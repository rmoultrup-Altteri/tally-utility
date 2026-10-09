-- Returned DEFECT rows prove unbounded published values admit numeric infinities (review S2; finite decimals are expected).

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r5';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';

INSERT INTO public.rule_parameters(parameter_name,unit,scoped_by,description,source_note)
 VALUES('codex_unbounded_value','usd','{}','codex published value','codex fixture');
INSERT INTO public.rule_parameter_values(parameter_name,effective_from,effective_to,value,source_note)
 VALUES('codex_unbounded_value','2000-01-01','2001-01-01','Infinity'::numeric,'codex infinity'),
       ('codex_unbounded_value','2001-01-01','2002-01-01','-Infinity'::numeric,'codex negative infinity');
SELECT 'DEFECT: nonfinite published value' AS result,value
 FROM public.rule_parameter_values WHERE parameter_name='codex_unbounded_value';
SELECT (public.rule_parameter_value_as_of('codex_unbounded_value',NULL,NULL,DATE '2000-06-01')).value AS nonfinite_lookup;

ROLLBACK;
