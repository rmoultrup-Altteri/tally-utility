-- ============================================================================
-- PATCH v5.4.0-01 — Application role, GRANTs, FORCE ROW LEVEL SECURITY
-- ============================================================================
-- Authority:   Ryan Moultrup, 2026-08-19 — split-role model chosen (parity
--              plan Phase 0.5 remnant; the open question flagged there and in
--              HANDOFF resume step 2). Runtime traffic uses a dedicated
--              non-owner role; migrations remain the schema owner's job.
--              Closes the CI-116 FORCE-RLS gap.
-- Affects:     No existing object is modified. Adds: role tally_app; schema/
--              table/function GRANTs; default privileges for future objects;
--              FORCE ROW LEVEL SECURITY on all 58 RLS-enabled tables.
--              materialized_view_refresh_log (the one non-RLS table, ops-only,
--              no tenant data) receives the same uniform grants and stays
--              non-RLS by design.
-- Mechanism:   tally_app is NOLOGIN — a privilege bundle, not a credential.
--              In production, create a LOGIN user per service and
--              GRANT tally_app TO <login user>; the app then connects as that
--              user and sets app.user_id per connection/transaction
--              (v5.4.0-00 contract). Because tally_app does not own the
--              tables, all 59 policies now bind it — this is the moment the
--              RLS layer becomes live for the first time.
--              FORCE ROW LEVEL SECURITY additionally binds the table OWNER,
--              closing CI-116's read-isolation gap (belt-and-suspenders: the
--              owner should only run migrations anyway). Note: superusers and
--              BYPASSRLS roles are exempt from RLS regardless of FORCE — in
--              the dev container the owner (tally) is a superuser, so FORCE
--              is observable there only via SET ROLE tally_app; on AWS the
--              owner will not be superuser and FORCE will bind it for DML.
--              Migration DML (backfills) must therefore either run with a
--              platform_admin app.user_id set, or temporarily NO FORCE the
--              affected table inside the migration transaction.
--              Cross-tenant application work (support tooling, platform jobs)
--              stays on the is_platform_admin() policy branch per the
--              existing policy shape; no BYPASSRLS role is created.
-- Idempotent:  yes (guarded CREATE ROLE; GRANT / ALTER DEFAULT PRIVILEGES /
--              FORCE are natively re-runnable).
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
-- ============================================================================

--
-- The application role. NOLOGIN: production LOGIN users are granted
-- membership; the role itself carries the privileges.
--
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tally_app') THEN
        CREATE ROLE tally_app NOLOGIN;
    END IF;
END
$$;

COMMENT ON ROLE tally_app IS
    'Application runtime role (v5.4.0-01). Non-owner, so all RLS policies apply. NOLOGIN by design: grant membership to per-service LOGIN users. Requires app.user_id session GUC for any tenant-scoped access (fail-closed). Migrations run as the schema owner, never as this role.';

--
-- Privileges. The schema has no sequences (all keys are uuid), so no
-- sequence grants are needed. Function EXECUTE is granted explicitly even
-- though PostgreSQL defaults functions to PUBLIC EXECUTE, so the grant
-- survives any future REVOKE ... FROM PUBLIC hardening.
--
GRANT USAGE ON SCHEMA public TO tally_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tally_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO tally_app;

--
-- Future objects created by the migration role in this schema inherit the
-- same grants, so per-patch GRANT boilerplate is not required.
--
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tally_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO tally_app;

--
-- FORCE ROW LEVEL SECURITY on every RLS-enabled table (58 of 59; the
-- exception is materialized_view_refresh_log, which has no RLS). Closes
-- CI-116: without FORCE, the table owner silently bypasses every policy.
--
ALTER TABLE public.account_ledger FORCE ROW LEVEL SECURITY;
ALTER TABLE public.adhoc_charges FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_audit_log FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_suggestions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_tool_calls FORCE ROW LEVEL SECURITY;
ALTER TABLE public.alerts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.anomalies FORCE ROW LEVEL SECURITY;
ALTER TABLE public.auto_pay_settings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.bill_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.billing_cycles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.billing_run_meters FORCE ROW LEVEL SECURITY;
ALTER TABLE public.billing_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.communities FORCE ROW LEVEL SECURITY;
ALTER TABLE public.correction_run_targets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.custom_field_definitions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.custom_location_types FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customer_contacts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customer_credits FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customer_interactions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customer_tax_exemptions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customer_winter_averages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.dunning_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.escheatment_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_fee_rules FORCE ROW LEVEL SECURITY;
ALTER TABLE public.import_column_mappings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.import_jobs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.import_mapping_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE public.import_staging FORCE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_applications FORCE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_line_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.invoices FORCE ROW LEVEL SECURITY;
ALTER TABLE public.meter_deployments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.meter_endpoint_history FORCE ROW LEVEL SECURITY;
ALTER TABLE public.meter_photos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.meter_readings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.meters FORCE ROW LEVEL SECURITY;
ALTER TABLE public.payment_methods FORCE ROW LEVEL SECURITY;
ALTER TABLE public.payment_provider_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.payments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rate_item_dependencies FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rate_item_history FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rate_item_history_archive FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rate_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rate_schedule_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rate_schedules FORCE ROW LEVEL SECURITY;
ALTER TABLE public.read_cycle_instances FORCE ROW LEVEL SECURITY;
ALTER TABLE public.read_cycle_meters FORCE ROW LEVEL SECURITY;
ALTER TABLE public.read_routes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.service_locations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.service_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_sequences FORCE ROW LEVEL SECURITY;
ALTER TABLE public.tenants FORCE ROW LEVEL SECURITY;
ALTER TABLE public.users FORCE ROW LEVEL SECURITY;
ALTER TABLE public.wna_monthly_adjustments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.wna_zones FORCE ROW LEVEL SECURITY;
