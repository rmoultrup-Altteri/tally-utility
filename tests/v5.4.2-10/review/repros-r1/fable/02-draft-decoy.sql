-- ATTACK 2: a correction that "replaces" a live DRAFT. Nothing requires the replaced
-- invoice to be void. Historical election reads the decoy's period_end, which is free
-- to move while the decoy has no snapshot. valid_at is not re-derived at issuance.
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
-- decoy draft: period_end chosen to be the valid_at the attacker wants (2024-01-31)
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa511', 'FA-DECOY', NULL, 'regular', NULL, '2024-01-01', '2024-01-31');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa611', '00000000-0000-4000-8000-0000000fa001', 'FA-CRUN-1', '2026-08', '2026-08-01', '2026-08-31', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fa711', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa611', '00000000-0000-4000-8000-0000000fa511',
   '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
-- the "correction": an Aug-2026 bill priced at a Jan-2024 valid_at
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa512', 'FA-CORR-DECOY', '00000000-0000-4000-8000-0000000fa611', 'correction', '00000000-0000-4000-8000-0000000fa511', '2026-08-01', '2026-08-31');
SELECT status AS decoy_status FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000fa511';
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa512', '2024-01-31', now());
-- now move the decoy's period so the election would resolve differently; issuance does not re-derive
UPDATE public.invoices SET period_start = '2026-08-01', period_end = '2026-08-31', due_date = '2026-09-21' WHERE id = '00000000-0000-4000-8000-0000000fa511';
SELECT public.get_correction_rate_date('00000000-0000-4000-8000-0000000fa611', '00000000-0000-4000-8000-0000000fa511') AS election_now;
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa512';
SELECT i.invoice_number, i.status, i.period_end, s.valid_at, s.recorded_at FROM public.invoices i JOIN public.invoice_calculation_snapshots s ON s.invoice_id = i.id WHERE i.id = '00000000-0000-4000-8000-0000000fa512';
ROLLBACK;
