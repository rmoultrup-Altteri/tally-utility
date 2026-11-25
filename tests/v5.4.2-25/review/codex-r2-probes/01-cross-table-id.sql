-- Codex r2: NOT EXECUTED. Run as owner on a fresh clone with frozen r2 applied.
-- No role is created, dropped, or altered. All fixture changes roll back.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = public, pg_temp;
INSERT INTO public.tenants (id,name,slug) VALUES ('00000000-0000-4000-8000-000000002da1','Codex r2','codex-r2');
INSERT INTO public.users (id,tenant_id,display_name,email,role) VALUES
 ('00000000-0000-4000-8000-000000002db1','00000000-0000-4000-8000-000000002da1','Operator','codex-r2@example.test','operator');
INSERT INTO public.customers (id,tenant_id,customer_number,customer_type) VALUES
 ('00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002da1','CR2','residential');
INSERT INTO public.service_locations (id,tenant_id,customer_id,location_number,address_line1,city,state,zip) VALUES
 ('00000000-0000-4000-8000-000000002dd1','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','CR2','1 Main','Austin','TX','78701');
INSERT INTO public.meters (id,tenant_id,meter_number,location_id,service_type) VALUES
 ('00000000-0000-4000-8000-000000002de1','00000000-0000-4000-8000-000000002da1','CR2','00000000-0000-4000-8000-000000002dd1','gas');
INSERT INTO public.meter_readings (id,tenant_id,meter_id,reading_date,reading_value) VALUES
 ('00000000-0000-4000-8000-000000002d71','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002de1',DATE '2026-03-01',50);
SET LOCAL app.user_id = '00000000-0000-4000-8000-000000002db1';
INSERT INTO public.places (id,kind_code,state_code,place_code,name,parent_place_id,effective_from,source_note)
SELECT '00000000-0000-4000-8000-000000002df1','municipality','TX','TX-CODEX-R2','Codex city',id,DATE '2000-01-01','review fixture'
 FROM public.places WHERE kind_code='state' AND state_code='TX';
INSERT INTO public.utility_service_profiles (tenant_id,service_type,system_kind,state_code,owner_type,commission_jurisdiction,owning_place_id,effective_from,evidence_reference,evidence_date)
VALUES ('00000000-0000-4000-8000-000000002da1','gas','distribution','TX','municipal',false,'00000000-0000-4000-8000-000000002df1',DATE '2000-01-01','review fixture',DATE '2000-01-01');

-- Four cases: amount and determination, each with distinct-ID control and matching-ID attempt.
-- Expected frozen r2: controls 23514; matching-ID cases ACCEPTED with later record_seq.
SET LOCAL ROLE tally_app;
DO $$
DECLARE d uuid; a uuid; e uuid; n uuid; law uuid; same boolean; kind text; ct int;
BEGIN
 SELECT id INTO STRICT law FROM public.dispute_rules WHERE customer_class='protected' AND 'municipal'=ANY(owner_types) AND effective_to IS NULL;
 FOREACH kind IN ARRAY ARRAY['amount','determination'] LOOP
  FOREACH same IN ARRAY ARRAY[false,true] LOOP
   d:=gen_random_uuid(); a:=gen_random_uuid(); e:=gen_random_uuid();
   n:=CASE WHEN same THEN e ELSE gen_random_uuid() END;
   INSERT INTO public.disputes(id,tenant_id,customer_id,reading_id,subject,received_on,channel)
   VALUES(d,'00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written');
   INSERT INTO public.dispute_amounts(id,tenant_id,dispute_id,amount,determined_by,effective_on)
   VALUES(a,'00000000-0000-4000-8000-000000002da1',d,40,'customer_claim','2026-03-02');
   BEGIN
    IF kind='amount' THEN
     WITH closing AS (
      INSERT INTO public.dispute_events(id,tenant_id,dispute_id,event_type,occurred_on)
      VALUES(e,'00000000-0000-4000-8000-000000002da1',d,'withdrawn','2026-03-03') RETURNING dispute_id
     ) INSERT INTO public.dispute_amounts(id,tenant_id,dispute_id,amount,determined_by,effective_on)
       SELECT n,'00000000-0000-4000-8000-000000002da1',dispute_id,10,'agreed','2026-03-03' FROM closing;
     SELECT count(*) INTO ct FROM public.dispute_amounts x JOIN public.dispute_events c ON c.id=e
      WHERE x.id=n AND x.record_seq>c.record_seq;
    ELSE
     WITH closing AS (
      INSERT INTO public.dispute_events(id,tenant_id,dispute_id,event_type,occurred_on)
      VALUES(e,'00000000-0000-4000-8000-000000002da1',d,'withdrawn','2026-03-03') RETURNING dispute_id
     ) INSERT INTO public.dispute_determinations(id,tenant_id,dispute_id,dispute_amount_id,state_code,service_type,system_kind,customer_class,rule_id,
       outcome,sheltered_amount,blocks,inputs,inputs_fingerprint,calculated_by)
       SELECT n,'00000000-0000-4000-8000-000000002da1',dispute_id,a,'TX','gas','distribution','protected',law,
        'no_terms',0,'{}','{}','review','codex-r2' FROM closing;
     SELECT count(*) INTO ct FROM public.dispute_determinations x JOIN public.dispute_events c ON c.id=e
      WHERE x.id=n AND x.record_seq>c.record_seq;
    END IF;
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE NOTICE '% same_id=% ACCEPTED SQLSTATE=00000 later_rows=% status=%',kind,same,ct,(SELECT status FROM public.disputes WHERE id=d);
   EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% same_id=% caught SQLSTATE=% message=%',kind,same,SQLSTATE,SQLERRM;
   END;
  END LOOP;
 END LOOP;
END $$;
RESET ROLE;
ROLLBACK;
