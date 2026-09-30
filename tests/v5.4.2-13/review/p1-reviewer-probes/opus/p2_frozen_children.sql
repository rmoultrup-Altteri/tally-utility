SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
RESET ROLE;
INSERT INTO b13 VALUES ('t1', pg_temp.rec('00000000-0000-4000-8000-0000000013e2', DATE '2026-05-15', 96));
SET ROLE tally_app;
WITH x AS (INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013e2','meter_error', pg_temp.id('t1'),
          DATE '2026-05-15','test_date','customer_owes') RETURNING id)
INSERT INTO b13 SELECT 'case', id FROM x;
-- The core says a supervisor must approve (approval_required = true) ...
WITH x AS (INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case'), 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owes', pg_temp.r('protected','meter_error'), true, '{}', 'fp', 'core-0.0.0') RETURNING id)
INSERT INTO b13 SELECT 'ev', id FROM x;
-- ... the app freezes without it (a core/app bug, which the record is meant to show) ...
UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev') WHERE id = pg_temp.id('case');
SELECT 'before' AS t, approval_pending, open_holds FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('case');
-- ... then a supervisor approves the frozen evaluation afterwards, and a hold is opened on the frozen case.
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b3';
INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case'), pg_temp.id('ev'), 'approved after the fact');
INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case'), DATE '2025-12-01', DATE '2025-12-31', 'legacy_records_not_loaded');
SELECT 'after' AS t, status, approval_pending, open_holds FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('case');
-- A withdrawn case also takes new holds, evaluations and approvals.
WITH x AS (INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from)
  VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013e8','crossed_meters',
          DATE '2026-05-01','discovery_date', DATE '2026-01-01') RETURNING id)
INSERT INTO b13 SELECT 'wcase', id FROM x;
UPDATE public.meter_correction_cases SET status='withdrawn', withdrawn_reason='not a real finding' WHERE id = pg_temp.id('wcase');
INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('wcase'), DATE '2025-12-01', DATE '2025-12-31', 'legacy_records_not_loaded');
SELECT 'withdrawn' AS t, status, open_holds FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('wcase');
ROLLBACK;
