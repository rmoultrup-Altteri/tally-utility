SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ DECLARE c uuid; e uuid; BEGIN
  INSERT INTO b13 VALUES ('t_fast', pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-05-15', 104));
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e1', 'meter_error', pg_temp.id('t_fast'),
          DATE '2026-05-15', 'test_date', 'customer_owed') RETURNING id INTO c;
  INSERT INTO b13 VALUES ('case_fast', c);
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', c, 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owed', pg_temp.r('protected', 'meter_error'), true, '{}', 'fp-1', 'core-0.0.0') RETURNING id INTO e;
  INSERT INTO b13 VALUES ('ev1', e);
END $$;
RESET ROLE;
-- P7 redo: no app.user_id at all (RESET), as the platform admin path or a
-- service session might run. First as owner (no RLS), then as tally_app.
RESET app.user_id;
DO $$ DECLARE a public.meter_correction_approvals%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), pg_temp.id('ev1'), 'nobody here')
  RETURNING * INTO a;
  RAISE NOTICE 'P7 (owner, no app.user_id) OBSERVED: approval accepted with approved_by = %', coalesce(a.approved_by::text, 'NULL');
  DELETE FROM public.meter_correction_approvals WHERE id = a.id;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P7 (owner) OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
SET ROLE tally_app;
DO $$ DECLARE a public.meter_correction_approvals%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), pg_temp.id('ev1'), 'nobody here')
  RETURNING * INTO a;
  RAISE NOTICE 'P7 (tally_app, no app.user_id) OBSERVED: approval accepted with approved_by = %', coalesce(a.approved_by::text, 'NULL');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P7 (tally_app, no app.user_id) OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
RESET ROLE;
-- P22 redo: months = 0 on a real TX rule; and a "days" term.
DO $$ BEGIN
  INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
  VALUES (pg_temp.r('protected', 'crossed_meters'), 'adverse', 'months_before_anchor', 0);
  RAISE NOTICE 'P22 OBSERVED: months=0 accepted';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P22 OBSERVED: months=0 refused % (%)', SQLSTATE, SQLERRM;
END $$;
DO $$ BEGIN
  RAISE NOTICE 'P22b OBSERVED: window_terms columns = %', (SELECT string_agg(column_name, ', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_name = 'backbilling_rule_window_terms');
END $$;
