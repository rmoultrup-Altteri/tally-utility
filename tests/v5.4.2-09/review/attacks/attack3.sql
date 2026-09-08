SET app.user_id = 'a1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;

\echo '=== T11b: proper flag-only flip (nested object built explicitly) ==='
UPDATE tenants SET settings = coalesce(settings,'{}'::jsonb) || '{"tax_exemptions":{"certificate_required":{"medical":false}}}'::jsonb
 WHERE id='a0000000-0000-0000-0000-00000000000a';
SELECT settings #>> '{tax_exemptions,certificate_required,medical}' AS medical_flag,
       tax_exemption_certificate_required('a0000000-0000-0000-0000-00000000000a','medical') AS accessor
  FROM tenants WHERE id='a0000000-0000-0000-0000-00000000000a';

\echo '=== T12b: born-active, flag-only, NO evidence (expect OK) ==='
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status, verified_by, verified_at, effective_start, effective_end)
VALUES ('e0000000-0000-0000-0000-000000000012','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000001','medical','active','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01','2027-06-01');
SELECT status, recorded_at IS NOT NULL AS asserted FROM customer_tax_exemptions WHERE id='e0000000-0000-0000-0000-000000000012';

\echo '=== T13b: flip back to required; evidence-less active row persists and still exempts ==='
UPDATE tenants SET settings = jsonb_set(settings,'{tax_exemptions,certificate_required,medical}','true')
 WHERE id='a0000000-0000-0000-0000-00000000000a';
SELECT should_charge_tax('a2000000-0000-0000-0000-000000000001', true, 'gas', DATE '2026-05-05', now()) AS still_exempt_no_evidence;

\echo '=== T19b: lapsed exemption stops exempting after effective_end (isolated customer) ==='
SET app.user_id TO DEFAULT;
RESET ROLE;
INSERT INTO customers (id, tenant_id, customer_number) VALUES ('a2000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-00000000000a','CUST-003');
SET app.user_id = 'a1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, certificate_number, verified_by, verified_at, effective_start, effective_end)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000003','non_profit','active','C-L2','a1000000-0000-0000-0000-000000000001',now(),'2025-08-02','2026-08-01');
SELECT should_charge_tax('a2000000-0000-0000-0000-000000000003', true, 'gas', DATE '2026-09-01', now()) AS taxed_after_lapse,
       should_charge_tax('a2000000-0000-0000-0000-000000000003', true, 'gas', DATE '2026-08-01', now()) AS exempt_on_end_date;

\echo '=== T20: bad renewal_notice_days on tenant B; tenant A queue unaffected, B queue raises ==='
RESET ROLE; SET app.user_id TO DEFAULT;
UPDATE tenants SET settings = coalesce(settings,'{}'::jsonb) || '{"tax_exemptions":{"renewal_notice_days_before":0}}'::jsonb
 WHERE id='b0000000-0000-0000-0000-00000000000b';
-- give tenant B an expiring exemption (as B admin)
SET app.user_id = 'b1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, certificate_number, verified_by, verified_at, effective_start, effective_end)
VALUES ('b0000000-0000-0000-0000-00000000000b','b2000000-0000-0000-0000-000000000001','government','active','B-CERT','b1000000-0000-0000-0000-000000000001',now(),'2025-10-02','2026-10-01');
\echo '--- B admin reads own queue (expect check_violation raise) ---'
SELECT count(*) FROM customer_tax_exemptions_renewal_due;
RESET ROLE;
\echo '--- A admin reads own queue (expect rows, no raise) ---'
SET app.user_id = 'a1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;
SELECT count(*) FROM customer_tax_exemptions_renewal_due;
RESET ROLE;
\echo '--- platform_admin reads global queue (expect raise: one bad tenant blocks all) ---'
SET app.user_id = 'c1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;
SELECT count(*) FROM customer_tax_exemptions_renewal_due;
RESET ROLE;

\echo '=== T21: renewal_notice_days parsing: 60.5 and "abc" ==='
SET app.user_id TO DEFAULT;
UPDATE tenants SET settings = jsonb_set(settings,'{tax_exemptions,renewal_notice_days_before}','60.5') WHERE id='b0000000-0000-0000-0000-00000000000b';
SELECT public.tax_exemption_renewal_notice_days('b0000000-0000-0000-0000-00000000000b');
UPDATE tenants SET settings = jsonb_set(settings,'{tax_exemptions,renewal_notice_days_before}','"abc"') WHERE id='b0000000-0000-0000-0000-00000000000b';
SELECT public.tax_exemption_renewal_notice_days('b0000000-0000-0000-0000-00000000000b');
UPDATE tenants SET settings = settings #- '{tax_exemptions,renewal_notice_days_before}' WHERE id='b0000000-0000-0000-0000-00000000000b';

\echo '=== T22: notice-window boundary: end exactly today+60 excluded, today+59 included ==='
SET app.user_id = 'a1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;
BEGIN;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, certificate_number, verified_by, verified_at, effective_start, effective_end)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000003','educational','active','C-B60','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01', CURRENT_DATE + 60),
       ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000003','religious','active','C-B59','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01', CURRENT_DATE + 59);
SELECT exemption_type, days_remaining, notice_window_opened_on, renewal_state FROM customer_tax_exemptions_renewal_due WHERE exemption_type IN ('educational','religious');
ROLLBACK;
