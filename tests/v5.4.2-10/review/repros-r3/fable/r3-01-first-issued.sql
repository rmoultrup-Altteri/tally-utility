BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
-- (a) INSERT with a caller value -> NULL
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, first_issued_at)
VALUES ('00000000-0000-4000-8000-0000000fc001', '00000000-0000-4000-8000-0000000fa001', 'FA-R3-A', '00000000-0000-4000-8000-0000000fa201', '00000000-0000-4000-8000-0000000fa301', '2026-04-01', '2026-03', '2026-03-01', '2026-03-31', '2026-04-22', '2020-01-01');
SELECT first_issued_at AS after_insert FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fc001';
-- (b) direct UPDATE -> refused
SAVEPOINT b; UPDATE public.invoices SET first_issued_at = now() WHERE id='00000000-0000-4000-8000-0000000fc001'; ROLLBACK TO b;
-- (c) INSERT directly in an issued status -> refused?
SAVEPOINT c;
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('00000000-0000-4000-8000-0000000fc002', '00000000-0000-4000-8000-0000000fa001', 'FA-R3-B', '00000000-0000-4000-8000-0000000fa201', '00000000-0000-4000-8000-0000000fa301', '2026-04-01', '2026-03', '2026-03-01', '2026-03-31', '2026-04-22', 'pending');
ROLLBACK TO c;
-- (d) held -> pending stamps; snapshot of a HELD invoice (mutex UPDATE fires hold-metadata/predelivery/deferred gates)
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount) VALUES ('00000000-0000-4000-8000-0000000fa001','00000000-0000-4000-8000-0000000fc001','gas','base_charge','x',1);
UPDATE public.invoices SET status='held', held_at=now(), held_by='00000000-0000-4000-8000-0000000fa101', hold_reason='r' WHERE id='00000000-0000-4000-8000-0000000fc001';
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fc001', '2026-03-31', now());
SELECT status, first_issued_at AS held_snapshotted FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fc001';
UPDATE public.invoices SET status='pending', held_at=NULL, held_by=NULL, hold_reason=NULL WHERE id='00000000-0000-4000-8000-0000000fc001';
SELECT first_issued_at = now() AS stamped_on_issue FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fc001';
-- (e) void keeps it; a correction snapshot's mutex on the void bill changes only updated_at
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fc001', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL AS voided;
SELECT to_jsonb(i) - 'updated_at' AS before_row FROM public.invoices i WHERE id='00000000-0000-4000-8000-0000000fc001' \gset
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000fc901', '00000000-0000-4000-8000-0000000fa001', 'FA-R3-CR1', '2026-03', '2026-03-01', '2026-03-31', 'correction', 'in_progress', now());
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fcb01', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fc901', '00000000-0000-4000-8000-0000000fc001', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fc003', 'FA-R3-C', '00000000-0000-4000-8000-0000000fc901', 'correction', '00000000-0000-4000-8000-0000000fc001', '2026-03-01', '2026-03-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fc003', '2026-03-31', now());
SELECT (to_jsonb(i) - 'updated_at') = :'before_row'::jsonb AS void_row_unchanged_except_updated_at FROM public.invoices i WHERE id='00000000-0000-4000-8000-0000000fc001';
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fc003';
SELECT status AS correction_status FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fc003';
ROLLBACK;
