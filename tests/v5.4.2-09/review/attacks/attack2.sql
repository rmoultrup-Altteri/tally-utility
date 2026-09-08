-- Part 2: config flips, renewal view, config parsing. Today assumed 2026-09-04 (UTC).
SET app.user_id = 'a1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;
SELECT CURRENT_DATE AS today;

\echo '=== T11: tenant_admin flips own category to flag-only via tally_app (can they?) ==='
UPDATE tenants SET settings = jsonb_set(coalesce(settings,'{}'), '{tax_exemptions,certificate_required,medical}', 'false')
 WHERE id='a0000000-0000-0000-0000-00000000000a';

\echo '=== T12: born-active, flag-only category, NO evidence (expect OK by design) ==='
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status, verified_by, verified_at, effective_start, effective_end)
VALUES ('e0000000-0000-0000-0000-000000000012','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','medical','active','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01','2027-06-01');

\echo '=== T13: flip category BACK to required — evidence-less active row persists (document) ==='
UPDATE tenants SET settings = jsonb_set(settings, '{tax_exemptions,certificate_required,medical}', 'true')
 WHERE id='a0000000-0000-0000-0000-00000000000a';
SELECT status, certificate_number, certificate_url FROM customer_tax_exemptions WHERE id='e0000000-0000-0000-0000-000000000012';

\echo '=== T14: malformed config value; born-active WITH evidence (does the write still raise?) ==='
UPDATE tenants SET settings = jsonb_set(settings, '{tax_exemptions,certificate_required,religious}', '"maybe"')
 WHERE id='a0000000-0000-0000-0000-00000000000a';
BEGIN;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, certificate_number, verified_by, verified_at, effective_start)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','religious','active','CERT-9','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01');
ROLLBACK;
\echo '=== T14b: malformed config, born-active WITHOUT evidence (expect raise, check errcode) ==='
BEGIN;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, verified_by, verified_at, effective_start)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','religious','active','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01');
ROLLBACK;
UPDATE tenants SET settings = settings #- '{tax_exemptions,certificate_required,religious}'
 WHERE id='a0000000-0000-0000-0000-00000000000a';

\echo '=== T15: seed renewal-view rows: due (end 2026-10-01) and lapsed (end 2026-08-01) ==='
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status, certificate_number, verified_by, verified_at, effective_start, effective_end)
VALUES ('e0000000-0000-0000-0000-000000000015','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','non_profit','active','C-DUE','a1000000-0000-0000-0000-000000000001',now(),'2025-10-02','2026-10-01'),
       ('e0000000-0000-0000-0000-000000000016','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','agricultural','active','C-LAPSE','a1000000-0000-0000-0000-000000000001',now(),'2025-08-02','2026-08-01');

\echo '=== T16: the view (expect e...15 renewal_due, e...16 lapsed, medical row NOT due yet? end 2027-06-01 no) ==='
SELECT exemption_id, exemption_type, effective_end, days_remaining, renewal_state FROM customer_tax_exemptions_renewal_due ORDER BY exemption_type;

\echo '=== T17: renewal on file for the due row (later bracket, active, evidence) -> suppressed ==='
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status, certificate_number, verified_by, verified_at, effective_start, effective_end)
VALUES ('e0000000-0000-0000-0000-000000000017','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','non_profit','active','C-RENEWED','a1000000-0000-0000-0000-000000000001',now(),'2026-10-02','2027-10-01');
SELECT exemption_id, exemption_type, renewal_state FROM customer_tax_exemptions_renewal_due ORDER BY exemption_type;

\echo '=== T18: PENDING renewal for the lapsed row -> must NOT suppress ==='
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status, certificate_number, effective_start, effective_end)
VALUES ('e0000000-0000-0000-0000-000000000018','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','agricultural','pending_verification','C-PEND','2026-08-02','2027-08-01');
SELECT exemption_id, exemption_type, renewal_state FROM customer_tax_exemptions_renewal_due ORDER BY exemption_type;

\echo '=== T19: should_charge_tax honours the active exemption at coordinates ==='
SELECT should_charge_tax('a2000000-0000-0000-0000-000000000002', true, 'gas', DATE '2026-09-01', now()) AS lapsed_agri_taxed_before_end,
       should_charge_tax('a2000000-0000-0000-0000-000000000002', true, 'gas', DATE '2026-07-01', now()) AS exempt_in_bracket;
