-- An evaluation cites TX protected estimation_catchup (no window terms = uncapped) ...
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
WITH x AS (INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from)
  VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013e8','estimation_catchup',
          DATE '2026-05-01','discovery_date', DATE '2025-01-01') RETURNING id)
INSERT INTO b13 SELECT 'case', id FROM x;
WITH x AS (INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, claimed_from, rule_id,
         adverse_window_start, approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case'), 'estimation_catchup', DATE '2026-05-01', 'discovery_date',
          DATE '2025-01-01', pg_temp.r('protected','estimation_catchup'), NULL, false, '{}', 'fp', 'core-0.0.0') RETURNING id)
INSERT INTO b13 SELECT 'ev', id FROM x;
RESET ROLE;   -- the owner (platform migration path), which the history trigger claims to bind too
-- (a) add a 3-month adverse term to the CITED rule: the rule row now says the window was 3 months
INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
VALUES (pg_temp.r('protected','estimation_catchup'), 'adverse', 'months_before_anchor', 3);
-- (b) close the cited rule retroactively, to before the dates the evaluation applied it to
UPDATE public.backbilling_rules SET effective_to = DATE '2004-07-13' WHERE id = (SELECT rule_id FROM public.meter_correction_evaluations WHERE id = pg_temp.id('ev'));
-- (c) rewrite the citation of a class every rule row keys on
UPDATE public.backbilling_customer_classes SET source_note = 'rewritten', description = 'rewritten' WHERE state_code='TX' AND class_code='protected';
UPDATE public.backbilling_causes SET description = 'rewritten' WHERE cause_code = 'meter_error';
SELECT 'OBSERVED' AS what, b.effective_from, b.effective_to,
       (SELECT count(*) FROM public.backbilling_rule_window_terms t WHERE t.rule_id = b.id) AS terms_now,
       v.anchor_date AS eval_anchor
  FROM public.meter_correction_evaluations v JOIN public.backbilling_rules b ON b.id = v.rule_id WHERE v.id = pg_temp.id('ev');
SELECT source_note FROM public.backbilling_customer_classes WHERE state_code='TX' AND class_code='protected';
ROLLBACK;
