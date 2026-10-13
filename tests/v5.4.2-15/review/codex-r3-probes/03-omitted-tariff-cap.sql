-- Source-review probe 03; run as clone owner (fixture setup), then tally_app.
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
INSERT INTO public.places (kind_code,state_code,place_code,name,parent_place_id,effective_from,source_note)
 SELECT 'municipality','TX','CODEXR3','Codex city',id,DATE '1950-01-01','review fixture'
 FROM public.places WHERE kind_code='state' AND place_code='TX';
INSERT INTO public.utility_service_profiles
 (tenant_id,service_type,system_kind,state_code,owner_type,commission_jurisdiction,owning_place_id,effective_from,evidence_reference,evidence_date)
 VALUES ('c0de0000-0000-4000-8000-000000000001','gas','distribution','TX','municipal',false,
 (SELECT id FROM public.places WHERE kind_code='municipality' AND place_code='CODEXR3'),
 DATE '2000-01-01','review fixture',DATE '2000-01-01');
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = 'c0de0000-0000-4000-8000-000000000002';
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','capcheck','residential','review fixture');
INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,effective_to,tariff_reference,terms_kind,terms_version,terms_source)
 VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','capcheck',DATE '2020-01-01',DATE '2030-01-01','review fixture','deposit_tariff',1,'{"citation": "Review tariff", "amount": {"strategy": "fixed", "version": 1, "amount": 100}, "triggers": [], "waivers": [], "instalments": []}');
DO $probe$
DECLARE n bigint;
BEGIN
 RAISE NOTICE 'PROBE 03: exact; expected frozen: ACCEPTED (control)';
 BEGIN
  INSERT INTO public.deposits (tenant_id,customer_id,basis,instrument,principal,posted_on,state_code,service_type,system_kind,customer_class,tariff_category,rule_id,tariff_id,decided_by,cap_amount,cap_source)
 SELECT 'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000003','credit_evaluation','cash',100,DATE '2026-01-01','TX','gas','distribution','residential','capcheck',r.id,tf.id,'core-review',100,'tariff'
 FROM public.deposit_rules r CROSS JOIN public.deposit_tariffs tf
 WHERE r.state_code='TX' AND r.service_type='gas' AND r.customer_class='residential' AND r.basis='credit_evaluation'
 AND r.owner_types @> ARRAY['municipal'] AND r.effective_to IS NULL AND tf.tenant_id='c0de0000-0000-4000-8000-000000000001' AND tf.tariff_category='capcheck';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture selected % rows, expected exactly one', n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: exact: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: exact: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
DO $probe$
DECLARE n bigint;
BEGIN
 RAISE NOTICE 'PROBE 03: explicit; expected frozen: REFUSED above tariff amount (control)';
 BEGIN
  INSERT INTO public.deposits (tenant_id,customer_id,basis,instrument,principal,posted_on,state_code,service_type,system_kind,customer_class,tariff_category,rule_id,tariff_id,decided_by,cap_amount,cap_source)
 SELECT 'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000003','credit_evaluation','cash',999,DATE '2026-01-01','TX','gas','distribution','residential','capcheck',r.id,tf.id,'core-review',999,'tariff'
 FROM public.deposit_rules r CROSS JOIN public.deposit_tariffs tf
 WHERE r.state_code='TX' AND r.service_type='gas' AND r.customer_class='residential' AND r.basis='credit_evaluation'
 AND r.owner_types @> ARRAY['municipal'] AND r.effective_to IS NULL AND tf.tenant_id='c0de0000-0000-4000-8000-000000000001' AND tf.tariff_category='capcheck';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture selected % rows, expected exactly one', n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: explicit: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: explicit: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
DO $probe$
DECLARE n bigint;
BEGIN
 RAISE NOTICE 'PROBE 03: nullsource; expected frozen: ACCEPTED (bug); desired REFUSED for missing cap source';
 BEGIN
  INSERT INTO public.deposits (tenant_id,customer_id,basis,instrument,principal,posted_on,state_code,service_type,system_kind,customer_class,tariff_category,rule_id,tariff_id,decided_by,cap_amount,cap_source)
 SELECT 'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000003','credit_evaluation','cash',999,DATE '2026-01-01','TX','gas','distribution','residential','capcheck',r.id,tf.id,'core-review',999,NULL
 FROM public.deposit_rules r CROSS JOIN public.deposit_tariffs tf
 WHERE r.state_code='TX' AND r.service_type='gas' AND r.customer_class='residential' AND r.basis='credit_evaluation'
 AND r.owner_types @> ARRAY['municipal'] AND r.effective_to IS NULL AND tf.tenant_id='c0de0000-0000-4000-8000-000000000001' AND tf.tariff_category='capcheck';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture selected % rows, expected exactly one', n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: nullsource: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: nullsource: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
DO $probe$
DECLARE n bigint;
BEGIN
 RAISE NOTICE 'PROBE 03: omitted; expected frozen: ACCEPTED (bug); desired REFUSED for omitted tariff cap';
 BEGIN
  INSERT INTO public.deposits (tenant_id,customer_id,basis,instrument,principal,posted_on,state_code,service_type,system_kind,customer_class,tariff_category,rule_id,tariff_id,decided_by,cap_amount,cap_source)
 SELECT 'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000003','credit_evaluation','cash',999,DATE '2026-01-01','TX','gas','distribution','residential','capcheck',r.id,tf.id,'core-review',NULL,NULL
 FROM public.deposit_rules r CROSS JOIN public.deposit_tariffs tf
 WHERE r.state_code='TX' AND r.service_type='gas' AND r.customer_class='residential' AND r.basis='credit_evaluation'
 AND r.owner_types @> ARRAY['municipal'] AND r.effective_to IS NULL AND tf.tenant_id='c0de0000-0000-4000-8000-000000000001' AND tf.tariff_category='capcheck';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture selected % rows, expected exactly one', n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 03: omitted: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03: omitted: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
ROLLBACK;
