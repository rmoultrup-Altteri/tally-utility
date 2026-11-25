-- Codex r3: NOT EXECUTED. Owner, fresh clone with frozen r3 applied.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE law jsonb; tariff jsonb; stages jsonb; problems text[];
BEGIN
 SELECT to_jsonb(r) INTO STRICT law FROM public.dispute_rules r
 WHERE r.customer_class='protected' AND 'investor_owned'=ANY(r.owner_types) AND r.effective_to IS NULL;
 tariff := (law->'terms')-'governs';
 -- Convert law sections to tariff sections (citations are only at top level).
 tariff := jsonb_set(tariff,'{subjects}',(tariff->'subjects')-'citation');
 tariff := jsonb_set(tariff,'{shelter_earned}',(tariff->'shelter_earned')-'citation');
 tariff := jsonb_set(tariff,'{shelter_ends}',(tariff->'shelter_ends')-'citation');
 tariff := jsonb_set(tariff,'{must_pay}',(tariff->'must_pay')-'citation');
 tariff := jsonb_set(tariff,'{blocks}',(tariff->'blocks')-'citation');
 tariff := jsonb_set(tariff,'{duties}',(tariff->'duties')-'citation');
 SELECT jsonb_agg(s-'citation' ORDER BY ord) INTO stages FROM jsonb_array_elements(tariff->'stages') WITH ORDINALITY t(s,ord);
 tariff := jsonb_set(tariff,'{stages}',stages);
 problems := public.dispute_tariff_compare(jsonb_build_object('terms',tariff),jsonb_build_array(law));
 RAISE NOTICE 'equal-stage control SQLSTATE=00000 problems=%',problems;
 tariff := jsonb_set(tariff,'{stages,1,decide_within,days}','3650');
 tariff := jsonb_set(tariff,'{stages,1,file_within}','{"kind":"days","days":1,"from":"prior_decision"}');
 PERFORM public.dispute_terms_check('Codex stage probe',tariff);
 RAISE NOTICE 'tariff schema errors=%',public.rule_terms_errors((SELECT json_schema FROM public.rule_term_schemas WHERE terms_kind='dispute_tariff' AND terms_version=1),tariff,true);
 problems := public.dispute_tariff_compare(jsonb_build_object('terms',tariff),jsonb_build_array(law));
 RAISE NOTICE '3650-day decision / one-day appeal SQLSTATE=00000 problems=% (predicted nonempty in r3)',problems;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'stage probe caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
