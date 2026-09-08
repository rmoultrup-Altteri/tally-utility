SET app.user_id = 'a1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;

\echo '=== T14c: store malformed value for real this time ==='
UPDATE tenants SET settings = jsonb_set(settings,'{tax_exemptions,certificate_required,religious}','"maybe"')
 WHERE id='a0000000-0000-0000-0000-00000000000a';
SELECT settings #>> '{tax_exemptions,certificate_required,religious}' AS religious_flag FROM tenants WHERE id='a0000000-0000-0000-0000-00000000000a';

\echo '--- T14c-1: born-active WITH evidence under malformed config (short-circuit? or loud raise?) ---'
BEGIN;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, certificate_number, verified_by, verified_at, effective_start)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000003','religious','active','CERT-9','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01');
ROLLBACK;
\echo '--- T14c-2: born-active WITHOUT evidence under malformed config (expect malformed-config raise) ---'
BEGIN;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, verified_by, verified_at, effective_start)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000003','religious','active','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01');
ROLLBACK;
\echo '--- T14c-3: accessor with JSON boolean true and number 1 ---'
UPDATE tenants SET settings = jsonb_set(settings,'{tax_exemptions,certificate_required,religious}','true') WHERE id='a0000000-0000-0000-0000-00000000000a';
SELECT tax_exemption_certificate_required('a0000000-0000-0000-0000-00000000000a','religious') AS bool_true;
UPDATE tenants SET settings = jsonb_set(settings,'{tax_exemptions,certificate_required,religious}','1') WHERE id='a0000000-0000-0000-0000-00000000000a';
SELECT tax_exemption_certificate_required('a0000000-0000-0000-0000-00000000000a','religious') AS num_one;
\echo '--- cleanup ---'
UPDATE tenants SET settings = settings #- '{tax_exemptions,certificate_required,religious}' WHERE id='a0000000-0000-0000-0000-00000000000a';

\echo '=== T24: rejected is terminal (v03 behavior preserved) ==='
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status)
VALUES ('e0000000-0000-0000-0000-000000000024','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000003','sales_for_resale','pending_verification');
UPDATE customer_tax_exemptions SET status='rejected' WHERE id='e0000000-0000-0000-0000-000000000024';
BEGIN;
UPDATE customer_tax_exemptions SET status='active', certificate_number='X', verified_by='a1000000-0000-0000-0000-000000000001', verified_at=now() WHERE id='e0000000-0000-0000-0000-000000000024';
ROLLBACK;

\echo '=== T25: pending -> expired refused (v03 behavior preserved) ==='
BEGIN;
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status)
VALUES ('e0000000-0000-0000-0000-000000000025','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000003','sales_for_resale','pending_verification');
UPDATE customer_tax_exemptions SET status='expired', certificate_number='X', effective_end='2026-01-01', verified_by='a1000000-0000-0000-0000-000000000001', verified_at=now() WHERE id='e0000000-0000-0000-0000-000000000025';
ROLLBACK;

\echo '=== T26: DELETE an asserted row (expect refused by bitemporal guard) ==='
BEGIN;
DELETE FROM customer_tax_exemptions WHERE id='e0000000-0000-0000-0000-000000000015';
ROLLBACK;

\echo '=== T27: search_path pin + single trigger binding sanity ==='
RESET ROLE;
SELECT p.proname, p.proconfig FROM pg_proc p WHERE p.proname IN ('enforce_tax_exemption_lifecycle','tax_exemption_certificate_required','tax_exemption_renewal_notice_days');
SELECT tgname FROM pg_trigger WHERE tgrelid='public.customer_tax_exemptions'::regclass AND NOT tgisinternal ORDER BY tgname;
