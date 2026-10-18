-- PREDICTED; owner sessions on a fresh clone with frozen r1 applied.
-- First run 05-race-fixtures.sql as owner, once on this fresh clone.
\set ON_ERROR_STOP on
-- Run while 08 is paused after taking its snapshot.
SET application_name='codex_r1_rr_draw_B';
BEGIN;
DO $$ BEGIN
INSERT INTO public.invoice_applications (tenant_id,customer_id,invoice_id,invoice_line_item_id,payment_id,amount,applied_on,basis,applied_by,reason)
VALUES ('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','00000000-0000-4000-8000-00000000cd11','00000000-0000-4000-8000-00000000cd12','00000000-0000-4000-8000-00000000cd01',10,DATE '2026-03-07','operator_override','00000000-0000-4000-8000-0000000023b1','Codex race');
RAISE NOTICE 'B2 concurrent draw: SQLSTATE=00000 accepted';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B2 concurrent draw: SQLSTATE=% message=%',SQLSTATE,SQLERRM; END $$;
COMMIT;
BEGIN;
ROLLBACK;
