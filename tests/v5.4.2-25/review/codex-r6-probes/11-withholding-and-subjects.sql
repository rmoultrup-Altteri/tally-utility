-- NOT EXECUTED. Owner, fresh clone with frozen r6 applied. No role DDL.
-- Every case validates both input documents, prints comparison and combined section.
-- r6 predictions: undisputed vs cap1.1 is looser and law wins;
-- cap1.1 vs undisputed has no finding and tariff wins. At 1 both have no finding.
-- .9 and 1 are controls; four subject-kind orientations also print union results.
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
 FOR c IN SELECT value FROM jsonb_array_elements($cases$
[
  {
    "name": "B2 fraction 0.9, tariff undisputed",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "B2 fraction 0.9, law undisputed",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "B2 fraction 1, tariff undisputed",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "B2 fraction 1, law undisputed",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "B2 fraction 1.1, tariff undisputed",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "B2 fraction 1.1, law undisputed",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "subject union any/any",
    "section": "subjects",
    "law": {
      "kind": "any",
      "excluded": [
        "deposit"
      ],
      "citation": "probe"
    },
    "tariff": {
      "kind": "any",
      "excluded": [
        "calculation"
      ]
    }
  },
  {
    "name": "subject union any/listed",
    "section": "subjects",
    "law": {
      "kind": "any",
      "excluded": [
        "deposit"
      ],
      "citation": "probe"
    },
    "tariff": {
      "kind": "listed",
      "codes": [
        "meter_accuracy"
      ],
      "excluded": [
        "deposit"
      ]
    }
  },
  {
    "name": "subject union listed/any",
    "section": "subjects",
    "law": {
      "kind": "listed",
      "codes": [
        "calculation",
        "deposit"
      ],
      "excluded": [],
      "citation": "probe"
    },
    "tariff": {
      "kind": "any",
      "excluded": [
        "calculation"
      ]
    }
  },
  {
    "name": "subject union listed/listed",
    "section": "subjects",
    "law": {
      "kind": "listed",
      "codes": [
        "calculation",
        "deposit"
      ],
      "excluded": [],
      "citation": "probe"
    },
    "tariff": {
      "kind": "listed",
      "codes": [
        "meter_accuracy"
      ],
      "excluded": [
        "deposit"
      ]
    }
  }
]
$cases$::jsonb) LOOP
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
