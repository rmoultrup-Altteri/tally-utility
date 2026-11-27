-- R7 reissue; NOT EXECUTED. Predictions reconsidered against frozen r7.
-- Codex r5: NOT EXECUTED. Owner, fresh clone with frozen r7 applied.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE law jsonb; tariff jsonb; stages jsonb; problems text[]; base_l jsonb; base_t jsonb; c jsonb;
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
 base_l := law; base_t := tariff;
 FOR c IN SELECT value FROM jsonb_array_elements($cases$[
 {"name":"equal finite filing / decision","law_file":{"kind":"days","days":30,"from":"prior_decision"},"tariff_file":{"kind":"days","days":30,"from":"prior_decision"},"tariff_decide":{"kind":"days","days":15},"ok":true},
 {"name":"shorter filing","law_file":{"kind":"days","days":30,"from":"prior_decision"},"tariff_file":{"kind":"days","days":29,"from":"prior_decision"},"tariff_decide":{"kind":"days","days":15},"ok":false},
 {"name":"longer filing quicker decision","law_file":{"kind":"days","days":30,"from":"prior_decision"},"tariff_file":{"kind":"days","days":31,"from":"prior_decision"},"tariff_decide":{"kind":"days","days":14},"ok":true},
 {"name":"different filing anchor","law_file":{"kind":"days","days":30,"from":"prior_decision"},"tariff_file":{"kind":"days","days":30,"from":"issue"},"tariff_decide":{"kind":"days","days":15},"ok":false},
 {"name":"unlimited filing vs finite law","law_file":{"kind":"days","days":30,"from":"prior_decision"},"tariff_file":{"kind":"none"},"tariff_decide":{"kind":"days","days":15},"ok":true},
 {"name":"finite filing vs unlimited law","law_file":{"kind":"none"},"tariff_file":{"kind":"days","days":3650,"from":"prior_decision"},"tariff_decide":{"kind":"days","days":15},"ok":false},
 {"name":"unlimited decision vs finite law","law_file":{"kind":"none"},"tariff_file":{"kind":"none"},"tariff_decide":{"kind":"none"},"ok":false}
 ]$cases$::jsonb) LOOP
  law := jsonb_set(base_l,'{terms,stages,1,file_within}',c->'law_file');
  tariff := jsonb_set(jsonb_set(base_t,'{stages,1,file_within}',c->'tariff_file'),'{stages,1,decide_within}',c->'tariff_decide');
  problems := public.dispute_tariff_compare(jsonb_build_object('terms',tariff),jsonb_build_array(law));
  RAISE NOTICE '% SQLSTATE=00000 expected_empty=% actual=%',c->>'name',c->>'ok',problems;
 END LOOP;
 -- Two law stages with the same decider need two distinct ordered tariff positions.
 law := jsonb_set(base_l,'{terms,stages,0,decider}','"regulator"');
 tariff := jsonb_set(base_t,'{stages}',jsonb_build_array(base_t#>'{stages,1}'));
 problems := public.dispute_tariff_compare(jsonb_build_object('terms',tariff),jsonb_build_array(law));
 RAISE NOTICE 'one position cannot satisfy two law stages SQLSTATE=00000 expected_nonempty actual=%',problems;
 tariff := jsonb_set(base_t,'{stages,0,decider}','"regulator"');
 problems := public.dispute_tariff_compare(jsonb_build_object('terms',tariff),jsonb_build_array(law));
 RAISE NOTICE 'two positions satisfy two law stages SQLSTATE=00000 expected_empty actual=%',problems;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'stage matrix caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
