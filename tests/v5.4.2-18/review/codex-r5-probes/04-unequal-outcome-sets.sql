-- Run ONLY as the migration owner on a disposable PRE-18 clone named codex18... .
-- psql -X -v ON_ERROR_STOP=1 -d codex18r5probe -f THIS_FILE
-- Self-contained: exact frozen r5 patch embedded below (md5 ee7ccdfb56da2f0fa8ac717bce421d81).
-- No PostgreSQL execution by Codex. Success rolls back; an expected error exits psql,
-- whose disconnect rolls back. Do not run via an interactive include and then commit.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = '';
SET LOCAL check_function_bodies = on;
SET LOCAL transaction_isolation = 'read committed';
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex18%' THEN RAISE EXCEPTION 'Use a disposable codex18... clone'; END IF;
 IF to_regclass('public.backbilling_rule_window_terms') IS NULL THEN RAISE EXCEPTION 'Requires PRE-18 clone'; END IF;
 EXECUTE format('REVOKE TEMP ON DATABASE %I FROM PUBLIC, tally_app, tally_core', current_database());
END $$;
-- EXPECTED: check_violation containing 'facts about its cause' and 'differ from the protected row'; removing repeats must not remove distinct members. psql exits nonzero and rolls back.
INSERT INTO public.backbilling_rules (id, state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty, adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, effective_to, source_note) VALUES
('00000000-0000-4000-8000-000000001803', 'TX', 'gas', 'protected', 'meter_error', 'test_date', ARRAY['fast','fast'], 'mandatory', 'forfeit_whole', 'forfeit_whole', 'adjustment', false, false, 'never', DATE '1800-01-01', DATE '1801-01-01', 'Codex historical set fixture'),
('00000000-0000-4000-8000-000000001804', 'TX', 'gas', 'unprotected', 'meter_error', 'test_date', ARRAY['fast','slow','slow'], 'permitted', 'include_whole', 'include_whole', 'adjustment', false, false, 'uncapped', DATE '1800-01-01', DATE '1801-01-01', '16 TAC 7.45 does not reach this class; Codex historical set fixture');

-- BEGIN EXACT FROZEN R5 PATCH
-- ============================================================================
-- PATCH v5.4.2-18 — backbilling at the rule-terms convention: the 16 Texas
--                    rows adopted in place, the window terms and two
--                    vocabularies folded into the document
-- ============================================================================
-- Authority:   Ryan, 2026-10-07: the step-2 defaults (inventory §4 A) — "-13's
--              rows are adopted in place": each row keeps its id, dates and
--              stamps and gains a document that says exactly what its old
--              columns and window terms said, proved by the database before
--              the old columns are dropped. Ryan, 2026-10-09: go ahead on the
--              -13 migration (HANDOFF resume order; residual R14 of -17).
-- Spec:        application/rule-terms-step2-source-inventory-2026-10-07.md
--              (V2, V4, V6, V7, V8, F6, T3, T5, T6, C2, L1; §3 settled point 2;
--              §5 "whether the -13 rows are investor-owned only") and
--              -17's residuals R14, R23, R24.
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   * The KIND `backbilling` v1 (law) — its schema is law/backbilling/
--     backbilling.v1.schema.json, embedded here and compared with the file by
--     CI (W4). A document says: what the correction counts back from (a
--     strategy union: a test date, with the outcomes that make a finding this
--     cause, or the discovery date); the favourable duty; how a straddling
--     period is treated, each direction; the delivery path; whether the cause
--     needs supervisor evidence; whether units are invariant; what collection
--     may pursue (a strategy union: uncapped, months, never, conditional on
--     a named condition); and the window of each direction as a list of terms
--     (a union on the term's kind). Every law kind also admits the document
--     "the law leaves this to the utility" (V8).
--   * ONE FACET, `anchor_basis` (text, $.anchor.strategy, in
--     backbilling_anchor_bases): the column -13 already had, now derived from
--     the document, so a basis no vocabulary row names is refused where the
--     rule is written. Other content has no facet: no record guard reads it
--     (inventory F6); the core reads the document.
--   * backbilling_rules is REGISTERED as a law table that adopts its
--     pre-convention rows: area key (customer_class, cause); template columns
--     added (terms_kind, terms_version, terms_source, terms, owner_types,
--     system_kinds, commission_jurisdiction and the three spans); the sixteen
--     rows bind what 16 TAC §7.45 binds — investor_owned and cooperative
--     owners, distribution systems (a piped-propane or master-meter system
--     finds no row), either jurisdiction status (residuals R1, R8, R9); eight of
--     them — the class §7.45 "does not reach" — are DELEGATIONS to the utility,
--     not law (R10); each gets its document through the sanctioned one-time fill
--     (T6), which runs backbilling_rule_adoption_check: the document must say
--     what the old columns and child window terms said, key by key.
--   * The -13 guards that the template now does are dropped:
--     enforce_backbilling_rule_history (the template's history trigger closes
--     rows, with the same floor — backbilling_rule_close_floor — and also
--     takes the citation lock) and enforce_backbilling_rule_record (stamps:
--     the template's; the basis/outcomes pairing: the schema's union plus
--     backbilling_rule_insert_check). -13's own no-overlap exclusion, range
--     and note checks are replaced by the template's (which key the overlap
--     on owner, system and jurisdiction spans too: a city's delegated rule
--     may sit beside the investor-owned one).
--   * The ten content columns are DROPPED once every document is proved equal
--     (qualifying_test_outcomes, favourable_duty, adverse_straddle,
--     favourable_straddle, delivery_path, requires_supervisor_evidence,
--     units_invariant, enforce_scope, enforce_months, enforce_condition),
--     and so are backbilling_rule_window_terms, backbilling_window_term_kinds
--     and backbilling_enforce_conditions (the kinds and the condition are the
--     schema's: inventory §3 point 2). backbilling_anchor_bases, _causes and
--     _customer_classes stay tables: cases, evaluations and rules cite them.
--   * Comments that named the dropped columns point at the document.
--
-- ----------------------------------------------------------------------------
-- What the database refuses (beyond -17's template)
-- ----------------------------------------------------------------------------
--   A rule document that fails the schema: a missing window (an empty list is
--   written, never omitted), a month count under 1 or under a strategy that
--   takes none, a condition not named, an anchor on a test with no outcomes
--   or on any other basis with them, a window term of an unknown kind or with
--   a quantity on a kind that takes none; a window naming one kind twice in
--   a direction or one priority twice (insert check); a basis whose
--   vocabulary row disagrees with the document about resting on a test
--   (insert check). A fill that disagrees with the row's old columns or
--   window terms (adoption check).
--
-- PRECONDITION. -13 and -17 applied (tu.sql); every legacy row is a Texas gas
--   row (any other is refused: nobody ruled on who it binds); applied by a role
--   that sees every tenant (superuser or BYPASSRLS — the template's fill is "a
--   reviewed migration's act") under READ COMMITTED. The migration is one DO
--   block: it leaves the TABLE either fully migrated or untouched (the three
--   hook functions and the builder, created just before it, remain after an
--   abort; CREATE OR REPLACE makes that harmless). A second run finds the table
--   registered and does nothing. A -13 row on a basis or condition v1 does not
--   name (battery-13's old notice-date anchor) fails the fill with the
--   validator's message: fail closed, as it should.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. The area's hooks (read by the template; none writes)
-- ----------------------------------------------------------------------------

-- The latest day a citing record needs a rule row in force (the -13 floor,
-- unchanged: each evaluation's anchor and its own date, each evidence row's
-- period start). A close must end after it. Called by the template's history
-- trigger under the closing role, which sees every tenant's citations.
CREATE OR REPLACE FUNCTION public.backbilling_rule_close_floor(p_rule_id uuid) RETURNS date
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT max(d) FROM (
        SELECT greatest(v.anchor_date, v.evaluated_at::date) AS d
          FROM public.meter_correction_evaluations v WHERE v.rule_id = p_rule_id
        UNION ALL
        SELECT p.period_start FROM public.meter_correction_period_evidence p WHERE p.rule_id = p_rule_id
    ) c
$$;
COMMENT ON FUNCTION public.backbilling_rule_close_floor(uuid) IS
    'v5.4.2-18. The close floor of a backbilling_rules row (rule_tables.close_floor): the latest date any evaluation (its anchor, its evaluation date) or evidence row (its period start) cites the row for, or NULL. Which date picks a rule row is the core''s (-13 R3), so the floor covers every candidate. Carried over from -13''s enforce_backbilling_rule_history.';

-- What only the area can say about a new row: the basis vocabulary and the
-- document agree about resting on a test (-13's record guard, which read the
-- vocabulary; the schema's union says the same in its own words, so a
-- vocabulary row altered under it is caught where the rule is written), and a
-- direction's window names a kind once and a priority once (-13's two unique
-- constraints on the child table, which a list cannot carry).
CREATE OR REPLACE FUNCTION public.backbilling_rule_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_terms   jsonb := p_row -> 'terms';
    v_on_test boolean;
    v_dir     text;
    v_dup     text;
    v_who     text := format('backbilling rule (%s %s)', p_row ->> 'customer_class', p_row ->> 'cause');
BEGIN
    IF v_terms ->> 'governs' IS DISTINCT FROM 'law' THEN
        RETURN;
    END IF;
    SELECT a.rests_on_test INTO v_on_test FROM public.backbilling_anchor_bases a WHERE a.basis_code = v_terms -> 'anchor' ->> 'strategy';
    IF v_on_test IS DISTINCT FROM ((v_terms -> 'anchor') ? 'qualifying_outcomes') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the anchor basis %s has rests_on_test = %s in backbilling_anchor_bases, but its document %s qualifying outcomes — a rule on a test basis names the test outcomes that make a finding its cause (R-39), a rule on any other basis names none (v5.4.2-18)',
                             v_who, v_terms -> 'anchor' ->> 'strategy', v_on_test, CASE WHEN (v_terms -> 'anchor') ? 'qualifying_outcomes' THEN 'names' ELSE 'names no' END),
            ERRCODE = 'check_violation';
    END IF;
    IF (v_terms -> 'anchor') ? 'qualifying_outcomes' AND
       (SELECT array_agg(o ORDER BY n) IS DISTINCT FROM array_agg(o ORDER BY o COLLATE "C")
          FROM jsonb_array_elements_text(v_terms -> 'anchor' -> 'qualifying_outcomes') WITH ORDINALITY AS q(o, n)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the qualifying outcomes are listed out of order — in byte order, so one law has one document (v5.4.2-18)', v_who),
            ERRCODE = 'check_violation';
    END IF;
    FOREACH v_dir IN ARRAY ARRAY['adverse', 'favourable'] LOOP
        SELECT t ->> 'kind' INTO v_dup FROM jsonb_array_elements(v_terms -> 'windows' -> v_dir) t
         GROUP BY t ->> 'kind' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;
        IF v_dup IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the %s window names the window-term kind %s twice — one term of a kind per direction (v5.4.2-18)', v_who, v_dir, v_dup),
                ERRCODE = 'check_violation';
        END IF;
        IF (SELECT array_agg(t ->> 'kind' ORDER BY o) IS DISTINCT FROM array_agg(t ->> 'kind' ORDER BY t ->> 'kind' COLLATE "C")
              FROM jsonb_array_elements(v_terms -> 'windows' -> v_dir) WITH ORDINALITY AS e(t, o)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the %s window lists its terms out of order — by kind, in byte order, so one law has one document (v5.4.2-18)', v_who, v_dir),
                ERRCODE = 'check_violation';
        END IF;
        SELECT t ->> 'priority' INTO v_dup FROM jsonb_array_elements(v_terms -> 'windows' -> v_dir) t
         WHERE t ? 'priority' GROUP BY t ->> 'priority' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;
        IF v_dup IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the %s window uses priority %s twice — a fallback chain orders its terms (v5.4.2-18)', v_who, v_dir, v_dup),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.backbilling_rule_insert_check(jsonb) IS
    'v5.4.2-18. The area predicate of backbilling_rules (rule_tables.insert_check), over the new row with its document: for a law document, the anchor basis the vocabulary names rests on a test exactly when the document names qualifying outcomes; no window-term kind and no priority is used twice in a direction, a direction lists its terms in order of kind (byte order), and the qualifying outcomes are in byte order. Raises check_violation. A delegated document has nothing to cross-check.';

-- The adoption check (T6), run only when a legacy row's empty document is
-- filled: the document must say what the row's OLD columns and its child
-- window terms said, key by key, so the message names the one that differs.
-- Written separately from the migration's document builder (P1b and the
-- battery's K2 are the fully independent proofs, typed apart from both). Two
-- limits, stated so nobody trusts it for more: the template passes the check
-- the row WITH its facets already derived from the document, so the anchor
-- basis in the row IS the document's strategy and is not compared here (the
-- template compares a writer-set facet with the derived one before the check
-- runs, and the outcomes comparison below flips with the strategy under v1);
-- and the citation uses the builder's own rule for the lead clause. The
-- citation is the lead clause of the row's source_note (the text before its
-- first " — " or ";"): derived, never invented.
-- A row whose note says 16 TAC 7.45 does not reach its class is a DELEGATION
-- ("the law leaves this to the utility", v2 §3), not law; the check demands
-- that, and demands that the old columns claimed nothing the delegation
-- drops: uncapped, permitted, whole periods, no supervisor evidence, no window terms.
CREATE OR REPLACE FUNCTION public.backbilling_rule_adoption_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_unreached CONSTANT text := '16 TAC 7.45 does not reach this class;%';
    v_t      jsonb := p_row -> 'terms';
    v_id     uuid := (p_row ->> 'id')::uuid;
    v_who    text := format('adopting backbilling rule %s (%s %s %s %s)', p_row ->> 'id', p_row ->> 'state_code', p_row ->> 'service_type',
                            p_row ->> 'customer_class', p_row ->> 'cause');
    v_unreached boolean := (p_row ->> 'source_note') LIKE c_unreached;
    v_dir    text;
    v_want   jsonb;
    v_have   jsonb;
    v_k      text;
BEGIN
    IF to_regclass('public.backbilling_rule_window_terms') IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the legacy window terms are gone, so a legacy row can no longer be adopted (v5.4.2-18)', v_who),
            ERRCODE = 'check_violation';
    END IF;
    -- The note and the class say the same thing, or the row is not adopted: neither a reworded note
    -- nor a mislabelled class may flip a row between law and delegation.
    IF v_unreached IS DISTINCT FROM ((p_row ->> 'customer_class') = 'unprotected') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: its note %s that 16 TAC 7.45 does not reach the class, but its class is %s — the note and the class must agree (v5.4.2-18)',
                             v_who, CASE WHEN v_unreached THEN 'says' ELSE 'does not say' END, p_row ->> 'customer_class'),
            ERRCODE = 'check_violation';
    END IF;
    IF v_unreached THEN
        IF v_t ->> 'governs' IS DISTINCT FROM 'delegated_to_utility' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: its note says 16 TAC 7.45 does not reach this class, so it is a delegation to the utility, not law (v5.4.2-18)', v_who),
                ERRCODE = 'check_violation';
        END IF;
        IF (v_t ->> 'citation') IS DISTINCT FROM '16 TAC 7.45' OR (v_t ->> 'note') IS DISTINCT FROM (p_row ->> 'source_note') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the delegation cites %L with note %L; it cites 16 TAC 7.45 and carries the source note whole (v5.4.2-18)', v_who, v_t ->> 'citation', v_t ->> 'note'),
                ERRCODE = 'check_violation';
        END IF;
        IF p_row ->> 'enforce_scope' IS DISTINCT FROM 'uncapped' OR p_row ->> 'favourable_duty' IS DISTINCT FROM 'permitted'
           OR p_row ->> 'adverse_straddle' IS DISTINCT FROM 'include_whole' OR p_row ->> 'favourable_straddle' IS DISTINCT FROM 'include_whole'
           OR (p_row -> 'requires_supervisor_evidence') IS DISTINCT FROM 'false'::jsonb
           OR EXISTS (SELECT 1 FROM public.backbilling_rule_window_terms w WHERE w.rule_id = v_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: a delegation drops what the old columns claimed (enforcement %s, duty %s, straddles %s / %s, supervisor evidence %s, window terms): they must claim nothing (v5.4.2-18)',
                                 v_who, p_row ->> 'enforce_scope', p_row ->> 'favourable_duty', p_row ->> 'adverse_straddle', p_row ->> 'favourable_straddle',
                                 p_row ->> 'requires_supervisor_evidence'),
                ERRCODE = 'check_violation';
        END IF;
        -- What a delegation drops that is not a claim about 7.45's reach: the facts about the CAUSE
        -- (R-39, R-33 — the outcomes that decide it, whether units stay, how it is delivered; the anchor goes
        -- with the outcomes, and the fill has already cleared it from the row). They must be what the
        -- protected row(s) of the same cause overlapping its dates say — and there must be one — so
        -- their loss is deliberate and stated (R10), not a different classification dropped unseen.
        IF NOT EXISTS (SELECT 1 FROM public.backbilling_rules q
                        WHERE q.state_code = p_row ->> 'state_code' AND q.service_type = p_row ->> 'service_type' AND q.cause = p_row ->> 'cause'
                          AND q.customer_class = 'protected'
                          AND daterange(q.effective_from, q.effective_to, '[)')
                              && daterange((p_row ->> 'effective_from')::date, (p_row ->> 'effective_to')::date, '[)')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: no protected row of the same cause overlaps its dates, so the facts about its cause (outcomes, units, delivery path) that a delegation drops have nothing to be compared with (v5.4.2-18)', v_who),
                ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.backbilling_rules q
                    WHERE q.state_code = p_row ->> 'state_code' AND q.service_type = p_row ->> 'service_type' AND q.cause = p_row ->> 'cause'
                      AND q.customer_class = 'protected'
                      AND daterange(q.effective_from, q.effective_to, '[)')
                          && daterange((p_row ->> 'effective_from')::date, (p_row ->> 'effective_to')::date, '[)')
                      AND ((SELECT array_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM unnest(q.qualifying_test_outcomes) o) u)
                             IS DISTINCT FROM (CASE WHEN jsonb_typeof(p_row -> 'qualifying_test_outcomes') = 'array'
                                                    THEN (SELECT array_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM jsonb_array_elements_text(p_row -> 'qualifying_test_outcomes') o) u) END)
                           OR q.units_invariant IS DISTINCT FROM (p_row ->> 'units_invariant')::boolean
                           OR q.delivery_path IS DISTINCT FROM p_row ->> 'delivery_path')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the facts about its cause (outcomes, units, delivery path) differ from the protected row of the same cause; a delegation drops them, so they must be the same classification (v5.4.2-18)', v_who),
                ERRCODE = 'check_violation';
        END IF;
        RETURN;
    END IF;
    IF v_t ->> 'governs' IS DISTINCT FROM 'law' THEN
        RAISE EXCEPTION USING MESSAGE = format('%s: a row whose note does not say 7.45 does not reach it is law, not a delegation (v5.4.2-18)', v_who), ERRCODE = 'check_violation';
    END IF;
    -- Scalars, each against its old column.
    FOREACH v_k IN ARRAY ARRAY['favourable_duty', 'adverse_straddle', 'favourable_straddle', 'delivery_path',
                               'requires_supervisor_evidence', 'units_invariant'] LOOP
        IF (v_t -> v_k) IS DISTINCT FROM (p_row -> v_k) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the document says %s = %s, the old column %s (v5.4.2-18)', v_who, v_k, v_t -> v_k, p_row -> v_k),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    IF (v_t ->> 'citation') IS DISTINCT FROM btrim(substring(p_row ->> 'source_note' from '^(.*?)(?: — |;|$)')) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the document cites %L, the lead clause of the source note is %L (v5.4.2-18)', v_who, v_t ->> 'citation',
                             btrim(substring(p_row ->> 'source_note' from '^(.*?)(?: — |;|$)'))),
            ERRCODE = 'check_violation';
    END IF;
    -- The anchor's version, and its outcomes as a set (the document lists them in byte order).
    IF (v_t -> 'anchor' -> 'version') IS DISTINCT FROM to_jsonb(1) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the document anchors on version %s of %s (v5.4.2-18)', v_who, v_t -> 'anchor' -> 'version', v_t -> 'anchor' ->> 'strategy'),
            ERRCODE = 'check_violation';
    END IF;
    SELECT CASE WHEN jsonb_typeof(p_row -> 'qualifying_test_outcomes') = 'array'
                THEN (SELECT jsonb_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM jsonb_array_elements_text(p_row -> 'qualifying_test_outcomes') o) u) END
      INTO v_want;
    IF (v_t -> 'anchor' -> 'qualifying_outcomes') IS DISTINCT FROM v_want THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the document names qualifying outcomes %s, the old column %s (v5.4.2-18)', v_who, v_t -> 'anchor' -> 'qualifying_outcomes', p_row -> 'qualifying_test_outcomes'),
            ERRCODE = 'check_violation';
    END IF;
    -- Enforcement: the scope, with its months or condition exactly where the old CHECKs put them.
    IF (v_t -> 'enforcement' ->> 'strategy') IS DISTINCT FROM (p_row ->> 'enforce_scope')
       OR (v_t -> 'enforcement' -> 'version') IS DISTINCT FROM to_jsonb(1)
       OR (v_t -> 'enforcement' -> 'months') IS DISTINCT FROM (CASE WHEN p_row ->> 'enforce_months' IS NOT NULL THEN p_row -> 'enforce_months' END)
       OR (v_t -> 'enforcement' -> 'condition') IS DISTINCT FROM (CASE WHEN p_row ->> 'enforce_condition' IS NOT NULL THEN p_row -> 'enforce_condition' END) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the document enforces %s, the old columns say %s, months %s, condition %s (v5.4.2-18)', v_who, v_t -> 'enforcement',
                             p_row ->> 'enforce_scope', p_row ->> 'enforce_months', p_row ->> 'enforce_condition'),
            ERRCODE = 'check_violation';
    END IF;
    -- Windows: each direction's terms, as a set, against the child rows.
    FOREACH v_dir IN ARRAY ARRAY['adverse', 'favourable'] LOOP
        SELECT coalesce(jsonb_agg(e ORDER BY e::text), '[]') INTO v_want
          FROM (SELECT jsonb_strip_nulls(jsonb_build_object('kind', w.term_kind, 'quantity', w.quantity, 'unit', w.unit, 'priority', w.priority)) AS e
                  FROM public.backbilling_rule_window_terms w WHERE w.rule_id = v_id AND w.direction = v_dir) x;
        SELECT coalesce(jsonb_agg(e ORDER BY e::text), '[]') INTO v_have
          FROM jsonb_array_elements(coalesce(v_t -> 'windows' -> v_dir, '[]')) e;
        IF v_want IS DISTINCT FROM v_have THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the document''s %s window is %s, the legacy window terms are %s (v5.4.2-18)', v_who, v_dir, v_have, v_want),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.backbilling_rule_adoption_check(jsonb) IS
    'v5.4.2-18 (inventory T6). rule_tables.adoption_check of backbilling_rules: run once per legacy row, when its empty document is filled, with the row as it stands (old columns, the new document, its facets — so the anchor basis in the row is already the document''s). A row whose note says 16 TAC 7.45 does not reach its class must be a delegation citing 16 TAC 7.45 and carrying the note whole, over old columns that claimed nothing; any other row must be law, equal to its old columns key by key — duties, straddles, delivery path, the two flags, the citation (the lead clause of the source note), the anchor version and its outcomes (as a set), the enforcement and its months or condition — with each direction''s window equal to the legacy child window terms as a set. Raises check_violation naming the key that differs. Needs the legacy table: once it is dropped, no legacy row can be adopted.';


-- ----------------------------------------------------------------------------
-- 2. The migration's document builder (dropped when the migration ends)
-- ----------------------------------------------------------------------------
-- Builds a legacy row's document from its old columns and child window terms.
-- The adoption check above compares the result key by key with the same
-- columns, written separately; the battery (K) and migration-18.sh compare it
-- with expectations typed from the -13 seed, apart from both.
CREATE OR REPLACE FUNCTION public.backbilling_rule_legacy_document(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    r     jsonb;
    v_win jsonb;
BEGIN
    SELECT to_jsonb(b) INTO r FROM public.backbilling_rules b WHERE b.id = p_id;
    -- 16 TAC 7.45 does not reach the class: the law leaves the matter to the utility.
    IF (r ->> 'source_note') LIKE '16 TAC 7.45 does not reach this class;%' THEN
        RETURN jsonb_build_object('governs', 'delegated_to_utility', 'citation', '16 TAC 7.45', 'note', r ->> 'source_note');
    END IF;
    SELECT jsonb_object_agg(d.direction, d.terms) INTO v_win
      FROM (SELECT dd AS direction,
                   coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('kind', w.term_kind, 'quantity', w.quantity, 'unit', w.unit, 'priority', w.priority))
                                              ORDER BY w.term_kind COLLATE "C")
                               FROM public.backbilling_rule_window_terms w WHERE w.rule_id = p_id AND w.direction = dd), '[]') AS terms
              FROM unnest(ARRAY['adverse', 'favourable']) dd) d;
    RETURN jsonb_build_object(
        'governs', 'law',
        'citation', btrim(substring(r ->> 'source_note' from '^(.*?)(?: — |;|$)')),
        'anchor', jsonb_strip_nulls(jsonb_build_object('strategy', r ->> 'anchor_basis', 'version', 1,
                                                       'qualifying_outcomes', CASE WHEN jsonb_typeof(r -> 'qualifying_test_outcomes') = 'array'
                                                            THEN (SELECT jsonb_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM jsonb_array_elements_text(r -> 'qualifying_test_outcomes') o) u) END)),
        'favourable_duty', r -> 'favourable_duty',
        'adverse_straddle', r -> 'adverse_straddle',
        'favourable_straddle', r -> 'favourable_straddle',
        'delivery_path', r -> 'delivery_path',
        'requires_supervisor_evidence', r -> 'requires_supervisor_evidence',
        'units_invariant', r -> 'units_invariant',
        'enforcement', jsonb_strip_nulls(jsonb_build_object('strategy', r ->> 'enforce_scope', 'version', 1,
                                                            'months', r -> 'enforce_months', 'condition', r -> 'enforce_condition')),
        'windows', v_win);
END;
$$;


-- ----------------------------------------------------------------------------
-- 3. The migration
-- ----------------------------------------------------------------------------
-- One transaction (a DO block). Order, after -17's R14: the kind and its facet
-- first (the facet must share its schema's transaction); the template
-- columns, with their defaults evaluated once — no row is updated, so -13's
-- history guard never sees them; the cross-checks that need no edit; -13's
-- own guards and constraints dropped; registration (which runs the fill's
-- checks on every legacy row); the fill; the proof that identity columns did
-- not move; and only then the old columns, the child table and the two
-- vocabularies dropped.
DO $migration$
DECLARE
    c_owner_types CONSTANT text[] := ARRAY['investor_owned', 'cooperative'];
    v_before   text;
    v_after    text;
    v_count    integer;
    v_count2   integer;
    v_unfilled integer;
    v_other    text;
    r          record;
BEGIN
    IF EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = 'public.backbilling_rules'::regclass) THEN
        RAISE NOTICE 'v5.4.2-18: backbilling_rules is already on the rule-terms convention; nothing to do';
        RETURN;
    END IF;
    -- The one applicability this migration writes is 16 TAC 7.45's, a Texas gas rule: a legacy row of any
    -- other state or service was never ruled on here, and is not given someone else's owner types.
    SELECT string_agg(format('%s (%s %s %s %s)', b.id, b.state_code, b.service_type, b.customer_class, b.cause), ', ' ORDER BY b.id) INTO v_other
      FROM public.backbilling_rules b WHERE b.state_code <> 'TX' OR b.service_type <> 'gas';
    IF v_other IS NOT NULL THEN
        RAISE EXCEPTION 'v5.4.2-18: backbilling_rules holds rows other than Texas gas, whose owner types nobody ruled on: %', v_other
            USING ERRCODE = 'check_violation', HINT = 'Decide who each binds, set owner_types and the spans first (R14 of -17), then adopt.';
    END IF;

    -- A delegation has no anchor, so the fill clears the anchor of every row that delegates. That loss is
    -- allowed only for an anchor that is the protected twin's (same cause, overlapping its dates):
    -- a different one is a classification nobody agreed to drop, and the fill can no longer see it.
    SELECT string_agg(format('%s (%s %s, anchor %s, its protected twin %s)', b.id, b.customer_class, b.cause, b.anchor_basis, q.anchor_basis), ', ' ORDER BY b.id) INTO v_other
      FROM public.backbilling_rules b
      JOIN public.backbilling_rules q ON q.state_code = b.state_code AND q.service_type = b.service_type AND q.cause = b.cause AND q.customer_class = 'protected'
                                     AND daterange(q.effective_from, q.effective_to, '[)') && daterange(b.effective_from, b.effective_to, '[)')
     WHERE b.source_note LIKE '16 TAC 7.45 does not reach this class;%' AND q.anchor_basis IS DISTINCT FROM b.anchor_basis;
    IF v_other IS NOT NULL THEN
        RAISE EXCEPTION 'v5.4.2-18: a delegation drops its anchor, and these anchors differ from their protected twin''s, so the loss was not deliberate: %', v_other
            USING ERRCODE = 'check_violation', HINT = 'Decide which anchor is right, set it on the delegation (or the twin) first, then adopt.';
    END IF;

    -- What must not move: the identity, key, dates, note and stamps of every row.
    SELECT count(*), md5(string_agg(row(b.id, b.state_code, b.service_type, b.customer_class, b.cause,
                                       CASE WHEN b.source_note LIKE '16 TAC 7.45 does not reach this class;%' THEN NULL ELSE b.anchor_basis END, b.effective_from,
                                       b.effective_to, b.source_note, b.created_at, b.recorded_txid, b.closed_at, b.closed_by)::text, '|' ORDER BY b.id))
      INTO v_count, v_before FROM public.backbilling_rules b;

    -- 3.1 The kind and its facet.
    INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
    VALUES ('backbilling', 1, 'law', $schema${
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/backbilling/backbilling.v1.schema.json",
  "title": "Backbilling rule, version 1",
  "description": "What a state's law says about correcting a past bill, for one customer class and one cause: what the correction counts back from, how far back it may reach in each direction, how a straddling period is treated, how the correction reaches a bill, and what collection may pursue. Written from public.backbilling_rules (v5.4.2-13) and its window-term child table, which this kind replaces. Every law kind also admits the document 'the law leaves this to the utility'.",
  "oneOf": [
    {"$ref": "#/$defs/law"},
    {"$ref": "#/$defs/delegated"}
  ],
  "$defs": {
    "citation": {"type": "string", "pattern": "[A-Za-z0-9]"},
    "delegated": {
      "type": "object",
      "additionalProperties": false,
      "required": ["governs", "citation"],
      "properties": {
        "governs": {"type": "string", "const": "delegated_to_utility"},
        "citation": {"type": "string", "pattern": "[A-Za-z0-9]"},
        "note": {"type": "string", "pattern": "[A-Za-z0-9]"}
      }
    },
    "law": {
      "type": "object",
      "additionalProperties": false,
      "required": ["governs", "citation", "anchor", "favourable_duty", "adverse_straddle", "favourable_straddle", "delivery_path",
                   "requires_supervisor_evidence", "units_invariant", "enforcement", "windows"],
      "properties": {
        "governs": {"type": "string", "const": "law"},
        "citation": {"$ref": "#/$defs/citation"},
        "anchor": {"oneOf": [{"$ref": "#/$defs/anchor_test_date"}, {"$ref": "#/$defs/anchor_discovery_date"}]},
        "favourable_duty": {
          "type": "string", "enum": ["mandatory", "permitted"],
          "description": "Must the utility correct in the customer's favour back to the window (a duty), or may it (a permission)?"
        },
        "adverse_straddle": {"$ref": "#/$defs/straddle"},
        "favourable_straddle": {"$ref": "#/$defs/straddle"},
        "delivery_path": {
          "type": "string", "enum": ["adjustment", "reissue", "unruled"],
          "description": "How the correction reaches a bill. 'unruled' is honest: the law (or Kyle's OQ-1) has not settled it, and it is not a default."
        },
        "requires_supervisor_evidence": {
          "type": "boolean",
          "description": "Whether moving a case into this cause needs a supervisor and evidence (Texas: tampering_bypass, R-38 attachment 2). The core checks it."
        },
        "units_invariant": {
          "type": "boolean",
          "description": "Whether a correction under this cause leaves the billed units unchanged (correct units, wrong price)."
        },
        "enforcement": {"oneOf": [
          {"$ref": "#/$defs/enforce_uncapped"}, {"$ref": "#/$defs/enforce_months"},
          {"$ref": "#/$defs/enforce_never"}, {"$ref": "#/$defs/enforce_conditional"}]},
        "windows": {"$ref": "#/$defs/windows"}
      }
    },
    "straddle": {
      "type": "string", "enum": ["forfeit_whole", "prorate_days", "include_whole"],
      "description": "A billed period that begins before the window and ends inside it: forfeited whole, prorated by days, or included whole."
    },
    "anchor_test_date": {
      "type": "object",
      "additionalProperties": false,
      "required": ["strategy", "version", "qualifying_outcomes"],
      "properties": {
        "strategy": {"type": "string", "const": "test_date"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1},
        "qualifying_outcomes": {
          "type": "array", "minItems": 1, "maxItems": 3, "uniqueItems": true,
          "items": {"type": "string", "enum": ["fast", "slow", "non_registering"]},
          "description": "The test outcomes that make a finding this cause (R-39: the outcome decides the cause)."
        }
      },
      "description": "The date of the meter test that found the fault (backbilling_anchor_bases.test_date)."
    },
    "anchor_discovery_date": {
      "type": "object",
      "additionalProperties": false,
      "required": ["strategy", "version"],
      "properties": {
        "strategy": {"type": "string", "const": "discovery_date"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1}
      },
      "description": "The date the utility discovered the fault, with no test deciding it (backbilling_anchor_bases.discovery_date)."
    },
    "enforce_uncapped": {
      "type": "object",
      "additionalProperties": false,
      "required": ["strategy", "version"],
      "properties": {
        "strategy": {"type": "string", "const": "uncapped"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1}
      },
      "description": "Collection may pursue everything that was billed."
    },
    "enforce_months": {
      "type": "object",
      "additionalProperties": false,
      "required": ["strategy", "version", "months"],
      "properties": {
        "strategy": {"type": "string", "const": "months"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1},
        "months": {"type": "integer", "minimum": 1}
      },
      "description": "Collection may pursue a bill no older than this many months."
    },
    "enforce_never": {
      "type": "object",
      "additionalProperties": false,
      "required": ["strategy", "version"],
      "properties": {
        "strategy": {"type": "string", "const": "never"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1}
      },
      "description": "Collection may not pursue the correction."
    },
    "enforce_conditional": {
      "type": "object",
      "additionalProperties": false,
      "required": ["strategy", "version", "condition"],
      "properties": {
        "strategy": {"type": "string", "const": "conditional"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1},
        "condition": {
          "type": "string", "enum": ["read_beyond_utility_control"],
          "description": "read_beyond_utility_control: whether the missed or estimated read was beyond the utility's control (Texas R-30). Evaluated by the calculation core; a new condition is a new schema version plus a core change."
        }
      },
      "description": "Collection may pursue the correction only when the named condition holds."
    },
    "windows": {
      "type": "object",
      "additionalProperties": false,
      "required": ["adverse", "favourable"],
      "properties": {
        "adverse": {"$ref": "#/$defs/window"},
        "favourable": {"$ref": "#/$defs/window"}
      },
      "description": "How far back a correction may reach, per direction (adverse: the customer owes; favourable: the customer is owed). A direction with no terms is uncapped. HOW TERMS COMBINE: every term with no priority always applies; the terms WITH a priority form one fallback chain, of which only the first whose date is known (lowest priority number first) applies; the window starts at the LATEST of the applying dates. So 'the shorter of six months or the last test' is two unprioritised terms, and 'from when the error is known to have begun, otherwise half the time since the last test, never more than N months' is claimed_start priority 1, half_since_last_test priority 2 and before_anchor N months unprioritised. A kind appears at most once per direction, and a priority at most once per direction, and the terms are listed in order of kind (byte order), so one law has one document (the insert check)."
    },
    "window": {"type": "array", "maxItems": 8, "items": {"$ref": "#/$defs/term"}},
    "priority": {"type": "integer", "minimum": 1},
    "term": {"oneOf": [
      {"$ref": "#/$defs/term_before_anchor"}, {"$ref": "#/$defs/term_last_test_any_outcome"},
      {"$ref": "#/$defs/term_last_test_accurate"}, {"$ref": "#/$defs/term_half_since_last_test"},
      {"$ref": "#/$defs/term_deployment_start"}, {"$ref": "#/$defs/term_service_start"},
      {"$ref": "#/$defs/term_claimed_start"}]},
    "term_before_anchor": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind", "quantity", "unit"],
      "properties": {
        "kind": {"type": "string", "const": "before_anchor"},
        "quantity": {"type": "integer", "minimum": 1},
        "unit": {"type": "string", "enum": ["months", "days", "billing_periods"]},
        "priority": {"$ref": "#/$defs/priority"}
      },
      "description": "A quantity of months, days or billing periods back from the anchor."
    },
    "term_last_test_any_outcome": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind"],
      "properties": {
        "kind": {"type": "string", "const": "last_test_any_outcome"},
        "priority": {"$ref": "#/$defs/priority"}
      },
      "description": "The most recent completed test of the meter before the anchor, whatever it found (Texas R-34)."
    },
    "term_last_test_accurate": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind"],
      "properties": {
        "kind": {"type": "string", "const": "last_test_accurate"},
        "priority": {"$ref": "#/$defs/priority"}
      },
      "description": "The most recent test before the anchor that found the meter within tolerance."
    },
    "term_half_since_last_test": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind"],
      "properties": {
        "kind": {"type": "string", "const": "half_since_last_test"},
        "priority": {"$ref": "#/$defs/priority"}
      },
      "description": "Half the time between the last test before the anchor and the anchor."
    },
    "term_deployment_start": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind"],
      "properties": {
        "kind": {"type": "string", "const": "deployment_start"},
        "priority": {"$ref": "#/$defs/priority"}
      },
      "description": "When the meter went into service at the premise (R-37(a))."
    },
    "term_service_start": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind"],
      "properties": {
        "kind": {"type": "string", "const": "service_start"},
        "priority": {"$ref": "#/$defs/priority"}
      },
      "description": "When the customer's service at the premise began."
    },
    "term_claimed_start": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind"],
      "properties": {
        "kind": {"type": "string", "const": "claimed_start"},
        "priority": {"$ref": "#/$defs/priority"}
      },
      "description": "When the fault is known to have begun, as the case records it (claimed_from). A term the core cannot resolve because the case records no such date is unknown, not zero."
    }
  }
}$schema$::jsonb, DATE '2026-10-09',
            'Backbilling rule (correcting a past bill): the anchor, the window of each direction, straddles, delivery, supervisor evidence, units, and what collection may pursue',
            'law/backbilling/backbilling.v1.schema.json');
    INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, description)
    VALUES ('backbilling', 1, 'anchor_basis', 'text', '$.anchor.strategy', 'public.backbilling_anchor_bases', 'basis_code',
            'What the correction counts back from: a backbilling_anchor_bases row that cases and evaluations also cite. Absent on a delegated document.');

    -- 3.2 The template columns. Defaults are evaluated once at ADD COLUMN, so no row is
    -- updated (the history guard of -13 refuses every update but a close); they are
    -- dropped at once, so a new row's applicability is written by the template's trigger.
    ALTER TABLE public.backbilling_rules
        ADD COLUMN owner_types text[] DEFAULT ARRAY['investor_owned', 'cooperative'],
        ADD COLUMN system_kinds text[] DEFAULT ARRAY['distribution'],
        ADD COLUMN commission_jurisdiction boolean,
        ADD COLUMN owner_span int4multirange NOT NULL DEFAULT public.rule_applicability_span('owner_type', ARRAY['investor_owned', 'cooperative']),
        ADD COLUMN system_span int4multirange NOT NULL DEFAULT public.rule_applicability_span('system_kind', ARRAY['distribution']),
        ADD COLUMN jurisdiction_span int4range NOT NULL DEFAULT public.rule_jurisdiction_span(NULL),
        ADD COLUMN terms_kind text,
        ADD COLUMN terms_version integer,
        ADD COLUMN terms_source text,
        ADD COLUMN terms jsonb;
    ALTER TABLE public.backbilling_rules
        ALTER COLUMN owner_types DROP DEFAULT,
        ALTER COLUMN system_kinds DROP DEFAULT,
        ALTER COLUMN owner_span DROP DEFAULT,
        ALTER COLUMN system_span DROP DEFAULT,
        ALTER COLUMN jurisdiction_span DROP DEFAULT,
        ALTER COLUMN anchor_basis DROP NOT NULL;      -- a facet column allows NULL (-17 R23)
    IF EXISTS (SELECT 1 FROM public.backbilling_rules WHERE owner_types IS DISTINCT FROM c_owner_types OR system_kinds IS DISTINCT FROM ARRAY['distribution']) THEN
        RAISE EXCEPTION 'v5.4.2-18: the template columns did not take their defaults';
    END IF;

    -- 3.3 -13's own guards and constraints give way to the template's.
    DROP TRIGGER a_enforce_backbilling_rule_history ON public.backbilling_rules;
    DROP TRIGGER a_enforce_backbilling_rule_record ON public.backbilling_rules;
    ALTER TABLE public.backbilling_rules
        DROP CONSTRAINT backbilling_rules_no_overlap,
        DROP CONSTRAINT backbilling_rules_range_check,
        DROP CONSTRAINT backbilling_rules_source_note_check;

    -- 3.4 Registration: the template's checks on the columns and on every legacy row.
    PERFORM public.rule_table_register('public.backbilling_rules', 'law', 'backbilling', ARRAY['customer_class', 'cause'], ARRAY['anchor_basis'],
                                       'public.backbilling_rule_close_floor(uuid)', 'public.backbilling_rule_insert_check(jsonb)', NULL, NULL,
                                       'public.backbilling_rule_adoption_check(jsonb)');

    -- 3.5 The fill (T6): each row's document, validated and compared with its old columns.
    UPDATE public.backbilling_rules b
       SET terms_kind = 'backbilling', terms_version = 1, terms_source = public.backbilling_rule_legacy_document(b.id)::text,
           anchor_basis = CASE WHEN public.backbilling_rule_legacy_document(b.id) ->> 'governs' = 'law' THEN b.anchor_basis END   -- a delegation has no anchor
     WHERE b.terms IS NULL;
    SELECT count(*) INTO v_unfilled FROM public.backbilling_rules WHERE terms IS NULL OR terms_source IS NULL;
    IF v_unfilled > 0 THEN
        RAISE EXCEPTION 'v5.4.2-18: % backbilling rows were not adopted', v_unfilled;
    END IF;

    -- 3.6 Nothing but the document moved (and the anchor facet of a delegation, which has no anchor).
    SELECT md5(string_agg(row(b.id, b.state_code, b.service_type, b.customer_class, b.cause,
                              CASE WHEN b.source_note LIKE '16 TAC 7.45 does not reach this class;%' THEN NULL ELSE b.anchor_basis END, b.effective_from,
                              b.effective_to, b.source_note, b.created_at, b.recorded_txid, b.closed_at, b.closed_by)::text, '|' ORDER BY b.id)),
           count(*) INTO v_after, v_count2 FROM public.backbilling_rules b;
    IF v_after IS DISTINCT FROM v_before OR v_count2 IS DISTINCT FROM v_count THEN
        RAISE EXCEPTION 'v5.4.2-18: adoption moved a row''s identity, key, dates, note or stamps (before %, after %)', v_before, v_after;
    END IF;

    -- 3.7 The old columns, the child table and the two vocabularies go: their content is the documents.
    ALTER TABLE public.backbilling_rules
        DROP COLUMN qualifying_test_outcomes, DROP COLUMN favourable_duty, DROP COLUMN adverse_straddle, DROP COLUMN favourable_straddle,
        DROP COLUMN delivery_path, DROP COLUMN requires_supervisor_evidence, DROP COLUMN units_invariant,
        DROP COLUMN enforce_scope, DROP COLUMN enforce_months, DROP COLUMN enforce_condition;
    DROP TABLE public.backbilling_rule_window_terms;
    DROP TABLE public.backbilling_window_term_kinds;
    DROP TABLE public.backbilling_enforce_conditions;
    DROP FUNCTION public.enforce_backbilling_rule_history();
    DROP FUNCTION public.enforce_backbilling_rule_record();
    DROP FUNCTION public.enforce_backbilling_window_term_record();

    COMMENT ON TABLE public.backbilling_anchor_bases IS
        'A-2 (v5.4.2-13, review P1). What a backbilling correction counts back from. rests_on_test: a case on this basis names the meter test that found the fault and counts back from its date; otherwise the case names no test and records how far back the fault is claimed to reach (claimed_from). Platform-held vocabulary; a rule document names a basis as its anchor strategy (backbilling v1 names these two), so a new basis is a vocabulary row, a new schema version of the kind, and a core change (v5.4.2-18).';

    -- 3.8 Words that named the old columns name the document.
    FOR r IN SELECT d.objoid::regclass AS rel, d.objsubid, replace(d.description, t.old_text, t.new_text) AS txt
               FROM pg_description d
               JOIN (VALUES ('public.correction_run_targets'::regclass, 'backbilling_rules.delivery_path', 'the rule''s document (terms.delivery_path)'),
                            ('public.meter_correction_cases'::regclass, 'backbilling_rules.requires_supervisor_evidence', 'the rule''s document (terms.requires_supervisor_evidence)'),
                            ('public.meter_correction_period_evidence'::regclass, 'the cited rule''s enforce_scope', 'the cited rule''s enforcement (terms.enforcement)')
                    ) AS t(rel, old_text, new_text)
                 ON d.classoid = 'pg_class'::regclass AND d.objoid = t.rel AND d.description LIKE '%' || t.old_text || '%' LOOP
        IF r.objsubid = 0 THEN
            EXECUTE format('COMMENT ON TABLE %s IS %L', r.rel, r.txt);
        ELSE
            EXECUTE format('COMMENT ON COLUMN %s.%I IS %L', r.rel,
                           (SELECT a.attname FROM pg_attribute a WHERE a.attrelid = r.rel AND a.attnum = r.objsubid), r.txt);
        END IF;
    END LOOP;
END
$migration$;

-- The builder served this migration only (also on a database already migrated, where section 2 re-created it).
DROP FUNCTION IF EXISTS public.backbilling_rule_legacy_document(uuid);


-- ----------------------------------------------------------------------------
-- 4. Words, grants and the tail
-- ----------------------------------------------------------------------------
COMMENT ON TABLE public.backbilling_rules IS
    'A-2 (v5.4.2-13), on the rule-terms convention since v5.4.2-18. What a state''s law requires of a backbilling correction, per (state, service, owner types, customer class, cause, dates): one LAW row of the kind backbilling, platform-held, never edited — the one change is a stamped close above the close floor — and cited by evaluations and period evidence by id. The content is the row''s document (terms, validated against the registered schema backbilling v1): what the correction counts back from, the window of each direction, how a straddling period is treated, the delivery path, whether the cause needs supervisor evidence, whether units are invariant, and what collection may pursue. anchor_basis is a facet of the document. The owner types, system kinds and jurisdiction status a row binds are columns, with spans the exclusion uses: the sixteen Texas rows bind investor-owned and cooperative gas utilities running distribution systems (16 TAC 7.45; Utilities Code 101.003(7) excludes a municipal corporation); the eight of the unprotected class are delegations to the utility (7.45 does not reach it). A municipal utility, a propane or master-meter system finds no row: unknown law is not permission.';
COMMENT ON COLUMN public.backbilling_rules.anchor_basis IS
    'A facet of the document (terms.anchor.strategy): a backbilling_anchor_bases row, that cases and evaluations also cite. NULL when the document delegates to the utility.';
COMMENT ON FUNCTION public.enforce_backbilling_law_immutable() IS
    'v5.4.2-13 (parity; review P1), narrowed by v5.4.2-18. BEFORE UPDATE OR DELETE, every role, on backbilling_causes, backbilling_customer_classes and backbilling_anchor_bases: refused. (The window terms and the other two vocabularies it guarded are the rule document''s now.)';

REVOKE ALL ON FUNCTION public.backbilling_rule_close_floor(uuid), public.backbilling_rule_insert_check(jsonb), public.backbilling_rule_adoption_check(jsonb)
    FROM PUBLIC, tally_app, tally_core;

DO $$
BEGIN
    PERFORM public.assert_core_role_invariants();
    PERFORM public.assert_rule_table_invariants();
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE NOTICE 'v5.4.2-18: backbilling_rules is a registered law table with % rows on the convention; the table-level invariants hold.', (SELECT count(*) FROM public.backbilling_rules WHERE terms IS NOT NULL);
END
$$;


-- ----------------------------------------------------------------------------
-- 5. Residuals
-- ----------------------------------------------------------------------------
-- R1. WHO 16 TAC 7.45 BINDS (OWNERSHIP AND SYSTEM). The sixteen rows bind
--     investor_owned and cooperative utilities running distribution systems.
--     Utilities Code 101.003(7) makes a "gas utility" a person or river
--     authority that distributes gas for compensation, and excludes (A) a
--     municipal corporation, (B) production, gathering, LPG sales and
--     agricultural fuel, (C) vehicle fuel, (D) own use, (E) persons excluded
--     under 121.007 (LNG marine terminal pipelines) and (F) an electric
--     cooperative or subsidiary excluded by 121.008; none excludes a retail
--     gas distribution cooperative (Legislative Council file, read
--     2026-10-09). LPG distribution is excluded by (B)(ii), so a
--     piped_propane_distribution system finds no row; master_meter systems are
--     out by default (their vocabulary note cites 121.211(d), safety only) —
--     a question for Kyle (R9). A river authority is a gas utility under the
--     definition, but its owner type is political_subdivision or
--     special_district, which no row binds: the lookup fails closed for it,
--     where the statute would bind it (a gap to close with R2's rows once Kyle
--     has said how a river authority's service is regulated). Ownership is the
--     profile's fact (utility_service_profiles.owner_type).
-- R2. A CITY'S LAW IS A DELEGATED ROW NOT YET WRITTEN. For a municipal owner
--     the lookup refuses (no row binds it), as places finding 1 requires. A
--     `delegated_to_utility` row per (class, cause) for owner type municipal
--     says the city sets its own standards; it is written with the city's
--     tariff table (the -15 rewrite's pattern), not here. The template lets
--     it sit beside the investor-owned row (the exclusion keys on the owner
--     span).
-- R3. THE CITING RECORDS ARE UNCHANGED. Evaluations and period evidence cite
--     a rule row by plain foreign key; nothing checks the row was in force on
--     the date cited (-13 R3). The close floor holds them in range after the
--     fact. The core resolves a rule through rule_law_row_as_of and a
--     citing record calls rule_law_row_cite when those tables become
--     core-written (inventory C2).
-- R4. THE CITATION IS DERIVED. A document's `citation` is the lead clause of
--     the row's source_note (the text before its first " — " or ";"); the
--     rest of the note stays in source_note, verbatim. A per-section
--     citation (v2 §3) awaits the law file, where a clause is written once;
--     the three R-39 rows' lead clause is a ruling id, not a statute, and
--     the estimation row's is a statement; the real clauses go in when the
--     law file is rewritten (meter_error and non_registering enforce `never`
--     under (4)(E)(vi), which their lead clause leaves out).
-- R5. WINDOW TERMS ARE A LIST, THE RULES ARE CHECKED IN TWO PLACES. A kind
--     once and a priority once per direction, and the list in order of kind
--     (byte order), are the area's insert check; the schema carries each
--     kind's shape (a quantity and unit exactly on before_anchor). A chain's
--     order is its priority numbers, not its list position; the canonical
--     order exists so that equal law is equal text (a seed compares
--     documents exactly).
-- R6. A DROPPED TABLE CANNOT BE ADOPTED FROM. The adoption check reads the
--     legacy window terms; after this patch no legacy row exists, and the
--     check refuses (the table is gone) if one were ever to appear.
-- R8. INCORPORATED AREAS. 16 TAC 7.45's preamble applies the minimum
--     standards "in unincorporated areas" and orders each gas distribution
--     utility to write them into its service rules for incorporated areas "but
--     only to the extent that said minimum service standards do not conflict
--     with standards lawfully established within a particular municipality".
--     The rows therefore bind either commission_jurisdiction status (NULL):
--     the order reaches every gas distribution utility. What the database
--     cannot say is the per-premise carve-out where a city has set a
--     conflicting standard (commission_jurisdiction is a utility-wide profile
--     fact, not a premise's): such a premise is for the core and the utility's
--     tariff (a looser city standard would meet the template's "stricter,
--     never looser" check). Kyle question.
-- R9. MASTER-METER SYSTEMS. Whether 16 TAC 7.45 binds a master-meter operator
--     (TX Utilities Code 121.211(d) makes it safety-regulated only) is not
--     settled; they are out by default, which fails closed. Adding them later
--     is a new row for the same key, beside the sixteen (the exclusion keys
--     on the system span), not an edit.
-- R10. "DOES NOT REACH" IS A DELEGATION. The eight rows of the unprotected
--     class said, in their own note, that 16 TAC 7.45 does not reach the class
--     and ordinary limitations law and the utility's filed tariff govern. -13
--     stored them as rules with no caps (uncapped, permitted, whole periods);
--     here they are `delegated_to_utility` documents citing 16 TAC 7.45 with
--     the note whole, over old columns that claimed nothing about reach (no
--     cap, permitted, whole periods, no supervisor evidence, no window terms).
--     The meaning changes: the core read "uncapped" from a law row as the law
--     permitting it, but a delegation sends it to the utility's tariff, and
--     until a backbilling tariff table exists (the -15 pattern) it finds none
--     and refuses an unprotected-class case. Fail toward protection. (Opus r1
--     B2; Ryan to confirm.)
--     WHAT IS LOST, AND WHERE IT MUST LIVE. The old unprotected rows also
--     carried facts about the CAUSE that were not about 7.45's reach, written
--     by -13's seed by cause (R-39, R-33): the test outcomes that decide a
--     meter error (fast/slow) or a non-registering meter, "correct units, wrong
--     price" (units_invariant) for a rate misapplication, and the delivery
--     path (adjustment, reissue). They equal the protected row's, cause by
--     cause; the adoption check demands that (a delegation drops them only
--     when the protected row of the same cause says the same). After this
--     patch the core has nowhere to read them for an unprotected case: the
--     future backbilling tariff kind, or the core's own cause semantics, must
--     restate them, or an unprotected rate-misapplication case loses a
--     constraint -13 held. HANDOFF says so.
--     LIMITATIONS LAW. The statute of limitations on the debt still bounds an
--     unprotected case, and a delegation does not say so: the future tariff
--     comparator must bound a delegated window by limitations law (a tariff
--     claiming ten years must not pass "stricter, never looser" against a
--     delegation that carries no number). Kyle names the period.
-- R11. THREE ROWS ARE LAW-SHAPED PLACEHOLDERS. billing_constant_error,
--     crossed_meters and unbilled_service (protected class) store enforcement
--     `never` and empty windows; their note says "enforceable classification
--     referred to counsel — never pending, per fail-toward-protection". The
--     empty windows read the silence of 7.45; `never` is the platform's
--     interim policy stored as what the law says. When counsel rules, that is
--     a correction of a row wrong from its first day (-17 R2), not a change in
--     the law, and a close plus successor would date it falsely. Question for
--     Kyle and counsel; likewise whether the uncapped protected rows
--     (tampering_bypass; the empty windows of the R-39 rows) mean "no limit"
--     or "the tariff's limit".
-- R7. THE LAW FILE. law/backbilling/ holds the schema, its examples and
--     (see backbilling_rules.yaml) the sixteen rows as a law file whose seed
--     is a no-op on this database: a row that differs from its file raises.
-- ============================================================================
-- END PATCH v5.4.2-18
-- ============================================================================
-- END EXACT FROZEN R5 PATCH
DO $$ BEGIN RAISE EXCEPTION 'FAIL: unequal outcome sets were adopted'; END $$;
ROLLBACK;
