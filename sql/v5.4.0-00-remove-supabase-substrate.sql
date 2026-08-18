-- ============================================================================
-- PATCH v5.4.0-00 — Remove the Supabase auth substrate
-- ============================================================================
-- Authority:   Ryan Moultrup, 2026-08-18 — the database will be PostgreSQL
--              hosted on AWS, not Supabase. All Supabase references removed.
--              (Parity plan Phase 0.5; gas-billing-memory/application/
--              schema-parity-plan.md)
-- Affects:     public.get_user_tenant_id(), public.is_platform_admin() —
--              the two wrapper functions every one of the 59 RLS policies
--              routes through. No policy text changes. Two column COMMENTs
--              updated. No enforcement grades change (mechanism swap, same
--              semantics); CI-116's FORCE-RLS gap is unaffected and remains
--              open under Phase 3.
-- Mechanism:   auth.uid() (Supabase) is replaced by the session context GUC
--              app.user_id, read with current_setting(..., true) so an unset
--              context yields NULL — get_user_tenant_id() returns NULL (all
--              tenant policies deny) and is_platform_admin() returns false.
--              Fail-closed. The application sets, per connection or per
--              transaction:  SET app.user_id = '<users.id uuid>';
--              This matches the schema's existing GUC pattern
--              (app.void_operation, used by void_invoice()).
-- Idempotent:  yes (CREATE OR REPLACE / COMMENT ON overwrite).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_user_tenant_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT tenant_id FROM users WHERE id = current_setting('app.user_id', true)::uuid
$$;

COMMENT ON FUNCTION public.get_user_tenant_id() IS
    'Tenant of the acting user, resolved from the app.user_id session GUC (set by the application per connection/transaction). NULL when no context is set, which denies all tenant-scoped RLS policies — fail-closed. Replaced Supabase auth.uid() in v5.4.0-00.';

CREATE OR REPLACE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT EXISTS(SELECT 1 FROM users WHERE id = current_setting('app.user_id', true)::uuid AND role = 'platform_admin')
$$;

COMMENT ON FUNCTION public.is_platform_admin() IS
    'True when the acting user (app.user_id session GUC) has role platform_admin. False when no context is set — fail-closed. Replaced Supabase auth.uid() in v5.4.0-00.';

COMMENT ON COLUMN public.customers.billing_hold_set_by IS
    'User who placed the hold. NULL when set by system (AI fraud detection, automated dispute workflow). Populated by the application from its authenticated user (app.user_id session context). Cleared automatically when hold is removed.';

COMMENT ON COLUMN public.meters.estimation_blocked_set_by IS
    'User who placed the block. Populated by the application from its authenticated user (app.user_id session context). NULL when set by system action (AI tamper detection, automated dispute workflow). Cleared when block is removed.';
