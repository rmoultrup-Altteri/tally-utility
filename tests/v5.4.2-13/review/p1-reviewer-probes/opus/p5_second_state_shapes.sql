\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
-- Owner, as the platform seeding a second state. Each statement is a plausible statutory shape.
INSERT INTO public.backbilling_customer_classes VALUES ('ZY','electric','residential','ZY residential','ZY code (fictional)', now());
-- S1: backbill limited to N months before the date the CORRECTED BILL is rendered (anchor = rebill / notice date)
INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, favourable_duty,
   adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, source_note)
VALUES ('ZY','electric','residential','unbilled_service','bill_date','permitted','include_whole','include_whole','adjustment',false,false,'uncapped',DATE '2000-01-01','S1 (fictional)');
-- S2: meter error: "for the period the error is known to have existed; if not known, one-half the time since the last test, not over 6 months"
--     needs a known-onset term AND a fallback (if-known-else), not the LATEST-of combinator
INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
   adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, source_note)
VALUES ('ZY','electric','residential','meter_error','test_date',ARRAY['fast','slow'],'mandatory','include_whole','include_whole','adjustment',false,false,'uncapped',DATE '2000-01-01','S2 (fictional)');
INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
SELECT id, 'favourable', 'error_onset_if_known', NULL FROM public.backbilling_rules WHERE state_code='ZY' AND cause='meter_error';
-- S3: window counted in days or billing cycles ("90 days", "the preceding four billing periods")
INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
SELECT id, 'adverse', 'billing_periods_before_anchor', NULL FROM public.backbilling_rules WHERE state_code='ZY' AND cause='meter_error';
-- S4: refunds carry interest at a stated rate; S5: the utility must offer an instalment plan as long as the backbill period
SELECT 'OBSERVED columns for interest / payment plan' AS what, count(*) FROM information_schema.columns
 WHERE table_schema='public' AND table_name IN ('backbilling_rules','meter_correction_period_evidence','meter_correction_evaluations')
   AND (column_name ~ 'interest|instal|payment_plan|arrangement');
-- S6: a second enforcement condition ("customer was notified of the estimate")
INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, favourable_duty,
   adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, enforce_condition, effective_from, source_note)
VALUES ('ZY','electric','residential','estimation_catchup','discovery_date','permitted','include_whole','include_whole','adjustment',false,false,'conditional','customer_notified_of_estimate',DATE '2000-01-01','S6 (fictional)');
