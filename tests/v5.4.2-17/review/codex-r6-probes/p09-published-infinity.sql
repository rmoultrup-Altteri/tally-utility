-- Acceptance of inf, +Infinity or -inf as a value or either bound proves a nonfinite-value guard defect; finite controls must succeed.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r6';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION pg_temp.expect(label text, command text, state text, phrase text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual_state text; message text;
BEGIN
 BEGIN
  EXECUTE command;
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
 END;
 IF actual_state IS DISTINCT FROM state OR (state IS NOT NULL AND position(phrase in message)=0) THEN
  RAISE EXCEPTION 'FAIL %: expected % / %, got % / %',label,state,phrase,actual_state,message;
 END IF;
 RAISE NOTICE 'PASS % (state %, message %)',label,coalesce(actual_state,'success'),coalesce(message,'none');
END $$;

INSERT INTO public.rule_parameters(parameter_name,unit,scoped_by,description,source_note)
 VALUES('codex_unbounded_value','usd','{}','codex value','codex fixture');
DO $$ DECLARE v text; c text; BEGIN
 FOREACH v IN ARRAY ARRAY['inf','+Infinity','-inf','NaN'] LOOP
  PERFORM pg_temp.expect('published value '||v,format($q$INSERT INTO public.rule_parameter_values(parameter_name,effective_from,value,source_note)
   VALUES('codex_unbounded_value','2000-01-01',%L::numeric,'codex')$q$,v),'23514','finite published value');
  FOREACH c IN ARRAY ARRAY['value_min','value_max'] LOOP
   PERFORM pg_temp.expect(c||' '||v,format($q$INSERT INTO public.rule_parameters(parameter_name,unit,scoped_by,%I,description,source_note)
    VALUES('codex_bound','usd','{}',%L::numeric,'codex','codex')$q$,c,v),'23514','rule_parameters_range_check');
  END LOOP;
 END LOOP;
END $$;
INSERT INTO public.rule_parameter_values(parameter_name,effective_from,value,source_note)
 VALUES('codex_unbounded_value','2000-01-01',1.25,'finite control');
SELECT (public.rule_parameter_value_as_of('codex_unbounded_value',NULL,NULL,DATE '2000-06-01')).value AS finite_control;
ROLLBACK;
