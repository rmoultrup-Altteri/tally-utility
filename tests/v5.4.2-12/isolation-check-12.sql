-- ============================================================================
-- v5.4.2-12 — a cutover_date change is refused outside READ COMMITTED
-- (review round 2, Opus). Cannot live in battery-12, which is one READ
-- COMMITTED transaction. Run: psql -U tally -d <db-with-patch>
--   -v ON_ERROR_STOP=1 -f isolation-check-12.sql
-- Each block rolls back.
-- ============================================================================

BEGIN ISOLATION LEVEL REPEATABLE READ;
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-0000000012f0', 'ISO', 'iso12');
DO $$ BEGIN
  UPDATE public.tenants SET cutover_date = DATE '2026-01-01' WHERE id = '00000000-0000-4000-8000-0000000012f0';
  RAISE EXCEPTION 'ISO1 FAILED';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'PASS ISO1: a cutover change under REPEATABLE READ is refused — its snapshot could miss a committed test';
END $$;
ROLLBACK;

BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $$ BEGIN
  INSERT INTO public.tenants (id, name, slug, cutover_date) VALUES ('00000000-0000-4000-8000-0000000012f1', 'ISO2', 'iso12b', DATE '2026-01-01');
  RAISE EXCEPTION 'ISO2 FAILED';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'PASS ISO2: creating a tenant with a cutover under SERIALIZABLE is refused too';
END $$;
ROLLBACK;

BEGIN;  -- READ COMMITTED
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-0000000012f0', 'ISO', 'iso12');
UPDATE public.tenants SET cutover_date = DATE '2026-01-01' WHERE id = '00000000-0000-4000-8000-0000000012f0';
DO $$ BEGIN
  IF (SELECT cutover_date FROM public.tenants WHERE id = '00000000-0000-4000-8000-0000000012f0') <> DATE '2026-01-01' THEN
    RAISE EXCEPTION 'ISO3 FAILED'; END IF;
  RAISE NOTICE 'PASS ISO3: the same change under READ COMMITTED is accepted';
END $$;
ROLLBACK;
