-- Source-review probe 06; run as clone owner (fixture setup), then tally_app.
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
INSERT INTO public.deposit_utility_categories (tenant_id,state_code,service_type,category_code,law_class,description) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','instalments','residential','review fixture');
INSERT INTO public.deposit_tariffs (tenant_id,state_code,service_type,system_kind,tariff_category,effective_from,tariff_reference,terms_kind,terms_version,terms_source) VALUES ('c0de0000-0000-4000-8000-000000000001','TX','gas','distribution','instalments',DATE '2020-01-01','review fixture','deposit_tariff',1,$doc${"citation":"Codex review fixture","amount":{"strategy":"fixed","version":1,"amount":100},"triggers":[],"waivers":[],"instalments":[{"id":"i1","fraction":0.5,"days_after":0},{"id":"i2","fraction":0.5,"days_after":30}]}$doc$);
  INSERT INTO public.deposits (id,tenant_id,customer_id,basis,instrument,principal,posted_on,state_code,service_type,system_kind,customer_class,tariff_category,rule_id,tariff_id,decided_by,received_at_posting,cap_amount,cap_source)
 SELECT 'c0de0000-0000-4000-8000-000000000004','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000003','credit_evaluation','cash',100,DATE '2026-01-01','TX','gas','distribution','residential','instalments',r.id,tf.id,'core-review',50,100,'tariff'
 FROM public.deposit_rules r CROSS JOIN public.deposit_tariffs tf
 WHERE r.state_code='TX' AND r.service_type='gas' AND r.customer_class='residential' AND r.basis='credit_evaluation'
 AND r.owner_types @> ARRAY['municipal'] AND r.effective_to IS NULL AND tf.tenant_id='c0de0000-0000-4000-8000-000000000001' AND tf.tariff_category='instalments';
 INSERT INTO public.deposit_instalments (tenant_id,deposit_id,instalment_no,amount,due_on)
 VALUES ('c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000004',2,50,DATE '2026-01-31');
SET CONSTRAINTS ALL IMMEDIATE;
DO $probe$ BEGIN
 RAISE NOTICE 'PROBE 06: valid two-part tariff schedule passed initial completeness check (control)';
END $probe$;
DO $probe$
BEGIN
 RAISE NOTICE 'PROBE 06: append after completeness check; expected frozen: REFUSED for extra instalment';
 BEGIN
  INSERT INTO public.deposit_instalments (tenant_id,deposit_id,instalment_no,amount,due_on)
  VALUES ('c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000004',3,10,DATE '2026-03-01');
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 06: append after completeness check: ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 06: append after completeness check: REFUSED [%] %', SQLSTATE, SQLERRM;
 END;
END $probe$;
DO $probe$
DECLARE n integer; total numeric;
BEGIN
 SELECT count(*) + 1, 50 + sum(amount) INTO n,total FROM public.deposit_instalments
 WHERE deposit_id='c0de0000-0000-4000-8000-000000000004';
 RAISE NOTICE 'PROBE 06: final schedule has % parts and total %; valid is 2 and 100; frozen expected 2 and 100',n,total;
END $probe$;
ROLLBACK;
