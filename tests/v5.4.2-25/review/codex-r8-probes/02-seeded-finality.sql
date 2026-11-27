-- PREDICTED, not executed. Run as owner on a fresh clone with frozen r8 applied.
-- A helper witness for R10's seed claim, not proof this tariff can be filed
-- against the already-effective seeded law. No role DDL.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE l jsonb; t jsonb; v jsonb; k text; errs text[];
BEGIN
 SELECT terms INTO STRICT l FROM public.dispute_rules
 WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 t:=l-'governs';
 FOREACH k IN ARRAY ARRAY['subjects','shelter_earned','shelter_ends','must_pay','blocks','duties'] LOOP
  t:=jsonb_set(t,ARRAY[k],(t->k)-'citation');
 END LOOP;
 t:=jsonb_set(t,'{stages}',jsonb_build_array(jsonb_set((l#>'{stages,0}')-'citation','{final}','true')));
 SELECT public.rule_terms_errors(json_schema,t,true) INTO errs FROM public.rule_term_schemas
 WHERE terms_kind='dispute_tariff' AND terms_version=1;
 IF cardinality(errs)>0 THEN RAISE EXCEPTION 'schema errors %',errs; END IF;
 PERFORM public.dispute_terms_check('short older policy witness',t);
 v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
 IF (l#>>'{stages,0,final}'='false' AND t#>>'{stages,0,final}'='true'
     AND v#>>'{stages,0,final}'='false' AND jsonb_array_length(v->'stages')=2) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'unexpected seeded witness %',v; END IF;
 RAISE NOTICE 'PASS SQLSTATE=00000 message=seeded first stage clears hypothetical older policy finality law=% tariff=% combined=%',l->'stages',t->'stages',v->'stages';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'FAIL SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
