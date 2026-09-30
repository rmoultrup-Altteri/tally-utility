SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
-- A discovery case claiming the fault reaches back to 2026-01-01; the core evaluates it.
WITH x AS (INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013e8','billing_constant_error',
          DATE '2026-05-01','discovery_date', DATE '2026-01-01', 'customer_owes') RETURNING id)
INSERT INTO b13 SELECT 'case', id FROM x;
WITH x AS (INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, claimed_from, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case'), 'billing_constant_error', DATE '2026-05-01', 'discovery_date',
          'customer_owes', DATE '2026-01-01', pg_temp.r('protected','billing_constant_error'), false, '{"claimed_from":"2026-01-01"}', 'fp-A', 'core-0.0.0')
  RETURNING id)
INSERT INTO b13 SELECT 'ev', id FROM x;
-- App bug: the operator widens the claim to 2019 and flips direction; the app then freezes on the old evaluation.
UPDATE public.meter_correction_cases SET claimed_from = DATE '2019-01-01', direction = 'customer_owed'
 WHERE id = pg_temp.id('case');
UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev') WHERE id = pg_temp.id('case');
SELECT 'OBSERVED case' AS what, c.status, c.claimed_from AS case_claimed_from, c.direction AS case_direction,
       v.claimed_from AS eval_claimed_from, v.direction AS eval_direction
  FROM public.meter_correction_cases c JOIN public.meter_correction_evaluations v ON v.id = c.frozen_evaluation_id
 WHERE c.id = pg_temp.id('case');
-- Test-anchored: the case is re-pointed at another test of the same date; the evaluation records no discovering test.
RESET ROLE;
INSERT INTO b13 VALUES ('t1', pg_temp.rec('00000000-0000-4000-8000-0000000013e2', DATE '2026-05-15', 96));
INSERT INTO b13 VALUES ('t2', pg_temp.rec('00000000-0000-4000-8000-0000000013e2', DATE '2026-05-15', 104));
SET ROLE tally_app;
WITH x AS (INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013e2','meter_error', pg_temp.id('t1'),
          DATE '2026-05-15','test_date','customer_owes') RETURNING id)
INSERT INTO b13 SELECT 'case2', id FROM x;
WITH x AS (INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case2'), 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owes', pg_temp.r('protected','meter_error'), false, '{}', 'fp-B', 'core-0.0.0') RETURNING id)
INSERT INTO b13 SELECT 'ev2', id FROM x;
-- re-point at the FAST test (104) and flip direction, freeze on the slow-test evaluation
UPDATE public.meter_correction_cases SET discovering_test_id = pg_temp.id('t2'), direction = 'customer_owed' WHERE id = pg_temp.id('case2');
UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev2') WHERE id = pg_temp.id('case2');
SELECT 'OBSERVED case2' AS what, c.status, c.discovering_test_id = pg_temp.id('t2') AS case_rests_on_fast_test, c.direction AS case_direction, v.direction AS eval_direction
  FROM public.meter_correction_cases c JOIN public.meter_correction_evaluations v ON v.id = c.frozen_evaluation_id WHERE c.id = pg_temp.id('case2');
ROLLBACK;
