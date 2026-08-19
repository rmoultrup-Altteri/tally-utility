-- ============================================================================
-- PATCH v5.4.0-05 — Pipeline & events set (v5.4 backlog items 11, 12, 13)
-- ============================================================================
-- Authority:   Kyle rulings 2026-07-10 (gas-billing-memory/application/
--              wu5-wu6-kyle-decisions-2026-07-10.md):
--                item 11  dry-run consolidation + DB guards + comment
--                         (D3C-6 / Part 4 inspection findings)
--                item 12  reversal-chain depth event at >3        (D1-3)
--                item 13  Fp swap validation + activation
--                         confirmation fields                     (D3B-1/2)
--              Fourth Phase 1 migration set per the parity plan.
-- Drafting decisions (delegated by the rulings to patch time):
--              * 11a: Kyle's primary option taken — 'dry_run' DROPPED from
--                the run_type enum (run type = what kind of run; dry-ness
--                is orthogonal). Safe: the value's only reference was the
--                CHECK itself, and no data exists anywhere.
--              * 11b extension: is_dry_run is made IMMUTABLE (same trigger).
--                Not explicitly ruled, but flipping is_dry_run=false after
--                the fact would launder a dry run into a real one, and the
--                CI-119 discipline already says a re-run is a NEW billing-
--                run row. Blocking status approved/posted alone leaves that
--                hole open.
--              * 12: D1-3 allowed "app-layer + event type only"; drafted as
--                a DB trigger instead — the same belt-and-braces philosophy
--                as 11b (the engine should emit it, the database makes sure
--                it exists). NO blocking: the trigger only inserts an
--                invoice_events row ('reversal_chain_depth_exceeded',
--                metadata {depth, severity: medium} for the Medium
--                portlet). Depth = ancestor count via replaces_invoice_id;
--                the legitimate 3-deep chain (bill → void → rebill →
--                void-the-rebill) stays silent; the event fires at >3.
--                Walk is capped at 50 links (cycle guards on lineage
--                columns are Phase 2.3, not this patch).
--              * 13 split (app vs. column), resolved as: the COLUMNS land —
--                meters.zone_confirmed_at/by + pressure_class_confirmed_at/
--                by (the D3B-2 activation gate's affirmation record; one
--                checkpoint with D3B-1) and meter_deployments.
--                fp_mismatch_confirmed_at/by/reason (D3B-1's explicit
--                operator confirmation with reason). The VALIDATION —
--                comparing post-pressure-test Fp against the service
--                point's last-known Fp, and refusing activation on
--                unaffirmed attributes — is application logic
--                (requires-application-discipline; the columns are its
--                recording substrate). Pair CHECKs keep half-filled
--                confirmations out.
-- Idempotent:  yes (ADD COLUMN IF NOT EXISTS; CREATE OR REPLACE FUNCTION;
--              constraints/triggers DROP IF EXISTS + re-ADD; COMMENT
--              overwrite).
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
-- ============================================================================

--
-- Item 11a — one source of truth for dry-ness: the boolean. 'dry_run'
-- leaves the run_type enum (Part 4 finding 3: run_type='dry_run',
-- is_dry_run=false was a legal row — the split-brain closes).
--
ALTER TABLE public.billing_runs DROP CONSTRAINT IF EXISTS billing_runs_run_type_check;
ALTER TABLE public.billing_runs ADD CONSTRAINT billing_runs_run_type_check
    CHECK ((run_type = ANY (ARRAY['regular'::text, 'off_cycle'::text, 'correction'::text, 'final'::text])));

COMMENT ON COLUMN public.billing_runs.run_type IS
    'regular=normal cycle run, off_cycle=out-of-sequence, correction=rebill, final=service-ending bill. dry_run removed from this enum in v5.4.0-05 (D3C-6): dry-ness is orthogonal to run type and lives only in is_dry_run — any run type can be previewed dry.';

--
-- Item 11c — documentation parity with import_jobs.is_dry_run (Part 4
-- finding 1), now backed by the guards below (finding 2).
--
COMMENT ON COLUMN public.billing_runs.is_dry_run IS
    'When true, the run evaluates and its per-meter outcomes populate but nothing commits: the database itself rejects invoice inserts, ledger writes, and read locks referencing this run, and blocks the approved/posted transitions (v5.4.0-05 guards, D3C-6). Lets operators preview impact before pulling the trigger. Immutable after creation — a real run is a NEW run row, never a flipped dry one.';

--
-- Item 11b — belt-and-braces guards: the engine shouldn't, the database
-- won't let it.
--
CREATE OR REPLACE FUNCTION public.enforce_dry_run_no_invoices() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.billing_run_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.billing_runs r WHERE r.id = NEW.billing_run_id AND r.is_dry_run) THEN
        RAISE EXCEPTION 'billing run % is a dry run (is_dry_run=true); invoices may not reference it (D3C-6 guard)', NEW.billing_run_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dry_run_no_invoices ON public.invoices;
CREATE TRIGGER dry_run_no_invoices BEFORE INSERT OR UPDATE OF billing_run_id ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.enforce_dry_run_no_invoices();

CREATE OR REPLACE FUNCTION public.enforce_dry_run_no_ledger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.reference_type = 'billing_run'
       AND NEW.reference_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.billing_runs r WHERE r.id = NEW.reference_id AND r.is_dry_run) THEN
        RAISE EXCEPTION 'billing run % is a dry run (is_dry_run=true); ledger entries may not reference it (D3C-6 guard)', NEW.reference_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dry_run_no_ledger ON public.account_ledger;
CREATE TRIGGER dry_run_no_ledger BEFORE INSERT ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION public.enforce_dry_run_no_ledger();

CREATE OR REPLACE FUNCTION public.enforce_dry_run_no_read_locks() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.locked_by_billing_run_id IS NOT NULL
       AND NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id
       AND EXISTS (SELECT 1 FROM public.billing_runs r WHERE r.id = NEW.locked_by_billing_run_id AND r.is_dry_run) THEN
        RAISE EXCEPTION 'billing run % is a dry run (is_dry_run=true); it may not lock readings (D3C-6 guard)', NEW.locked_by_billing_run_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dry_run_no_read_locks ON public.meter_readings;
CREATE TRIGGER dry_run_no_read_locks BEFORE UPDATE ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION public.enforce_dry_run_no_read_locks();

CREATE OR REPLACE FUNCTION public.enforce_dry_run_terminal_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.is_dry_run IS DISTINCT FROM OLD.is_dry_run THEN
        RAISE EXCEPTION 'billing_runs.is_dry_run is immutable (run %); a real run is a new run row, never a flipped dry one (D3C-6 guard)', OLD.id;
    END IF;
    IF NEW.is_dry_run AND NEW.status = ANY (ARRAY['approved'::text, 'posted'::text]) THEN
        RAISE EXCEPTION 'dry run % may not transition to status % (D3C-6 guard); dry runs end at review', OLD.id, NEW.status;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dry_run_terminal_status ON public.billing_runs;
CREATE TRIGGER dry_run_terminal_status BEFORE UPDATE ON public.billing_runs FOR EACH ROW EXECUTE FUNCTION public.enforce_dry_run_terminal_status();

--
-- Item 12 — reversal-chain depth event (D1-3). Monitoring only, never
-- blocking: legitimate 3-deep chains exist; >3 posts an elevated-severity
-- event for the Medium portlet.
--
ALTER TABLE public.invoice_events DROP CONSTRAINT IF EXISTS invoice_events_event_type_check;
ALTER TABLE public.invoice_events ADD CONSTRAINT invoice_events_event_type_check
    CHECK ((event_type = ANY (ARRAY['created'::text, 'sent'::text, 'held'::text, 'released_from_hold'::text, 'voided'::text, 'void_attempted_blocked'::text, 'correction_initiated'::text, 'correction_posted'::text, 'payment_applied'::text, 'written_off'::text, 'status_changed'::text, 'reversal_chain_depth_exceeded'::text])));

CREATE OR REPLACE FUNCTION public.check_reversal_chain_depth() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_depth integer := 0;
    v_cursor uuid := NEW.replaces_invoice_id;
BEGIN
    WHILE v_cursor IS NOT NULL AND v_depth < 50 LOOP
        v_depth := v_depth + 1;
        SELECT replaces_invoice_id INTO v_cursor FROM public.invoices WHERE id = v_cursor;
    END LOOP;
    IF v_depth > 3 THEN
        INSERT INTO public.invoice_events (tenant_id, invoice_id, event_type, metadata)
        VALUES (NEW.tenant_id, NEW.id, 'reversal_chain_depth_exceeded',
                jsonb_build_object('depth', v_depth, 'severity', 'medium', 'ruling', 'D1-3'));
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reversal_chain_depth ON public.invoices;
CREATE TRIGGER reversal_chain_depth AFTER INSERT OR UPDATE OF replaces_invoice_id ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.check_reversal_chain_depth();

--
-- Item 13 — the D3B-2 activation-gate affirmation record on meters, and
-- the D3B-1 Fp-mismatch confirmation record on meter_deployments. The
-- comparison/gating logic is application discipline; these columns are
-- where its outcomes must be recorded.
--
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS zone_confirmed_at timestamp with time zone;
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS zone_confirmed_by uuid;
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS pressure_class_confirmed_at timestamp with time zone;
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS pressure_class_confirmed_by uuid;

ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_zone_confirmed_by_fkey;
ALTER TABLE public.meters ADD CONSTRAINT meters_zone_confirmed_by_fkey
    FOREIGN KEY (zone_confirmed_by) REFERENCES public.users(id);
ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_pressure_class_confirmed_by_fkey;
ALTER TABLE public.meters ADD CONSTRAINT meters_pressure_class_confirmed_by_fkey
    FOREIGN KEY (pressure_class_confirmed_by) REFERENCES public.users(id);

ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_zone_confirmation_pair_check;
ALTER TABLE public.meters ADD CONSTRAINT meters_zone_confirmation_pair_check
    CHECK (((zone_confirmed_at IS NULL) AND (zone_confirmed_by IS NULL)) OR ((zone_confirmed_at IS NOT NULL) AND (zone_confirmed_by IS NOT NULL)));
ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_pressure_class_confirmation_pair_check;
ALTER TABLE public.meters ADD CONSTRAINT meters_pressure_class_confirmation_pair_check
    CHECK (((pressure_class_confirmed_at IS NULL) AND (pressure_class_confirmed_by IS NULL)) OR ((pressure_class_confirmed_at IS NOT NULL) AND (pressure_class_confirmed_by IS NOT NULL)));

COMMENT ON COLUMN public.meters.zone_confirmed_at IS
    'D3B-2 activation QA gate (v5.4.0-05): when the meter''s zone assignment was affirmed by a person. Measurement-critical attributes are affirmed, never defaulted — the activation gate (application logic) must refuse to make the meter billable while this is NULL. Pairs with zone_confirmed_by (CHECK-enforced).';

COMMENT ON COLUMN public.meters.pressure_class_confirmed_at IS
    'D3B-2 activation QA gate (v5.4.0-05): when meter_pressure_class was affirmed — the pressure-test result is what affirms it (D3B-1 and D3B-2 share one checkpoint). The activation gate (application logic) must refuse activation while NULL. Pairs with pressure_class_confirmed_by (CHECK-enforced).';

ALTER TABLE public.meter_deployments ADD COLUMN IF NOT EXISTS fp_mismatch_confirmed_at timestamp with time zone;
ALTER TABLE public.meter_deployments ADD COLUMN IF NOT EXISTS fp_mismatch_confirmed_by uuid;
ALTER TABLE public.meter_deployments ADD COLUMN IF NOT EXISTS fp_mismatch_reason text;

ALTER TABLE public.meter_deployments DROP CONSTRAINT IF EXISTS meter_deployments_fp_mismatch_confirmed_by_fkey;
ALTER TABLE public.meter_deployments ADD CONSTRAINT meter_deployments_fp_mismatch_confirmed_by_fkey
    FOREIGN KEY (fp_mismatch_confirmed_by) REFERENCES public.users(id);

ALTER TABLE public.meter_deployments DROP CONSTRAINT IF EXISTS meter_deployments_fp_mismatch_confirmation_check;
ALTER TABLE public.meter_deployments ADD CONSTRAINT meter_deployments_fp_mismatch_confirmation_check
    CHECK (((fp_mismatch_confirmed_at IS NULL) AND (fp_mismatch_confirmed_by IS NULL) AND (fp_mismatch_reason IS NULL))
        OR ((fp_mismatch_confirmed_at IS NOT NULL) AND (fp_mismatch_confirmed_by IS NOT NULL) AND (fp_mismatch_reason IS NOT NULL)));

COMMENT ON COLUMN public.meter_deployments.fp_mismatch_confirmed_at IS
    'D3B-1 (v5.4.0-05): a meter swap whose post-pressure-test Fp mismatches the service point''s last-known Fp requires explicit operator confirmation before the swap commits / the meter goes billable. The comparison fires AFTER the pressure test (application logic); this records the confirmation. All three fp_mismatch_* fields set together or not at all (CHECK-enforced) — a confirmation without a reason is not a confirmation.';
