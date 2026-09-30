-- ============================================================================
-- PATCH v5.4.2-14 — meter_governing_test() stops computing R-36's approval
--                    gate: the facts stay in the database, the law moves to
--                    the calculation core
-- ============================================================================
-- Authority:   Ryan, 2026-09-28: the schema REPRESENTS rules and the C# core
--              EVALUATES them; "a Texas-only launch does not mean a Texas-only
--              architecture". Texas-only audit (application/texas-only-
--              architecture-audit-2026-09-28.md) §3.3 and §6; v5.4.2-13
--              residual R8. Ryan, 2026-09-30: first of the follow-up patches
--              that move landed law out of the database.
--
-- NUMBERING.   This patch takes v5.4.2-14. The text of v5.4.2-13 (landed,
--              append-only) says "-14" for the delivery patch that makes a
--              frozen correction post (its residual R1, its status comment).
--              That patch is now v5.4.2-15. Read "-14" in -13 as "-15".
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--
--   v5.4.2-12's meter_governing_test(meter, anchor) returned a column,
--   supervisor_gate, computed as
--
--       weak_provenance AND (cutover_date IS NULL
--                            OR anchor − 6 months < cutover_date)
--
--   That is law, not record: Kyle's R-36 transitional approval gate, with
--   Texas's six months written into the database (audit §3.3 "6 months
--   buried in general code"). Whether an evaluation needs a supervisor's
--   approval is decided by the core, from the resolved rule's adverse
--   before_anchor term, the correction's direction and the tenant's cutover
--   (application/a2-rules-for-the-core.md §9.1), and recorded on the
--   evaluation (meter_correction_evaluations.approval_required, v5.4.2-13).
--   A 12-month state would otherwise get a gate that lapses six months early.
--
--   The function is re-created WITHOUT supervisor_gate. Everything else it
--   returns is a fact about the record and its logic is unchanged (compare
--   -12:1544-1618): the governing test (R-34's "last test of the meter"), its
--   kind, outcome and record_basis, entered_out_of_order, prior_test_failed,
--   the declared absence, and weak_provenance (none, or migrated_date_only:
--   what the row can prove). tenants.cutover_date stays where it is. The
--   core has every input the gate needs.
--
--   A column cannot be removed from a function's result by CREATE OR
--   REPLACE, so the function is dropped and created. Nothing in the schema
--   depends on it (no view, no function body reads it; v5.4.2-13 stopped).
--   Its grants are re-issued exactly: EXECUTE to tally_app, not to PUBLIC.
--
--   Four comments that described the database computing the gate are
--   re-issued, so the catalog no longer says it does.
--
-- WHAT DOES NOT CHANGE
--   * The cutover invariant (every migrated test on or before cutover, every
--     recorded test on or after it) and its platform-only setting. That is
--     record integrity: it is what makes "migrated" mean pre-go-live.
--   * Which test governs, and how same-date ties rank.
--
-- APPLICATION CONTRACT (AC-33). A caller of meter_governing_test() that
--   read supervisor_gate must compute the gate in the core instead. No
--   application code exists yet (Ryan, 2026-09-28), so nothing breaks.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. meter_governing_test() without the gate
-- ----------------------------------------------------------------------------
-- The body is v5.4.2-12's with the gate and the cutover lookup removed; the
-- selection, the ranking and every other column are unchanged.

DROP FUNCTION IF EXISTS public.meter_governing_test(uuid, date);

CREATE FUNCTION public.meter_governing_test(
        p_meter_id     uuid,
        p_anchor_date  date)
    RETURNS TABLE (
        meter_test_id         uuid,
        test_date             date,
        test_kind             text,
        outcome               text,
        record_basis          text,
        entered_out_of_order  boolean,
        prior_test_failed     boolean,
        absence               text,
        weak_provenance       boolean)
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_meter   record;
    v_test    record;
BEGIN
    IF p_meter_id IS NULL OR p_anchor_date IS NULL THEN
        RAISE EXCEPTION 'meter_governing_test: a meter and an anchor date are both required (got %, %) — there is no default anchor', p_meter_id, p_anchor_date
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT m.id, m.tenant_id, m.test_history_absence INTO v_meter
      FROM public.meters m WHERE m.id = p_meter_id;
    IF v_meter.id IS NULL THEN
        RAISE EXCEPTION 'meter_governing_test: meter % is not visible to this session', p_meter_id
            USING ERRCODE = 'no_data_found';
    END IF;

    SELECT t.id, t.test_date, t.test_kind, t.outcome, t.record_basis, t.entered_out_of_order, t.found_defective INTO v_test
      FROM public.meter_tests t
     WHERE t.meter_id = p_meter_id AND t.tenant_id = v_meter.tenant_id
       AND t.test_date < p_anchor_date
       AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id)
     ORDER BY t.test_date DESC,
              (t.load_results IS NOT NULL) DESC,
              (t.found_defective IS TRUE AND t.load_results IS NULL) DESC,
              (t.outcome IS NOT NULL) DESC,
              array_position(ARRAY['migrated_date_only', 'migrated_full', 'recorded'], t.record_basis) DESC,
              t.recorded_seq DESC
     LIMIT 1;

    meter_test_id        := v_test.id;
    test_date            := v_test.test_date;
    test_kind            := v_test.test_kind;
    outcome              := v_test.outcome;
    record_basis         := v_test.record_basis;
    entered_out_of_order := v_test.entered_out_of_order;
    prior_test_failed    := coalesce(v_test.found_defective, false);
    absence              := CASE WHEN v_test.id IS NULL
                                 THEN coalesce(v_meter.test_history_absence, 'undeclared') END;
    weak_provenance      := v_test.id IS NULL OR v_test.record_basis = 'migrated_date_only';
    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.meter_governing_test(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.meter_governing_test(uuid, date) TO tally_app;

COMMENT ON FUNCTION public.meter_governing_test(uuid, date) IS
    'v5.4.2-12 (R-34, R-35); v5.4.2-14 (the R-36 gate moved to the core). "The last test of the meter": the most recent non-superseded test on the same meter dated strictly before p_anchor_date, whatever its outcome or kind. Always one row; where none qualifies the test columns are NULL and absence reports the tenant''s declaration (or undeclared) — never an inferred date (R-31; install_date, test_interval_months and next_test_due_date are not read). prior_test_failed = the governing test itself found the meter defective (found_defective), a data-integrity flag for the operator (R-34) and not a reason to skip it. weak_provenance = no test, or a migrated_date_only one: what the record can prove. It computes no law: whether a correction needs a supervisor''s approval (R-36) is the calculation core''s, from the resolved rule, the direction and tenants.cutover_date (application/a2-rules-for-the-core.md §9.1), recorded on meter_correction_evaluations.approval_required. Invoker rights: an invisible meter raises.';


-- ----------------------------------------------------------------------------
-- 2. Comments that said the database computes the gate
-- ----------------------------------------------------------------------------

COMMENT ON COLUMN public.tenants.cutover_date IS
    'v5.4.2-12. The date this utility went live on Tally — the boundary between migrated and recorded meter test history: every migrated test is dated on or before it and every recorded test on or after it. Set by the platform (a platform administrator, or the owner at onboarding), never by the tenant. May change only within those bounds, and not back to NULL once history exists. NULL = not yet cut over: no test may be recorded yet. The calculation core reads it for transitional rules that turn on go-live, such as Texas''s R-36 approval gate on weakly evidenced adverse corrections (v5.4.2-14 moved that gate out of the database). Changes are logged in tenant_configuration_history. Also the home Kyle''s R-37 record asks for.';

COMMENT ON COLUMN public.meter_tests.record_basis IS
    'What the row can prove (R-35 / R-36). recorded = captured in Tally at or after the test, full field list. migrated_full = loaded at onboarding with the full field list. migrated_date_only = loaded with a date and at most a result — exactly what the (7)(B)(i) equipment record requires, so not deficient (F-2), but it cannot win a dispute over the test''s accuracy. A date-only row still anchors a window (R-36), marked weak_provenance by meter_governing_test(); whether that needs a supervisor''s approval is the calculation core''s (v5.4.2-14). Migrated rows must be dated on or before tenants.cutover_date.';

COMMENT ON TABLE public.meter_test_absence_declarations IS
    'v5.4.2-12 (R-35 refinements 2 and 4). What a tenant declares about a meter''s missing test history — attested_none or unknown — with the basis. It describes the history BEFORE the meter''s earliest recorded test, so a declaration on a meter that has tests is not a contradiction: meter_governing_test() reports it only for an anchor no test precedes. Append-only; the latest row per meter is meters.test_history_absence. What an absence means for a correction — in Texas, no bar: the months term governs alone, behind the R-36 gate during the transitional period (R-35 refinement 5) — is the calculation core''s.';


-- ----------------------------------------------------------------------------
-- 3. Residuals, stated
-- ----------------------------------------------------------------------------
-- R1. TEXT ONLY. -12's enforce_tenant_cutover_date() still explains its two
--     refusals in terms of "R-36's six-month gate", and -12's section comments
--     in tu.sql say the gate lapses at cutover + 6 months. The refusals
--     themselves are record integrity and correct; the wording is Texas-
--     shaped. Re-issuing the function for its messages is left for the next
--     patch that touches it.
--
-- R2. THE GATE'S SCOPE IS STILL FOR KYLE (a2-rules-for-the-core.md D3): which
--     causes it covers, and whether an attested_none or unknown meter gates
--     without a cause qualifier. The core's rule, not the schema's.

-- ----------------------------------------------------------------------------
-- 4. The AC-32 tail
-- ----------------------------------------------------------------------------
-- No new tables or views. The assertion still runs, as every patch's does.

SELECT public.assert_tenant_isolation_invariants();

-- ============================================================================
-- END PATCH v5.4.2-14
-- ============================================================================
