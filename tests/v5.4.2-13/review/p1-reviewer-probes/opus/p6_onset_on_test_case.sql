-- S2 continued: a test found the meter fast, and the utility can show when the error began (e.g. a
-- register swap on 2025-09-01). A test-anchored case cannot record that onset.
INSERT INTO b13 VALUES ('t1', pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-05-15', 104));
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
\set ON_ERROR_STOP 0
INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction, claimed_from)
VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013e1','meter_error', pg_temp.id('t1'),
        DATE '2026-05-15','test_date','customer_owed', DATE '2025-09-01');
ROLLBACK;
