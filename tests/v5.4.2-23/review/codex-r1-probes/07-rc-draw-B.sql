-- PREDICTED; owner sessions on a fresh clone with frozen r1 applied.
-- First run 05-race-fixtures.sql as owner, once on this fresh clone.
\set ON_ERROR_STOP on
-- Start while 06 is paused. This should wait, then REFUSE when A commits nsf.
SET application_name='codex_r1_draw_B';
BEGIN;
DO $$ BEGIN
INSERT INTO public.invoice_applications (tenant_id,customer_id,invoice_id,invoice_line_item_id,payment_id,amount,applied_on,basis,applied_by,reason)
VALUES ('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','00000000-0000-4000-8000-00000000cd11','00000000-0000-4000-8000-00000000cd12','00000000-0000-4000-8000-00000000cd01',10,DATE '2026-03-07','operator_override','00000000-0000-4000-8000-0000000023b1','Codex race');
RAISE NOTICE 'B2 draw after source ends: SQLSTATE=00000 accepted';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B2 draw after source ends: SQLSTATE=% message=%',SQLSTATE,SQLERRM; END $$;
SELECT p.status,(SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.payment_id=p.id) AS applied
FROM public.payments p WHERE p.id='00000000-0000-4000-8000-00000000cd01';
ROLLBACK;
