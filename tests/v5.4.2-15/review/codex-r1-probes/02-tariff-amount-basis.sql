-- Source-review probe 02; run as clone owner (fixture setup), then tally_app.
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
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','average','residential','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 02: average; expected frozen result: ACCEPTED (control)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','average',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"months_of_billing","version":1,"months":2,"of":"average","minimum_amount":{"kind":"none"}},"triggers":[],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02: average: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02: average: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','highest','residential','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 02: highest; expected frozen result: ACCEPTED (bug); highest bill is not average billing';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','highest',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"months_of_billing","version":1,"months":2,"of":"highest","minimum_amount":{"kind":"none"}},"triggers":[],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02: highest: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02: highest: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','minimum','residential','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 02: minimum; expected frozen result: ACCEPTED (bug); minimum may exceed the statutory cap';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','minimum',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"months_of_billing","version":1,"months":2,"of":"average","minimum_amount":{"kind":"amount","amount":5000}},"triggers":[],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02: minimum: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02: minimum: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','too_many','residential','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 02: too_many; expected frozen result: REFUSED, looser than the law (control)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','too_many',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"months_of_billing","version":1,"months":3,"of":"average","minimum_amount":{"kind":"none"}},"triggers":[],"waivers":[],"instalments":[]}$doc$);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02: too_many: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02: too_many: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
ROLLBACK;
