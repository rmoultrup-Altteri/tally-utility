-- Source-review probe 05; run as clone owner (fixture setup), then tally_app.
-- Self-contained; no battery helpers, extensions, or committed changes.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL client_min_messages = notice;
SET LOCAL statement_timeout = '30s';
INSERT INTO public.tenants (id,name,slug) VALUES ('c0de0000-0000-4000-8000-000000000001','Codex review probe','codex-r1-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role)
 VALUES ('c0de0000-0000-4000-8000-000000000002','c0de0000-0000-4000-8000-000000000001','Codex operator','codex-r1-probe@example.test','operator');
INSERT INTO public.customers (id,tenant_id,customer_number,customer_type)
 VALUES ('c0de0000-0000-4000-8000-000000000003','c0de0000-0000-4000-8000-000000000001','CODEX-R1','residential');
INSERT INTO public.utility_service_profiles
 (tenant_id,service_type,system_kind,state_code,owner_type,commission_jurisdiction,effective_from,evidence_reference,evidence_date)
 VALUES ('c0de0000-0000-4000-8000-000000000001','gas','distribution','TX','investor_owned',true,
 
 DATE '2000-01-01','review fixture',DATE '2000-01-01');
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = 'c0de0000-0000-4000-8000-000000000002';
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','normal','residential','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 05: normal; expected frozen result: ACCEPTED (control)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','normal',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[{"id":"t1","trigger_code":"usage_doubled","guards":[{"kind":"payment_due_days","days":2}],"condition":{"kind":"ratio","measure":"usage_to_estimate","op":"at_least","value":2}}],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 05: normal: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 05: normal: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','duplicate','residential','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 05: duplicate; expected frozen result: ACCEPTED (bug); desired REFUSED for duplicate guard kind';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','duplicate',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[{"id":"t1","trigger_code":"usage_doubled","guards":[{"kind":"payment_due_days","days":2},{"kind":"payment_due_days","days":1}],"condition":{"kind":"ratio","measure":"usage_to_estimate","op":"at_least","value":2}}],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 05: duplicate: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 05: duplicate: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','reversed','residential','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 05: reversed; expected frozen result: REFUSED, fewer days (shows first guard wins)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','reversed',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[{"id":"t1","trigger_code":"usage_doubled","guards":[{"kind":"payment_due_days","days":1},{"kind":"payment_due_days","days":2}],"condition":{"kind":"ratio","measure":"usage_to_estimate","op":"at_least","value":2}}],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 05: reversed: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 05: reversed: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
ROLLBACK;
