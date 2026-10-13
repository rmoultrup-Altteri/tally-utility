-- Source-review probe 01; run as clone owner (fixture setup), then tally_app.
-- Self-contained; no battery helpers, extensions, or committed changes.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL client_min_messages = notice;
SET LOCAL statement_timeout = '30s';
INSERT INTO public.tenants (id,name,slug) VALUES ('c0de0000-0000-4000-8000-000000000001','Codex review probe','codex-r3-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role)
 VALUES ('c0de0000-0000-4000-8000-000000000002','c0de0000-0000-4000-8000-000000000001','Codex operator','codex-r3-probe@example.test','operator');
INSERT INTO public.customers (id,tenant_id,customer_number,customer_type)
 VALUES ('c0de0000-0000-4000-8000-000000000003','c0de0000-0000-4000-8000-000000000001','CODEX-R3','residential');
INSERT INTO public.utility_service_profiles
 (tenant_id,service_type,system_kind,state_code,owner_type,commission_jurisdiction,effective_from,effective_to,evidence_reference,evidence_date)
 VALUES ('c0de0000-0000-4000-8000-000000000001','gas','distribution','TX','investor_owned',true,DATE '2020-01-01',DATE '2021-01-01','review fixture',DATE '2000-01-01'),
 ('c0de0000-0000-4000-8000-000000000001','gas','distribution','TX','cooperative',true,DATE '2021-01-01',DATE '2022-01-01','review fixture',DATE '2000-01-01');
INSERT INTO public.deposit_customer_classes (state_code,service_type,class_code,description,source_note)
 VALUES ('TX','gas','codex_profile_gap','Only investor-owned law exists','review fixture');
INSERT INTO public.deposit_rules
 (state_code,service_type,customer_class,basis,owner_types,system_kinds,effective_from,effective_to,source_note,terms_kind,terms_version,terms_source)
 VALUES ('TX','gas','codex_profile_gap','credit_evaluation',ARRAY['investor_owned'],ARRAY['distribution'],DATE '2020-01-01',DATE '2022-01-01','review fixture','deposit',1,'{"governs": "law", "citation": "Synthetic review law", "cap": {"strategy": "none", "version": 1}, "triggers": [], "waivers": [], "interest": {"strategy": "none", "version": 1}, "return": [], "instalments": []}');
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = 'c0de0000-0000-4000-8000-000000000002';
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','before','codex_profile_gap','review fixture');
DO $probe$
DECLARE n bigint;
BEGIN
 RAISE NOTICE 'PROBE 01: before; expected frozen: ACCEPTED (control)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,effective_to,tariff_reference,terms_kind,terms_version,terms_source)
 VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','before',DATE '2020-01-01',DATE '2021-01-01','review fixture','deposit_tariff',1,'{"citation": "Review tariff", "amount": {"strategy": "fixed", "version": 1, "amount": 100}, "triggers": [], "waivers": [], "instalments": []}');
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture selected % rows, expected exactly one', n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 01: before: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 01: before: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','after','codex_profile_gap','review fixture');
DO $probe$
DECLARE n bigint;
BEGIN
 RAISE NOTICE 'PROBE 01: after; expected frozen: REFUSED for missing class law (control)';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,effective_to,tariff_reference,terms_kind,terms_version,terms_source)
 VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','after',DATE '2021-01-01',DATE '2022-01-01','review fixture','deposit_tariff',1,'{"citation": "Review tariff", "amount": {"strategy": "fixed", "version": 1, "amount": 100}, "triggers": [], "waivers": [], "instalments": []}');
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture selected % rows, expected exactly one', n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 01: after: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 01: after: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','spanning','codex_profile_gap','review fixture');
DO $probe$
DECLARE n bigint;
BEGIN
 RAISE NOTICE 'PROBE 01: spanning; expected frozen: ACCEPTED (bug); desired REFUSED for missing class law in cooperative profile';
 BEGIN
  INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,effective_to,tariff_reference,terms_kind,terms_version,terms_source)
 VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','spanning',DATE '2020-01-01',DATE '2022-01-01','review fixture','deposit_tariff',1,'{"citation": "Review tariff", "amount": {"strategy": "fixed", "version": 1, "amount": 100}, "triggers": [], "waivers": [], "instalments": []}');
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture selected % rows, expected exactly one', n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 01: spanning: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 01: spanning: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
ROLLBACK;
