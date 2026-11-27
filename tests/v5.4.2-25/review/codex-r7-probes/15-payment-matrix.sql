-- NOT EXECUTED. Owner, fresh clone with frozen r7 applied. No role DDL.
-- 64 ordered pairs, independent expected table, schema controls, exact combinations,
-- and transitivity of the no-finding relation. Every unexpected result raises.
-- R is a defensive helper input only: unruled is forbidden in a tariff.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE pay_matrix(t integer,l integer,verdict text,PRIMARY KEY(t,l));
DO $$
DECLARE bl jsonb; bt jsonb; l jsonb; t jsonb; v jsonb; expected_combo jsonb;
 k text; i integer; j integer; got text; wanted text; errs text[];
 names text[]:=ARRAY['R','F','U','W.9','W1','W1.1','A2','A3'];
 -- rows tariff, columns law; - no finding, L looser, N not comparable
 expected text[]:=ARRAY['--LLLLLL','--LLLLLL','-----L--','--L-LLNN',
                        '-----L--','--------','--LNLL-N','--LNLLN-'];
 pays jsonb:='[{"strategy":"unruled"},{"strategy":"full_bill"},
 {"strategy":"undisputed_charges"},{"strategy":"withhold_cap","fraction":0.9},
 {"strategy":"withhold_cap","fraction":1},{"strategy":"withhold_cap","fraction":1.1},
 {"strategy":"average_usage_cap","history_years":2,"no_history":"similar_customers"},
 {"strategy":"average_usage_cap","history_years":3,"no_history":"similar_customers"}]';
BEGIN
 SELECT terms INTO STRICT bl FROM public.dispute_rules
 WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 bt:=bl-'governs';
 FOREACH k IN ARRAY ARRAY['subjects','shelter_earned','shelter_ends','must_pay','blocks','duties'] LOOP
  bt:=jsonb_set(bt,ARRAY[k],(bt->k)-'citation');
 END LOOP;
 bt:=jsonb_set(bt,'{stages}',(SELECT jsonb_agg(x-'citation' ORDER BY n)
 FROM jsonb_array_elements(bt->'stages') WITH ORDINALITY z(x,n)));
 FOR i IN 1..8 LOOP FOR j IN 1..8 LOOP
  BEGIN
   t:=jsonb_set(bt,'{must_pay}',pays->(i-1)||'{"version":1,"id":"m1"}');
   l:=jsonb_set(bl,'{must_pay}',pays->(j-1)||'{"version":1,"id":"m1","citation":"probe"}');
   SELECT public.rule_terms_errors(json_schema,l,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute' AND terms_version=1;
   IF cardinality(errs) IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'law schema errors %',errs; END IF;
   SELECT public.rule_terms_errors(json_schema,t,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute_tariff' AND terms_version=1;
   IF i=1 THEN
    IF coalesce(cardinality(errs),0)=0 THEN RAISE EXCEPTION 'unruled tariff passed schema'; END IF;
   ELSIF cardinality(errs) IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'tariff schema errors %',errs;
   END IF;
   PERFORM public.dispute_terms_check('law',l); PERFORM public.dispute_terms_check('tariff',t);
   SELECT coalesce(string_agg(CASE verdict WHEN 'looser' THEN 'L' WHEN 'not_comparable' THEN 'N' ELSE '?' END,''),'-') INTO got
   FROM public.dispute_tariff_compare_sections(jsonb_build_object('terms',t),jsonb_build_array(jsonb_build_object('terms',l))) WHERE section='must_pay';
   wanted:=substr(expected[i],j,1);
   IF got IS DISTINCT FROM wanted THEN RAISE EXCEPTION 'expected %, got %',wanted,got; END IF;
   v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
   expected_combo:=CASE got WHEN '-' THEN t->'must_pay' WHEN 'L' THEN l->'must_pay'
    ELSE jsonb_build_object('either',jsonb_build_array(t->'must_pay',jsonb_set(l->'must_pay','{id}','"law:m1"'))) END;
   IF v->'must_pay' IS DISTINCT FROM expected_combo THEN RAISE EXCEPTION 'combination expected %, got %',expected_combo,v->'must_pay'; END IF;
   INSERT INTO pay_matrix VALUES(i,j,got);
   RAISE NOTICE 'tariff=% law=% SQLSTATE=00000 verdict=% exact combination passed',names[i],names[j],got;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'tariff=% law=% SQLSTATE=% message=%',names[i],names[j],SQLSTATE,SQLERRM; RAISE;
  END;
 END LOOP; END LOOP;
 IF EXISTS(SELECT FROM pay_matrix a JOIN pay_matrix b ON a.l=b.t JOIN pay_matrix c ON c.t=a.t AND c.l=b.l WHERE a.verdict='-' AND b.verdict='-' AND c.verdict<>'-') THEN
  RAISE EXCEPTION 'no-finding relation is not transitive';
 END IF;
 RAISE NOTICE 'SQLSTATE=00000 64 pairs and transitivity passed';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'matrix SQLSTATE=% message=%',SQLSTATE,SQLERRM; RAISE;
END $$;
ROLLBACK;
