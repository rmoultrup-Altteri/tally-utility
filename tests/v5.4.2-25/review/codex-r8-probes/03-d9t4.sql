-- PREDICTED, not executed. Owner, fresh clone with frozen r8 applied.
-- Exact frozen battery constructors; no role DDL. Expected PASS for exact
-- alternatives and rejection of dropped, reversed, duplicate and NULL values.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.tdoc(p_over jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"citation": "Battery tariff, disputes",
           "subjects": {"kind": "any", "excluded": []},
           "shelter_earned": {"kind": "before_termination"},
           "must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m1"},
           "shelter_ends": {"kind": "resolution"},
           "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                      {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": true}],
           "blocks": {"codes": ["notice_issue", "disconnect_order", "disconnect_execute", "late_fee"]},
           "duties": {"codes": ["investigate", "report_result", "inform_complaint_route"]}}'::jsonb || p_over
$$;
CREATE FUNCTION pg_temp.avg(p_id text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('strategy', 'average_usage_cap', 'version', 1, 'id', p_id, 'history_years', 2, 'no_history', 'similar_customers')
$f$;
CREATE FUNCTION pg_temp.wcap(p_fraction numeric, p_id text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('strategy', 'withhold_cap', 'version', 1, 'id', p_id, 'fraction', p_fraction, 'citation', 'battery')
$f$;
DO $$
DECLARE l jsonb; t jsonb; v jsonb; expected jsonb; bad jsonb;
BEGIN
 SELECT terms INTO STRICT l FROM public.dispute_rules
 WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 t:=pg_temp.tdoc(jsonb_build_object('must_pay',pg_temp.avg('m1')));
 l:=l || jsonb_build_object('must_pay',pg_temp.wcap(0.9,'m2'));
 v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
 expected:=jsonb_build_array(pg_temp.avg('m1'),pg_temp.wcap(0.9,'m2'));
 IF NOT ((v#>'{must_pay,either}') IS NOT DISTINCT FROM expected)
 THEN RAISE EXCEPTION 'D9t4 unexpected result %',v; END IF;
 FOR bad IN SELECT x FROM (VALUES
  (jsonb_build_array(expected->0)),(jsonb_build_array(expected->1)),
  (jsonb_build_array(expected->1,expected->0)),
  (jsonb_build_array(expected->0,expected->0)),(NULL::jsonb)) q(x)
 LOOP
  IF bad IS NOT DISTINCT FROM expected THEN RAISE EXCEPTION 'bad value accepted %',bad; END IF;
 END LOOP;
 RAISE NOTICE 'PASS SQLSTATE=00000 message=D9t4 exact ordered terms and all five negative controls result=%',v->'must_pay';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'FAIL SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
