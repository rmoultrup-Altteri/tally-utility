BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
-- A issued -> void
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fd001', 'R4-A', NULL, 'regular', NULL, '2026-01-01', '2026-01-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd001', '2026-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fd001';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fd001', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL AS a_void;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000fd901', '00000000-0000-4000-8000-0000000fa001', 'R4-CR1', '2026-01', '2026-01-01', '2026-01-31', 'correction', 'in_progress', now()),
  ('00000000-0000-4000-8000-0000000fd902', '00000000-0000-4000-8000-0000000fa001', 'R4-CR2', '2026-01', '2026-01-01', '2026-01-31', 'correction', 'in_progress', now()),
  ('00000000-0000-4000-8000-0000000fd903', '00000000-0000-4000-8000-0000000fa001', 'R4-CR3', '2026-01', '2026-01-01', '2026-01-31', 'correction', 'in_progress', now());
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fdb01', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fd901', '00000000-0000-4000-8000-0000000fd001', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201'),
  ('00000000-0000-4000-8000-0000000fdb02', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fd902', '00000000-0000-4000-8000-0000000fd001', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
-- MIXED: a regular-typed rebill R replaces A (ordinary shape), issued and live
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fd002', 'R4-REGULAR-REBILL', NULL, 'regular', '00000000-0000-4000-8000-0000000fd001', '2026-01-01', '2026-01-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd002', '2026-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fd002';
-- correction B of A: lands beside the live regular rebill?
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fd003', 'R4-B', '00000000-0000-4000-8000-0000000fd901', 'correction', '00000000-0000-4000-8000-0000000fd001', '2026-01-01', '2026-01-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd003', '2026-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fd003';
SELECT count(*) AS live_bills_replacing_A FROM public.invoices WHERE replaces_invoice_id='00000000-0000-4000-8000-0000000fd001' AND status='pending';
-- SIDEWAYS: B2 also corrects A while B live -> refused
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fd004', 'R4-B2', '00000000-0000-4000-8000-0000000fd902', 'correction', '00000000-0000-4000-8000-0000000fd001', '2026-01-01', '2026-01-31');
SAVEPOINT s1; SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd004', '2026-01-31', now()); ROLLBACK TO s1;
-- void B; B2 lands; then C corrects B (void) while B2 live -> refused (sideways at different depth)
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fd003', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL AS b_void;
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd004', '2026-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fd004';
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fdb03', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fd903', '00000000-0000-4000-8000-0000000fd003', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fd005', 'R4-C', '00000000-0000-4000-8000-0000000fd903', 'correction', '00000000-0000-4000-8000-0000000fd003', '2026-01-01', '2026-01-31');
SAVEPOINT s2; SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd005', '2026-01-31', now()); ROLLBACK TO s2;
-- void B2 -> C lands (D of the brief)
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fd004', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL AS b2_void;
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd005', '2026-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fd005';
SELECT status AS c_status FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fd005';
-- CYCLE: a draft whose replaces chain loops via a void regular bill. D draft; V regular replaces D, issued, voided; D.replaces := V. Then correct V.
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fd011', 'R4-D', NULL, 'regular', NULL, '2026-02-01', '2026-02-28');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fd012', 'R4-V', NULL, 'regular', '00000000-0000-4000-8000-0000000fd011', '2026-02-01', '2026-02-28');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd012', '2026-02-28', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fd012';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fd012', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL AS v_void;
SAVEPOINT s3; UPDATE public.invoices SET replaces_invoice_id='00000000-0000-4000-8000-0000000fd012' WHERE id='00000000-0000-4000-8000-0000000fd011'; ROLLBACK TO s3;
SELECT replaces_invoice_id IS NOT NULL AS d_points_at_v FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fd011';
ROLLBACK;
