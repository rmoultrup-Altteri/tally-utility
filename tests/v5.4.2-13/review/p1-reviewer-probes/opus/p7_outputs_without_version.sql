-- Which core outputs name the rule row / core version / evaluation that produced them?
SELECT table_name,
       bool_or(column_name = 'rule_id')       AS has_rule_id,
       bool_or(column_name = 'calculated_by') AS has_core_version,
       bool_or(column_name = 'evaluation_id' OR column_name = 'frozen_evaluation_id') AS has_evaluation
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name IN ('meter_correction_evaluations','meter_correction_period_evidence','meter_correction_approvals',
                      'meter_correction_holds','meter_correction_cases')
 GROUP BY table_name ORDER BY table_name;
