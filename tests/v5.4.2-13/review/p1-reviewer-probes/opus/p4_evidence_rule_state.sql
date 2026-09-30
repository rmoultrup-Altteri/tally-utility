-- Owner seeds a second state that also uses the class code 'protected', and an electric TX rule.
INSERT INTO public.backbilling_customer_classes VALUES ('ZZ','gas','protected','ZZ protected','ZZ code (fictional)', now()),
                                                       ('TX','electric','protected','TX electric protected','PUCT (fictional for probe)', now());
INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
   adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, source_note)
VALUES ('ZZ','gas','protected','meter_error','test_date',ARRAY['fast','slow'],'permitted','include_whole','include_whole','adjustment',false,false,'uncapped',DATE '2000-01-01','ZZ (fictional)'),
       ('TX','electric','protected','meter_error','test_date',ARRAY['fast','slow'],'permitted','include_whole','include_whole','adjustment',false,false,'uncapped',DATE '2000-01-01','probe');
INSERT INTO b13 VALUES ('t1', pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-05-15', 104));
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
WITH x AS (INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction, updated_at)
  VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013e1','meter_error', pg_temp.id('t1'),
          DATE '2026-05-15','test_date','customer_owed', TIMESTAMPTZ '1999-01-01') RETURNING id, updated_at)
INSERT INTO b13 SELECT 'case', id FROM x;
SELECT 'OBSERVED caller updated_at' AS what, updated_at FROM public.meter_correction_cases WHERE id = pg_temp.id('case');
WITH x AS (INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case'), 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owed', pg_temp.r('protected','meter_error'), false, '{}', 'fp', 'core-0.0.0') RETURNING id)
INSERT INTO b13 SELECT 'ev', id FROM x;
-- TX gas premise, TX gas evaluation; period rows cite a ZZ rule and a TX *electric* rule.
INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id, location_id,
       period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, days_in_window)
VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('ev'), pg_temp.id('inv_f1'), '00000000-0000-4000-8000-0000000013c1',
        '00000000-0000-4000-8000-0000000013d1', DATE '2026-03-01', DATE '2026-03-31', 'protected',
        (SELECT id FROM public.backbilling_rules WHERE state_code='ZZ' AND customer_class='protected'), 'customer_owed', -2.00, 'included', 31),
       ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('ev'), pg_temp.id('inv_f2'), '00000000-0000-4000-8000-0000000013c1',
        '00000000-0000-4000-8000-0000000013d1', DATE '2026-04-01', DATE '2026-04-30', 'protected',
        (SELECT id FROM public.backbilling_rules WHERE service_type='electric'), 'customer_owed', -2.00, 'included', 30);
SELECT 'OBSERVED evidence' AS what, b.state_code, b.service_type, b.customer_class FROM public.meter_correction_period_evidence p
  JOIN public.backbilling_rules b ON b.id = p.rule_id WHERE p.evaluation_id = pg_temp.id('ev');
ROLLBACK;
