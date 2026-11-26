-- NOT EXECUTED. Owner, fresh clone with frozen r4 applied. No role DDL.
-- B1: every case validates both input documents, prints comparison and combined section.
-- Expected defect: subjects lose deposit; stages lose the 1-day employee decision;
-- incomparable starts/ends/pay return the law's section rather than refusing.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE base_l jsonb; base_t jsonb; l jsonb; t jsonb; c jsonb; k text; v jsonb; errs text[];
BEGIN
 SELECT terms INTO STRICT base_l FROM public.dispute_rules
 WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 base_t := base_l - 'governs';
 FOREACH k IN ARRAY ARRAY['subjects','shelter_earned','shelter_ends','must_pay','blocks','duties'] LOOP
  base_t := jsonb_set(base_t,ARRAY[k],(base_t->k)-'citation');
 END LOOP;
 base_t := jsonb_set(base_t,'{stages}',(SELECT jsonb_agg(x-'citation' ORDER BY n) FROM jsonb_array_elements(base_t->'stages') WITH ORDINALITY z(x,n)));
 FOR c IN SELECT value FROM jsonb_array_elements($cases$[
 {"name":"subjects crossed sets","section":"subjects","law":{"kind":"listed","codes":["meter_accuracy","calculation"],"excluded":[],"citation":"probe"},"tariff":{"kind":"listed","codes":["meter_accuracy","deposit"],"excluded":[]}},
 {"name":"stage mixed deadlines","section":"stages","law":[{"id":"s1","decider":"designated_employee","file_within":{"kind":"none"},"decide_within":{"kind":"none"},"final":false,"citation":"probe"},{"id":"s2","decider":"regulator","file_within":{"kind":"none"},"decide_within":{"kind":"days","days":10},"final":true,"citation":"probe"}],"tariff":[{"id":"s1","decider":"designated_employee","file_within":{"kind":"none"},"decide_within":{"kind":"days","days":1},"final":false},{"id":"s2","decider":"regulator","file_within":{"kind":"none"},"decide_within":{"kind":"days","days":15},"final":true}]},
 {"name":"incomparable starts","section":"shelter_earned","law":{"kind":"within_days","days":21,"from":"receipt","citation":"probe"},"tariff":{"kind":"before_termination"}},
 {"name":"incomparable ends","section":"shelter_ends","law":{"kind":"earlier_of_resolution_and_days","days":60,"from":"issue","citation":"probe"},"tariff":{"kind":"through_regulator_close"}},
 {"name":"incomparable average parameters","section":"must_pay","law":{"strategy":"average_usage_cap","version":1,"id":"m1","history_years":2,"no_history":"similar_customers","citation":"probe"},"tariff":{"strategy":"average_usage_cap","version":1,"id":"m1","history_years":3,"no_history":"similar_customers"}},
 {"name":"blocks union control","section":"blocks","law":{"codes":["late_fee"],"citation":"probe"},"tariff":{"codes":["notice_issue"]}},
 {"name":"duties union control","section":"duties","law":{"codes":["investigate"],"citation":"probe"},"tariff":{"codes":["offer_payment_arrangement"]}},
 {"name":"ordered end control","section":"shelter_ends","law":{"kind":"earlier_of_resolution_and_days","days":60,"from":"issue","citation":"probe"},"tariff":{"kind":"resolution"}}
 ]$cases$::jsonb) LOOP
  BEGIN
   k:=c->>'section'; l:=jsonb_set(base_l,ARRAY[k],c->'law'); t:=jsonb_set(base_t,ARRAY[k],c->'tariff');
   SELECT public.rule_terms_errors(json_schema,l,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute' AND terms_version=1;
   IF cardinality(errs)>0 THEN RAISE EXCEPTION 'law schema errors %',errs; END IF;
   SELECT public.rule_terms_errors(json_schema,t,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute_tariff' AND terms_version=1;
   IF cardinality(errs)>0 THEN RAISE EXCEPTION 'tariff schema errors %',errs; END IF;
   PERFORM public.dispute_terms_check('law probe',l); PERFORM public.dispute_terms_check('tariff probe',t);
   RAISE NOTICE '% comparison=%',c->>'name',public.dispute_tariff_compare(jsonb_build_object('terms',t),jsonb_build_array(jsonb_build_object('terms',l)));
   v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
   RAISE NOTICE '% SQLSTATE=00000 law=% tariff=% combined=%',c->>'name',l->k,t->k,v->k;
  EXCEPTION WHEN OTHERS THEN
   RAISE NOTICE '% SQLSTATE=% message=%',c->>'name',SQLSTATE,SQLERRM;
  END;
 END LOOP;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'setup SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
-- The newly granted comparator is an invoker and reads only the shared vocabulary.
SET LOCAL ROLE tally_core;
DO $$ DECLARE l jsonb; v jsonb; BEGIN
 SELECT to_jsonb(r) INTO STRICT l FROM public.dispute_rules r WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 v:=public.dispute_terms_combined(l,l);
 RAISE NOTICE 'core helper SQLSTATE=00000 terms_nonnull=%',v IS NOT NULL;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'core helper SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
RESET ROLE;
ROLLBACK;
