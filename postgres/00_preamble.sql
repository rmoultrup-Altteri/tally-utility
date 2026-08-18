-- Preamble applied before the schema SQL runs.
-- Disables function-body checking because pg_dump ordering places the
-- LANGUAGE sql functions (get_user_tenant_id, is_platform_admin) before
-- CREATE TABLE users, which they reference. Documented in the tu.sql header
-- (bug 1 of the seven known build-test bugs).
SET check_function_bodies = off;
