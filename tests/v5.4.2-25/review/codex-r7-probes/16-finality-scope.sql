-- R7 reissue; NOT EXECUTED. Predictions reconsidered against frozen r7.
-- NOT EXECUTED. Owner, fresh clone with frozen r7 applied. No role DDL.
-- Carried matrix cases (r7): every case validates both input documents, prints comparison and combined section.
-- Predictions: first case replaces t1.final=true with false, appends final l2.
-- Second sets t1.final=true and retains t2; final does not truncate the array.
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
  {
    "name": "short older policy final at first law place",
    "section": "stages",
    "law": [
      {
        "id": "l1",
        "decider": "designated_employee",
        "file_within": {
          "kind": "none"
        },
        "decide_within": {
          "kind": "none"
        },
        "final": false,
        "citation": "probe"
      },
      {
        "id": "l2",
        "decider": "regulator",
        "file_within": {
          "kind": "none"
        },
        "decide_within": {
          "kind": "none"
        },
        "final": true,
        "citation": "probe"
      }
    ],
    "tariff": [
      {
        "id": "t1",
        "decider": "designated_employee",
        "file_within": {
          "kind": "none"
        },
        "decide_within": {
          "kind": "none"
        },
        "final": true
      }
    ]
  },
  {
    "name": "law final with surviving later policy appeal",
    "section": "stages",
    "law": [
      {
        "id": "l1",
        "decider": "regulator",
        "file_within": {
          "kind": "none"
        },
        "decide_within": {
          "kind": "none"
        },
        "final": true,
        "citation": "probe"
      }
    ],
    "tariff": [
      {
        "id": "t1",
        "decider": "regulator",
        "file_within": {
          "kind": "none"
        },
        "decide_within": {
          "kind": "none"
        },
        "final": false
      },
      {
        "id": "t2",
        "decider": "executive",
        "file_within": {
          "kind": "none"
        },
        "decide_within": {
          "kind": "none"
        },
        "final": true
      }
    ]
  }
]$cases$::jsonb) LOOP
  BEGIN
   k:=c->>'section'; l:=jsonb_set(base_l,ARRAY[k],c->'law'); t:=jsonb_set(base_t,ARRAY[k],c->'tariff');
   SELECT public.rule_terms_errors(json_schema,l,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute' AND terms_version=1;
   IF cardinality(errs)>0 THEN RAISE EXCEPTION 'law schema errors %',errs; END IF;
   SELECT public.rule_terms_errors(json_schema,t,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute_tariff' AND terms_version=1;
   IF cardinality(errs)>0 THEN RAISE EXCEPTION 'tariff schema errors %',errs; END IF;
   PERFORM public.dispute_terms_check('law probe',l); PERFORM public.dispute_terms_check('tariff probe',t);
   RAISE NOTICE '% comparison=%',c->>'name',(SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]') FROM public.dispute_tariff_compare_sections(jsonb_build_object('terms',t),jsonb_build_array(jsonb_build_object('terms',l))) f);
   v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
   RAISE NOTICE '% SQLSTATE=00000 law=% tariff=% combined=%',c->>'name',l->k,t->k,v->k;
   IF c->>'name'='short older policy final at first law place' THEN
    IF (v#>>'{stages,0,final}'='false' AND v#>>'{stages,1,final}'='true'
        AND v#>>'{stages,0,id}'='t1' AND jsonb_array_length(v->'stages')=2) IS DISTINCT FROM true
    THEN RAISE EXCEPTION 'short-policy prediction failed %',v->'stages'; END IF;
   ELSE
    IF (v#>>'{stages,0,final}'='true' AND v#>>'{stages,1,id}'='t2'
        AND jsonb_array_length(v->'stages')=2) IS DISTINCT FROM true
    THEN RAISE EXCEPTION 'trailing-appeal prediction failed %',v->'stages'; END IF;
   END IF;

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
