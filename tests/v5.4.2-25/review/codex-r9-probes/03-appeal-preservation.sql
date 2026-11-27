-- PREDICTED, NOT EXECUTED. Owner, fresh clone with frozen r9 applied.
-- Direct-helper witnesses, not claims that historical policies can be newly filed.
-- No role DDL. All errors print SQLSTATE and message; inspect FAIL notices.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE l jsonb; t jsonb; v jsonb; k text; errs text[]; r record; n integer := 0;
BEGIN
 -- Inspect precisely the four Texas seed identities from the frozen patch.
 FOR r IN SELECT customer_class, owner_types, terms FROM public.dispute_rules
 WHERE state_code='TX' AND service_type='gas' AND effective_from=DATE '2004-07-12'
 AND customer_class IN ('protected','unprotected')
 AND (owner_types=ARRAY['cooperative','investor_owned']::text[] OR owner_types=ARRAY['municipal']::text[])
 LOOP
  n:=n+1;
  IF jsonb_array_length(coalesce(r.terms->'stages','[]'))>0
     AND (r.terms#>'{stages,-1,final}') IS DISTINCT FROM 'true'::jsonb THEN
   RAISE EXCEPTION 'seed has nonfinal last stage: %',r;
  END IF;
  RAISE NOTICE 'seed SQLSTATE=00000 message=last stage final or no last stage class=% owners=% stages=%',r.customer_class,r.owner_types,r.terms->'stages';
 END LOOP;
 IF n<>4 THEN RAISE EXCEPTION 'expected four seed identities, found %',n; END IF;
 SELECT terms INTO STRICT l FROM public.dispute_rules
 WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 t:=l-'governs';
 FOREACH k IN ARRAY ARRAY['subjects','shelter_earned','shelter_ends','must_pay','blocks','duties'] LOOP
  t:=jsonb_set(t,ARRAY[k],(t->k)-'citation');
 END LOOP;
 t:=jsonb_set(t,'{stages}',(SELECT jsonb_agg(x-'citation' ORDER BY i) FROM jsonb_array_elements(l->'stages') WITH ORDINALITY q(x,i)));
 -- Both law positions replaced by same-decider policy stages with different IDs.
 -- The policy's regulator filing window is narrower and decision time slower.
 t:=jsonb_set(t,'{stages,0,id}','"t1"');
 t:=jsonb_set(t,'{stages,1,id}','"t2"');
 t:=jsonb_set(t,'{stages,1,file_within}','{"kind":"days","days":1,"from":"prior_decision"}');
 t:=jsonb_set(t,'{stages,1,decide_within}','{"kind":"days","days":30}');
 SELECT public.rule_terms_errors(json_schema,t,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute_tariff' AND terms_version=1;
 IF cardinality(errs)>0 THEN RAISE EXCEPTION 'schema errors %',errs; END IF;
 PERFORM public.dispute_terms_check('displaced law stage witness',t);
 v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
 IF (jsonb_array_length(v->'stages')=2 AND v#>>'{stages,1,id}'='t2'
 AND v#>>'{stages,1,decider}'='regulator' AND v#>'{stages,1,file_within}'=l#>'{stages,1,file_within}'
 AND v#>'{stages,1,decide_within}'=l#>'{stages,1,decide_within}'
 AND v#>'{stages,1,final}'=l#>'{stages,1,final}') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'displaced appeal prediction failed %',v; END IF;
 RAISE NOTICE 'PASS SQLSTATE=00000 message=policy replaces law appeal identity but retains law protections stages=%',v->'stages';
 -- Different decider: law appeal retained verbatim and unused policy stage appended.
 t:=jsonb_set(t,'{stages,1,decider}','"executive"');
 v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
 IF (jsonb_array_length(v->'stages')=3 AND v#>'{stages,1}'=l#>'{stages,1}'
 AND v#>'{stages,2}'=t#>'{stages,1}') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'unmatched appeal prediction failed %',v; END IF;
 RAISE NOTICE 'PASS SQLSTATE=00000 message=law appeal and displaced policy appeal retained stages=%',v->'stages';
 -- Hypothetical nonfinal last law stage: the flag replaces the policy's final.
 l:=jsonb_set(l,'{stages,1,final}','false');
 t:=jsonb_set(t,'{stages,1,decider}','"regulator"');
 v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
 IF (jsonb_array_length(v->'stages')=2 AND v#>'{stages,1,final}'='false'::jsonb) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'last-stage finality prediction failed %',v; END IF;
 RAISE NOTICE 'PASS SQLSTATE=00000 message=hypothetical last law stage replaces policy finality stages=%',v->'stages';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'FAIL SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
