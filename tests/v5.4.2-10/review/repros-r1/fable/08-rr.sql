BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa571', 'FA-RR', NULL, 'regular', NULL, '2026-05-01', '2026-05-31');
SELECT count(*) AS snapshots_on_draft FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-0000000fa571';
UPDATE public.invoices SET period_end = '2026-06-02', due_date = '2026-06-23' WHERE id = '00000000-0000-4000-8000-0000000fa571';
ROLLBACK;
-- report block cannot raise: run it against s10c's current rows
DO $$
DECLARE v_bad bigint; v_runs bigint;
BEGIN
  SELECT count(*) INTO v_bad FROM public.invoice_calculation_snapshots s JOIN public.invoices i ON i.id = s.invoice_id
   WHERE public.calculation_snapshot_coordinate_violation(i, s.valid_at, s.recorded_at, true) IS NOT NULL;
  SELECT count(DISTINCT s.billing_run_id) INTO v_runs FROM public.invoice_calculation_snapshots s JOIN public.billing_runs b ON b.id = s.billing_run_id WHERE b.started_at IS NULL;
  RAISE NOTICE 'report: bad=% runs=%', v_bad, v_runs;
END $$;
