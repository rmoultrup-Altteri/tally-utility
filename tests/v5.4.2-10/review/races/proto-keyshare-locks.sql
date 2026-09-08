-- (prototype only — the frozen patch is untouched; this rewrites the two lock sites on s10d)
CREATE OR REPLACE FUNCTION public.__proto_keyshare_validator() RETURNS void LANGUAGE sql AS $$ SELECT 1 $$;
DO $$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef('public.validate_calculation_snapshot()'::regprocedure) INTO src;
  src := replace(src, 'WHERE b.id = v_inv.billing_run_id FOR SHARE', 'WHERE b.id = v_inv.billing_run_id FOR KEY SHARE');
  src := replace(src, 't.voided_invoice_id = v_inv.replaces_invoice_id FOR SHARE', 't.voided_invoice_id = v_inv.replaces_invoice_id FOR KEY SHARE');
  EXECUTE src;
  SELECT pg_get_functiondef('public.enforce_billing_run_clock_and_election()'::regprocedure) INTO src;
  src := replace(src, 'IF EXISTS (SELECT 1 FROM public.invoice_calculation_snapshots s WHERE s.billing_run_id = OLD.id) THEN',
                      'PERFORM 1 FROM public.billing_runs b WHERE b.id = OLD.id FOR UPDATE;' || E'\n' ||
                      '        IF EXISTS (SELECT 1 FROM public.invoice_calculation_snapshots s WHERE s.billing_run_id = OLD.id) THEN');
  EXECUTE src;
  SELECT pg_get_functiondef('public.enforce_correction_target_frozen_under_snapshot()'::regprocedure) INTO src;
  src := replace(src, '    IF EXISTS (' || E'\n' || '        SELECT 1' || E'\n' || '          FROM public.invoice_calculation_snapshots s',
                      '    PERFORM 1 FROM public.correction_run_targets t WHERE t.id = OLD.id FOR UPDATE;' || E'\n' ||
                      '    IF EXISTS (' || E'\n' || '        SELECT 1' || E'\n' || '          FROM public.invoice_calculation_snapshots s');
  EXECUTE src;
END $$;
SELECT count(*) FROM pg_proc WHERE prosrc LIKE '%FOR KEY SHARE%' AND proname='validate_calculation_snapshot';
SELECT count(*) FROM pg_proc WHERE prosrc LIKE '%FOR UPDATE;%' AND proname IN ('enforce_billing_run_clock_and_election','enforce_correction_target_frozen_under_snapshot');
