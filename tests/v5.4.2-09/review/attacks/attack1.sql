-- Attack battery part 1: gate bypass routes. Run as tally_app, tenant A admin.
SET app.user_id = 'a1000000-0000-0000-0000-000000000001';
SET ROLE tally_app;

\echo '=== T1: draft without evidence (expect OK) ==='
INSERT INTO customer_tax_exemptions (id, tenant_id, customer_id, exemption_type)
VALUES ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000001','government');

\echo '=== T2: verify draft to active WITHOUT evidence (expect REFUSED 23514) ==='
BEGIN;
UPDATE customer_tax_exemptions SET status='active', verified_by='a1000000-0000-0000-0000-000000000001', verified_at=now()
 WHERE id='e0000000-0000-0000-0000-000000000001';
ROLLBACK;

\echo '=== T3: verify with whitespace-only certificate_number (expect REFUSED) ==='
BEGIN;
UPDATE customer_tax_exemptions SET status='active', certificate_number='   ', verified_by='a1000000-0000-0000-0000-000000000001', verified_at=now()
 WHERE id='e0000000-0000-0000-0000-000000000001';
ROLLBACK;

\echo '=== T4: verify with certificate_url only (expect OK) ==='
UPDATE customer_tax_exemptions SET status='active', certificate_url='https://docs/letter.pdf', verified_by='a1000000-0000-0000-0000-000000000001', verified_at=now(), effective_start='2026-01-01', effective_end='2027-01-01'
 WHERE id='e0000000-0000-0000-0000-000000000001';
SELECT status, recorded_at IS NOT NULL AS asserted FROM customer_tax_exemptions WHERE id='e0000000-0000-0000-0000-000000000001';

\echo '=== T5: clear evidence on asserted row (expect REFUSED by bitemporal freeze) ==='
BEGIN;
UPDATE customer_tax_exemptions SET certificate_url=NULL WHERE id='e0000000-0000-0000-0000-000000000001';
ROLLBACK;

\echo '=== T6: INSERT born-active, change_type=backfill, recorded_at pre-set, NO evidence (expect REFUSED) ==='
BEGIN;
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, verified_by, verified_at, recorded_at, change_type, effective_start, effective_end)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000002','non_profit','active','a1000000-0000-0000-0000-000000000001',now(),now(),'backfill','2025-01-01','2026-12-31');
ROLLBACK;

\echo '=== T7: correction dance — close asserted row + insert correction WITHOUT evidence (expect REFUSED) ==='
BEGIN;
UPDATE customer_tax_exemptions SET recorded_until=now(), closed_type='superseded', closed_reason='test correction', closed_by='a1000000-0000-0000-0000-000000000001'
 WHERE id='e0000000-0000-0000-0000-000000000001';
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, verified_by, verified_at, change_type, change_reason, supersedes_id, effective_start, effective_end)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000001','government','active','a1000000-0000-0000-0000-000000000001',now(),'correction','drop evidence','e0000000-0000-0000-0000-000000000001','2026-01-01','2027-01-01');
ROLLBACK;

\echo '=== T8: revoked successor WITHOUT evidence (expect REFUSED) ==='
BEGIN;
UPDATE customer_tax_exemptions SET recorded_until=now(), closed_type='superseded', closed_reason='revoking', closed_by='a1000000-0000-0000-0000-000000000001'
 WHERE id='e0000000-0000-0000-0000-000000000001';
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, verified_by, verified_at, change_type, supersedes_id, effective_start, effective_end, revoked_at, revoked_by)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000001','government','revoked','a1000000-0000-0000-0000-000000000001',now(),'succession','e0000000-0000-0000-0000-000000000001','2026-01-01','2026-06-01',now(),'a1000000-0000-0000-0000-000000000001');
ROLLBACK;

\echo '=== T9: same revoked successor WITH evidence (expect OK, then rollback) ==='
BEGIN;
UPDATE customer_tax_exemptions SET recorded_until=now(), closed_type='superseded', closed_reason='revoking', closed_by='a1000000-0000-0000-0000-000000000001'
 WHERE id='e0000000-0000-0000-0000-000000000001';
INSERT INTO customer_tax_exemptions (tenant_id, customer_id, exemption_type, status, certificate_url, verified_by, verified_at, change_type, supersedes_id, effective_start, effective_end, revoked_at, revoked_by)
VALUES ('a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000001','government','revoked','https://docs/letter.pdf','a1000000-0000-0000-0000-000000000001',now(),'succession','e0000000-0000-0000-0000-000000000001','2026-01-01','2026-06-01',now(),'a1000000-0000-0000-0000-000000000001');
SELECT 'T9 insert ok' AS result;
ROLLBACK;

\echo '=== T10: cross-tenant config probe — tenant A user reads tenant B config (expect no_data_found) ==='
SELECT tax_exemption_certificate_required('b0000000-0000-0000-0000-00000000000b','government');
