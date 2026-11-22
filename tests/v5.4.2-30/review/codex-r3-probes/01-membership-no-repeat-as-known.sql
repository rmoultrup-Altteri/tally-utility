-- Owner, fresh clone of tally with frozen r3 applied; revoke TEMP as in brief.
-- SOURCE-ONLY prediction; author runs. All changes end in ROLLBACK.
-- Like M12, plant only knowledge stamps to model an overlapping transaction:
-- successor began yesterday, predecessor voided today, successor inserted after void.
-- Every insert/void and tested read runs with all guards enabled.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.tenants (id,name,slug) VALUES ('00000000-0000-4000-8000-0000000033a1','Codex r3','codex-r3-no-repeat');
INSERT INTO public.users (id,tenant_id,display_name,email,role)
VALUES ('00000000-0000-4000-8000-0000000033b1','00000000-0000-4000-8000-0000000033a1','Codex r3','codex-r3@example.test','operator');
INSERT INTO public.customers (id,tenant_id,customer_number,customer_type)
VALUES ('00000000-0000-4000-8000-0000000033c1','00000000-0000-4000-8000-0000000033a1','C33','residential');
INSERT INTO public.service_locations (id,tenant_id,customer_id,location_number,address_line1,city,state,zip)
VALUES ('00000000-0000-4000-8000-0000000033d1','00000000-0000-4000-8000-0000000033a1','00000000-0000-4000-8000-0000000033c1','L33','1 Main','Fixture','TX','78701');
INSERT INTO public.places (id,kind_code,state_code,place_code,name,parent_place_id,effective_from,source_note)
SELECT v.id,v.kind,'TX',v.code,v.code,p.id,DATE '2000-01-01','Codex r3 fixture'
FROM (VALUES
 ('00000000-0000-4000-8000-0000000033e1'::uuid,'special_purpose_district','TX-C33-D1'),
 ('00000000-0000-4000-8000-0000000033e2'::uuid,'special_purpose_district','TX-C33-D2'),
 ('00000000-0000-4000-8000-0000000033e3'::uuid,'municipality','TX-C33-CITY')
) v(id,kind,code), public.places p
WHERE p.kind_code='state' AND p.state_code='TX' AND p.effective_to IS NULL;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.places WHERE place_code IN ('TX-C33-D1','TX-C33-D2','TX-C33-CITY')) <> 3 THEN
  RAISE EXCEPTION 'SETUP: expected one current TX state';
 END IF;
END $$;
ALTER TABLE public.places DISABLE TRIGGER a_enforce_place;
UPDATE public.places SET created_at=now()-interval '3 days'
WHERE (kind_code='state' AND state_code='TX') OR place_code IN ('TX-C33-D1','TX-C33-D2','TX-C33-CITY');
ALTER TABLE public.places ENABLE ALWAYS TRIGGER a_enforce_place;
ALTER TABLE public.service_location_state_history DISABLE TRIGGER append_only;
UPDATE public.service_location_state_history SET recorded_at=now()-interval '3 days'
WHERE service_location_id='00000000-0000-4000-8000-0000000033d1';
ALTER TABLE public.service_location_state_history ENABLE ALWAYS TRIGGER append_only;

SET LOCAL app.user_id='00000000-0000-4000-8000-0000000033b1';
SET LOCAL ROLE tally_app;
INSERT INTO public.premise_place_memberships (id,tenant_id,service_location_id,place_id,axis,place_kind,relation,valid_from,evidence_kind,evidence_reference,evidence_date)
SELECT v.id,'00000000-0000-4000-8000-0000000033a1','00000000-0000-4000-8000-0000000033d1',p.id,'tax',p.kind_code,'within',DATE '2020-01-01','address_lookup','Codex r3 fixture',DATE '2020-01-01'
FROM (VALUES
 ('00000000-0000-4000-8000-0000000033f1'::uuid,'TX-C33-D1'),
 ('00000000-0000-4000-8000-0000000033f2'::uuid,'TX-C33-D2'),
 ('00000000-0000-4000-8000-0000000033f3'::uuid,'TX-C33-CITY')
) v(id,code) JOIN public.places p ON p.place_code=v.code;
-- Control: the existing no_repeat rule rejects a live repeat even for NULL group.
DO $$ BEGIN
 BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id,service_location_id,place_id,axis,place_kind,valid_from,evidence_kind,evidence_reference,evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000033a1','00000000-0000-4000-8000-0000000033d1','00000000-0000-4000-8000-0000000033e1','tax','special_purpose_district',DATE '2020-01-01','address_lookup','duplicate control',DATE '2020-01-01');
  RAISE NOTICE 'CONTROL live duplicate unexpectedly admitted';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'CONTROL live duplicate SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
END $$;
RESET ROLE;
ALTER TABLE public.premise_place_memberships DISABLE TRIGGER a_enforce_premise_place_membership;
UPDATE public.premise_place_memberships SET created_at=now()-interval '2 days'
WHERE service_location_id='00000000-0000-4000-8000-0000000033d1';
ALTER TABLE public.premise_place_memberships ENABLE ALWAYS TRIGGER a_enforce_premise_place_membership;
SET LOCAL ROLE tally_app;
DO $$ DECLARE n integer; BEGIN
 SELECT count(*) INTO n FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000033d1',DATE '2026-06-01','tax',now()-interval '12 hours') WHERE kind_code='special_purpose_district';
 RAISE NOTICE 'CONTROL distinct districts legitimately stack: count=% (expect 2)',n;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'CONTROL stack SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
UPDATE public.premise_place_memberships SET void_reason='correct evidence / relation'
WHERE id IN ('00000000-0000-4000-8000-0000000033f1','00000000-0000-4000-8000-0000000033f3');
INSERT INTO public.premise_place_memberships (id,tenant_id,service_location_id,place_id,axis,place_kind,relation,valid_from,evidence_kind,evidence_reference,evidence_date)
SELECT v.id,'00000000-0000-4000-8000-0000000033a1','00000000-0000-4000-8000-0000000033d1',p.id,'tax',p.kind_code,v.relation,DATE '2020-01-01','address_lookup','corrected evidence',DATE '2020-01-01'
FROM (VALUES
 ('00000000-0000-4000-8000-0000000033f4'::uuid,'TX-C33-D1','within'),
 ('00000000-0000-4000-8000-0000000033f5'::uuid,'TX-C33-CITY','outside')
) v(id,code,relation) JOIN public.places p ON p.place_code=v.code;
RESET ROLE;
ALTER TABLE public.premise_place_memberships DISABLE TRIGGER a_enforce_premise_place_membership;
UPDATE public.premise_place_memberships SET created_at=now()-interval '1 day'
WHERE id IN ('00000000-0000-4000-8000-0000000033f4','00000000-0000-4000-8000-0000000033f5');
ALTER TABLE public.premise_place_memberships ENABLE ALWAYS TRIGGER a_enforce_premise_place_membership;
SET LOCAL ROLE tally_app;
DO $$ DECLARE n integer; rel text; BEGIN
 BEGIN
  SELECT count(*) INTO n FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000033d1',DATE '2026-06-01','tax',now()-interval '12 hours') WHERE place_code='TX-C33-D1';
  RAISE NOTICE 'B1 district returned % times (predicted 2, should refuse ambiguity)',n;
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B1 district SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
 BEGIN
  SELECT string_agg(relation,',' ORDER BY relation) INTO rel FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000033d1',DATE '2026-06-01','tax',now()-interval '12 hours') WHERE place_code='TX-C33-CITY';
  RAISE NOTICE 'B1 city relations=% (predicted outside,within; should refuse ambiguity)',rel;
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B1 city SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
 BEGIN
  SELECT string_agg(place_code||':'||relation,',' ORDER BY place_code,relation) INTO rel FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000033d1',DATE '2026-06-01','tax',now());
  RAISE NOTICE 'CONTROL now: one row per place, city outside; result=%',rel;
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'CONTROL now SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
END $$;
RESET ROLE;
ROLLBACK;
