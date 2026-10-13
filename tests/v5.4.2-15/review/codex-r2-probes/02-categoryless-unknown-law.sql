-- Source-review probe 02; run as clone owner (fixture setup), then tally_app.
-- Self-contained; no battery helpers, extensions, or committed changes.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL client_min_messages = notice;
SET LOCAL statement_timeout = '30s';
INSERT INTO public.tenants (id,name,slug) VALUES ('c0de0000-0000-4000-8000-000000000001','Codex review probe','codex-r2-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role)
 VALUES ('c0de0000-0000-4000-8000-000000000002','c0de0000-0000-4000-8000-000000000001','Codex operator','codex-r2-probe@example.test','operator');
INSERT INTO public.customers (id,tenant_id,customer_number,customer_type)
 VALUES ('c0de0000-0000-4000-8000-000000000003','c0de0000-0000-4000-8000-000000000001','CODEX-R2','residential');
INSERT INTO public.places (kind_code,state_code,place_code,name,effective_from,source_note)
 VALUES ('state','ZY','ZY','Codex synthetic state',DATE '1900-01-01','review fixture');
INSERT INTO public.utility_service_profiles
 (tenant_id,service_type,system_kind,state_code,owner_type,commission_jurisdiction,effective_from,evidence_reference,evidence_date)
 VALUES ('c0de0000-0000-4000-8000-000000000001','gas','distribution','ZY','investor_owned',true,
 
 DATE '2000-01-01','review fixture',DATE '2000-01-01');
INSERT INTO public.deposit_customer_classes (state_code,service_type,class_code,description,source_note)
 VALUES ('ZY','gas','codex_unknown','Class without law','review fixture');
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = 'c0de0000-0000-4000-8000-000000000002';
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','ZY','gas','unknown','codex_unknown','review fixture');
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 02: named category; expected frozen: REFUSED for missing law (control)';
 BEGIN
  INSERT INTO public.deposit_interest_rates (tenant_id,state_code,service_type,tariff_category,effective_date,annual_rate,source_reference)
  VALUES ('c0de0000-0000-4000-8000-000000000001','ZY','gas','unknown',DATE '2020-01-01',0,'review fixture');
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02: named category: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02: named category: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 02: every category; expected frozen: ACCEPTED (bug); desired REFUSED for missing law';
 BEGIN
  INSERT INTO public.deposit_interest_rates (tenant_id,state_code,service_type,tariff_category,effective_date,annual_rate,source_reference)
  VALUES ('c0de0000-0000-4000-8000-000000000001','ZY','gas',NULL,DATE '2020-01-01',0,'review fixture');
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02: every category: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02: every category: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
ROLLBACK;
