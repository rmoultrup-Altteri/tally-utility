-- Source-review probe 03; run as clone owner (fixture setup), then tally_app.
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
INSERT INTO public.deposit_customer_classes (state_code,service_type,class_code,description,source_note)
 VALUES ('TX','gas','codex_count','Count comparison fixture','review fixture');
INSERT INTO public.deposit_rules (state_code,service_type,customer_class,basis,owner_types,system_kinds,effective_from,source_note,terms_kind,terms_version,terms_source) VALUES ('TX','gas','codex_count','additional_trigger',ARRAY['investor_owned'],ARRAY['distribution'],DATE '2000-01-01','review fixture','deposit',1,$doc${"governs":"law","citation":"Synthetic review law","cap":{"strategy":"none","version":1},"triggers":[{"id":"t1","trigger_code":"nsf","guards":[],"condition":{"kind":"count","event":"nsf","at_least":2,"window":{"unit":"months","size":12},"consecutive":true,"exclude_disputed":true}}],"waivers":[],"interest":{"strategy":"none","version":1},"return":[],"instalments":[]}$doc$);
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = 'c0de0000-0000-4000-8000-000000000002';
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','equal','codex_count','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 03: equal; expected frozen result: ACCEPTED (control)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','equal',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[{"id":"t1","trigger_code":"nsf","guards":[],"condition":{"kind":"count","event":"nsf","at_least":2,"window":{"unit":"months","size":12},"consecutive":true,"exclude_disputed":true}}],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: equal: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: equal: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','nonconsecutive','codex_count','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 03: nonconsecutive; expected frozen result: ACCEPTED (bug); desired REFUSED';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','nonconsecutive',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[{"id":"t1","trigger_code":"nsf","guards":[],"condition":{"kind":"count","event":"nsf","at_least":2,"window":{"unit":"months","size":12},"consecutive":false,"exclude_disputed":true}}],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: nonconsecutive: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: nonconsecutive: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','disputed','codex_count','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 03: disputed; expected frozen result: ACCEPTED (bug); desired REFUSED';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','disputed',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[{"id":"t1","trigger_code":"nsf","guards":[],"condition":{"kind":"count","event":"nsf","at_least":2,"window":{"unit":"months","size":12},"consecutive":true,"exclude_disputed":false}}],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: disputed: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: disputed: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','fewer','codex_count','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 03: fewer; expected frozen result: REFUSED, looser than the law (control)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','fewer',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[{"id":"t1","trigger_code":"nsf","guards":[],"condition":{"kind":"count","event":"nsf","at_least":1,"window":{"unit":"months","size":12},"consecutive":true,"exclude_disputed":true}}],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: fewer: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: fewer: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
ROLLBACK;
