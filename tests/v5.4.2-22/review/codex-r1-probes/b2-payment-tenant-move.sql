-- Codex r1 source-review probe. NOT EXECUTED by reviewer.
-- Run with psql -U tally -d <fresh-clone-with-frozen-patch> -f this-file.sql
-- Requires the clone owner/superuser; no role DDL, no commits; all changes roll back.
-- OBSERVED notices report behavior, not a pre-declared pass. Unexpected setup errors stop psql.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = public, pg_temp;
SET LOCAL client_min_messages = notice;
DO $$
DECLARE t uuid := gen_random_uuid(); t2 uuid := gen_random_uuid();
        c uuid := gen_random_uuid(); c2 uuid := gen_random_uuid();
        u uuid := gen_random_uuid(); pa uuid := gen_random_uuid(); p uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('codex.t', t::text, true); PERFORM set_config('codex.t2', t2::text, true);
  PERFORM set_config('codex.c', c::text, true); PERFORM set_config('codex.c2', c2::text, true);
  PERFORM set_config('codex.u', u::text, true); PERFORM set_config('codex.pa', pa::text, true);
  PERFORM set_config('codex.p', p::text, true);
  INSERT INTO public.tenants(id,name,slug) VALUES(t,'Codex probe','cx-'||t),(t2,'Codex other','cx-'||t2);
  INSERT INTO public.users(id,tenant_id,display_name,email,role,is_active)
  VALUES(u,t,'Supervisor',u||'@codex.test','tenant_admin',true),
        (pa,t,'Platform admin',pa||'@codex.test','platform_admin',true);
  INSERT INTO public.customers(id,tenant_id,customer_number,customer_type)
  VALUES(c,t,'CX-1','residential'),(c2,t2,'CX-2','residential');
  INSERT INTO public.accounting_periods(id,tenant_id,period_start,period_end)
  VALUES(p,t,DATE '2020-01-01',DATE '2020-01-31');
  PERFORM set_config('app.user_id',u::text,true);
END $$;
-- Expected defect: platform-admin application moves a pending payment OUT OF a frozen tenant.
DO $$
DECLARE pay uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('codex.pay',pay::text,true);
  INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,status)
  VALUES(pay,current_setting('codex.t')::uuid,current_setting('codex.c')::uuid,'CX-P',DATE '2020-01-15',10,'check','pending');
END $$;
SET LOCAL ROLE tally_app;
DO $$ BEGIN PERFORM public.close_accounting_period(current_setting('codex.p')::uuid); END $$;
SELECT set_config('app.user_id',current_setting('codex.pa'),true);
DO $$
BEGIN
  BEGIN
    UPDATE public.payments SET tenant_id=current_setting('codex.t2')::uuid,
      customer_id=current_setting('codex.c2')::uuid,payment_date=DATE '2020-02-01'
    WHERE id=current_setting('codex.pay')::uuid;
    RAISE NOTICE 'OBSERVED B2 accepted move from closed-through % to open tenant; row=%',
      (SELECT closed_through FROM public.accounting_close_heads WHERE tenant_id=current_setting('codex.t')::uuid),
      (SELECT row_to_json(p) FROM public.payments p WHERE id=current_setting('codex.pay')::uuid);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'OBSERVED B2 refused: % %',SQLSTATE,SQLERRM;
  END;
END $$;

RESET ROLE;
ROLLBACK;
