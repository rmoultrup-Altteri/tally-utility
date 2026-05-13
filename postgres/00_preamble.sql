-- Preamble applied before the schema SQL runs.
-- Disables function-body checking so forward-references in tu.sql
-- (LANGUAGE sql functions that reference auth.users before it exists)
-- do not abort the init sequence. Documented in the tu.sql header.
SET check_function_bodies = off;
