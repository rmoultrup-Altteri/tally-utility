BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fe001', 'R5-A', NULL, 'regular', NULL, '2026-01-01', '2026-01-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fe001', '2026-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fe001';
-- credit_memo referencing a live bill: ordinary shape, allowed
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fe002', 'R5-CM', NULL, 'credit_memo', '00000000-0000-4000-8000-0000000fe001', '2026-01-01', '2026-01-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fe002', '2026-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fe002';
SELECT status AS credit_memo_status FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fe002';
-- final / consolidated carrying replaces_invoice_id: refused?
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fe003', 'R5-FINAL', NULL, 'final', '00000000-0000-4000-8000-0000000fe001', '2026-02-01', '2026-02-10');
SAVEPOINT a; SELECT public.fa_snap('00000000-0000-4000-8000-0000000fe003', '2026-02-10', now()); ROLLBACK TO a;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fe004', 'R5-CONS', NULL, 'consolidated', '00000000-0000-4000-8000-0000000fe001', '2026-01-01', '2026-01-31');
SAVEPOINT b; SELECT public.fa_snap('00000000-0000-4000-8000-0000000fe004', '2026-01-31', now()); ROLLBACK TO b;
-- cross-tenant replaces_invoice_id at INSERT (composite FK)
SAVEPOINT c;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fe005', 'R5-XT', NULL, 'credit_memo', '00000000-0000-4000-8000-0000000fa562', '2026-01-01', '2026-01-31');
ROLLBACK TO c;
ROLLBACK;
