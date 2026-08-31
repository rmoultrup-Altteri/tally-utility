-- ============================================================================
-- PATCH v5.4.2-08 — A-7 follow-up: a ruled surcharge line stays on its
--                    invoice, an invoice stays under its rule, and a rule
--                    correction stays over its lines (closes the
--                    out-of-cycle re-parent residual and its siblings — the
--                    draft invoice_date walk, the cycle-shrinking
--                    correction, and the correction/line-write race — from
--                    the v5.4.2-07/-08 reviews; CI-038)
-- ============================================================================
-- Authority:   Fable final-pass residual on v5.4.2-07 (2026-08-31): with the
--              rider link frozen, re-parenting a capped line was still open —
--              `UPDATE invoice_line_items SET invoice_id` onto a draft whose
--              bill date lies OUTSIDE the assessment cycle finds no rule
--              (the guard is date-scoped), frees the (rate item, meter)
--              total in-cycle, and both invoices issue: two cap-sized PSF
--              lines for one meter, one of them on an out-of-cycle bill.
--              Ryan, 2026-08-31: land the close now (v5.4.2-02-style rider).
--              Both reviewers' round-1 reports on this rider then found the
--              SIBLING vector independently: the same outcome without
--              touching the line at all — a draft invoice's own
--              invoice_date is freely editable, so moving THE INVOICE out
--              of the cycle drops its ruled lines from the (rate item,
--              meter) total (the cap sum and the compliance view both key
--              on i.invoice_date), a fresh in-cycle bill passes, and the
--              walked invoice issues unchecked at its new date — 2.00 on a
--              1.00 cap AND regulatory_surcharge_billing_summary
--              under-reports the billed total by the walked half (Codex).
--
-- What lands — the same freeze, applied to both halves of the join:
--
--   1. enforce_surcharge_line() re-issued with ONE added refusal — a line
--      whose OLD rider has a rule for the OLD invoice's bill date cannot
--      change invoice_id at all, exactly as its rate_item_id already
--      cannot change (v5.4.2-07, Codex CRITICAL-1). The in-cycle re-parent
--      was already refused by the cap re-run at the NEW invoice; this
--      makes the refusal uniform and date-independent: moving a ruled
--      line is delete + new line, which re-runs every check at the
--      destination. Everything else in the function is byte-identical to
--      v5.4.2-07. The meter_id swap on a ruled line stays ALLOWED (stated
--      in -07's review record): it moves the attribution and the
--      per-meter cap holds at both meters.
--
--   2. enforce_invoice_date_rule_membership() — BEFORE UPDATE OF
--      invoice_date on invoices: for every distinct rider on the invoice
--      whose rule covers the OLD bill date, the NEW bill date must be
--      covered by the SAME rule row. Moving the date within the cycle
--      stays free (F3's legitimate path — a pre-cycle draft moved INTO a
--      cycle is unruled at its old date, so this guard is silent and the
--      issuance gate's full re-check governs, as before); moving a ruled
--      invoice out of its cycle, or into another cycle, is refused —
--      delete the ruled lines first. Issued invoices are already frozen
--      by A-4; this guard is about drafts. ENABLE ALWAYS.
--
--   3. enforce_regulatory_surcharge_rule() re-issued with the third half
--      of the same freeze (Codex, extended-08 round: a routine
--      cycle-shortening correction reproduced the identical 2.00-on-1.00
--      outcome — the orphaned line silently left the cap sum AND the
--      compliance view without anyone touching it): a successor rule
--      (supersedes_id set) whose cycle no longer covers the bill date of
--      an existing non-void line that the predecessor's cycle covered is
--      refused — void or delete those bills first, or keep the cycle over
--      them; and a rule cannot be closed as 'retracted' while any
--      non-void line's bill date lies in its cycle (retract-then-reassert
--      was the route around the successor check). A cap-only correction,
--      a cycle extension, and a shrink that still covers every line stay
--      free. Everything else in the function is byte-identical to
--      v5.4.2-07. Both refusal paths require READ COMMITTED (an
--      invalid_transaction_state refusal otherwise), and
--      assert_surcharge_line() is re-issued to hold the governing rule row
--      FOR SHARE for the rest of the line writer's transaction — Fable's
--      final round reproduced the race: with the checks unsynchronised, a
--      correction committing between a line's check and its commit
--      orphaned the in-flight line (invisible to the orphan check as a
--      READ COMMITTED phantom), dropping it from the cap sum AND the
--      compliance view — 2.00 on a 1.00 cap again. Now the close of the
--      rule row (an UPDATE) waits behind every in-flight line checked
--      against it, and its statement snapshots then see those lines; a
--      REPEATABLE READ line writer whose rule was concurrently closed
--      fails with a serialization error and retries (the same contract as
--      the per-meter cap mutex, AC-27).
--
--   Two contract notes, stated (both reviewers' final rounds): every rule
--   correction and retraction MUST run under READ COMMITTED — an
--   application that runs admin writes at a higher isolation level by
--   policy must special-case these two paths (the refusal is immediate
--   and explicit). And a line written for a rider in the gap before a
--   NEW rule commits is unchecked at INSERT time (no rule exists to hold
--   FOR SHARE) but cannot reach an issued invoice: the deferred issuance
--   gate re-validates every line on current knowledge and was verified
--   to catch a pre-rule line against the later rule's cap.
--
-- Idempotent:  yes (CREATE OR REPLACE FUNCTION; COMMENT overwrite; DROP
--              TRIGGER IF EXISTS + re-CREATE for the new invoices trigger;
--              the line trigger from v5.4.2-07 already fires on UPDATE OF
--              invoice_id and is already ENABLE ALWAYS — not re-created).
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.enforce_surcharge_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bad  record;
    v_inv  public.invoices%ROWTYPE;
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- A surcharge line keeps its rider link: nulling or swapping
        -- rate_item_id detached the line from every cap / exclusion check
        -- while it kept its description and amount (Codex CRITICAL-1). The
        -- OLD rider's rule for the bill date decides; a genuine
        -- reclassification is delete + new line.
        -- v5.4.2-08: the same freeze covers invoice_id — re-parenting the
        -- line onto an out-of-cycle draft freed the (rate item, meter)
        -- total in-cycle (Fable final-pass residual).
        IF (NEW.rate_item_id IS DISTINCT FROM OLD.rate_item_id OR NEW.invoice_id IS DISTINCT FROM OLD.invoice_id)
           AND OLD.rate_item_id IS NOT NULL THEN
            SELECT * INTO v_inv FROM public.invoices i WHERE i.id = OLD.invoice_id;
            IF FOUND THEN
                SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rule_as_of(OLD.rate_item_id, v_inv.invoice_date, now()) r;
                IF FOUND THEN
                    RAISE EXCEPTION USING
                        MESSAGE = format('line %s (%s) is a %s surcharge line (rule %s): its rate_item_id and invoice_id cannot be changed — delete the line and write a new one where it belongs (CI-038)', OLD.id, OLD.description, v_rule.surcharge_kind, v_rule.id),
                        ERRCODE = 'check_violation';
                END IF;
            END IF;
        END IF;
        -- A line with a base composition (on either side) stays on its invoice:
        -- re-parenting it would carry rows that describe another bill.
        IF NEW.invoice_id IS DISTINCT FROM OLD.invoice_id
           AND EXISTS (SELECT 1 FROM public.invoice_line_item_bases b WHERE b.line_item_id = OLD.id OR b.base_line_item_id = OLD.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('line %s (%s) has a base composition (invoice_line_item_bases) and cannot be moved to another invoice — delete the composition first (CI-045)', OLD.id, OLD.description),
                ERRCODE = 'check_violation';
        END IF;
        -- A cited line cannot shrink under, or flip the sign of, what a base already took from it.
        IF NEW.amount IS DISTINCT FROM OLD.amount THEN
            SELECT b.base_amount, cl.description INTO v_bad
              FROM public.invoice_line_item_bases b
              JOIN public.invoice_line_items cl ON cl.id = b.line_item_id
             WHERE b.base_line_item_id = OLD.id
               AND (sign(b.base_amount) <> sign(NEW.amount) OR abs(b.base_amount) > abs(NEW.amount))
             LIMIT 1;
            IF FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('line %s (%s) cannot change to %s: %s of it is already in the base of %s (invoice_line_item_bases) — adjust the composition first (CI-045)', OLD.id, OLD.description, NEW.amount, v_bad.base_amount, v_bad.description),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    PERFORM public.assert_surcharge_line(NEW, now());
    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. The check half: line writers hold their rule row FOR SHARE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_surcharge_line(p_line public.invoice_line_items, p_recorded_at timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv  public.invoices%ROWTYPE;
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
    v_sum  numeric;
BEGIN
    IF p_line.rate_item_id IS NULL THEN
        RETURN;
    END IF;
    SELECT * INTO v_inv FROM public.invoices i WHERE i.id = p_line.invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_items: invoice %s is not visible in this tenant', p_line.invoice_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_inv.tenant_id <> p_line.tenant_id THEN
        RAISE EXCEPTION USING MESSAGE = 'invoice_line_items: tenant_id must equal the invoice''s tenant', ERRCODE = 'check_violation';
    END IF;
    SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rule_as_of(p_line.rate_item_id, v_inv.invoice_date, p_recorded_at) r;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    -- v5.4.2-08 (Fable, correction/line race): hold the governing rule row
    -- FOR SHARE until this transaction ends. A concurrent correction or
    -- retraction must close this row (an UPDATE), so it WAITS for every
    -- in-flight line checked against the rule and then sees their committed
    -- lines in its orphan check (the correction path is required to run
    -- under READ COMMITTED). Under REPEATABLE READ / SERIALIZABLE a line
    -- writer whose rule was concurrently closed fails here with a
    -- serialization error instead of passing on a stale rule.
    PERFORM 1 FROM public.regulatory_surcharge_rules r WHERE r.id = v_rule.id AND r.recorded_until IS NULL FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('regulatory_surcharge_rules: rule %s was corrected or closed by a concurrent transaction — retry (CI-038)', v_rule.id),
            ERRCODE = 'serialization_failure';
    END IF;
    IF p_line.charge_type = 'tax' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: line %s is a %s surcharge rider (regulatory_surcharge_rules %s), not a tax — charge_type ''tax'' rejected (CI-038)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
            ERRCODE = 'check_violation';
    END IF;
    IF v_rule.excluded_from_tax_bases THEN
        IF p_line.is_taxable OR coalesce(p_line.taxable_amount, 0) <> 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge excluded from every tax base — is_taxable must be false and taxable_amount empty (CI-038 / 16 TAC §8.201; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.invoice_line_item_bases b WHERE b.base_line_item_id = p_line.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge excluded from every tax base but is cited as a base by another line (CI-038 / CI-045; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF v_rule.exempts_state_agencies AND p_line.amount <> 0 AND public.customer_is_state_agency_as_of(v_inv.customer_id, v_inv.period_end) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: the customer was a state agency at the end of the billed period (%s) and is exempt from the %s surcharge — line %s must be 0.00 (CI-038; rule %s)', v_inv.invoice_number, v_inv.period_end, v_rule.surcharge_kind, p_line.description, v_rule.id),
            ERRCODE = 'check_violation';
    END IF;
    IF v_rule.cap_per_service IS NOT NULL THEN
        IF p_line.meter_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge capped per service (%s over the cycle %s..%s) and must name its service — meter_id is required (CI-038; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.cap_per_service, v_rule.cycle_start, v_rule.cycle_end, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
        -- serialise concurrent lines for one (rider, service) on the mutex row (5.0)
        INSERT INTO public.regulatory_surcharge_service_locks (tenant_id, rate_item_id, meter_id)
        VALUES (p_line.tenant_id, p_line.rate_item_id, p_line.meter_id)
        ON CONFLICT (rate_item_id, meter_id) DO UPDATE SET touched_at = clock_timestamp();
        -- Only POSITIVE amounts count toward the cap: a negative line (a
        -- correction) never lends headroom, because the invoice carrying it
        -- can be discarded or voided later (Fable HIGH-1). The path to bill
        -- again is void + rebill, which releases the voided amount.
        SELECT coalesce(sum(greatest(l.amount, 0)), 0) INTO v_sum
          FROM public.invoice_line_items l
          JOIN public.invoices i ON i.id = l.invoice_id
         WHERE l.tenant_id = p_line.tenant_id
           AND l.rate_item_id = p_line.rate_item_id
           AND l.meter_id = p_line.meter_id
           AND l.id <> p_line.id
           AND i.status <> 'void'
           AND i.invoice_date >= v_rule.cycle_start AND i.invoice_date <= v_rule.cycle_end;
        IF v_sum + p_line.amount > v_rule.cap_per_service THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s would bring the %s surcharge on this service to %s for the cycle %s..%s (%s already billed on non-void invoices and drafts, positive lines only, + %s), over the cap of %s per service (CI-038 / 16 TAC §8.201; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_sum + p_line.amount, v_rule.cycle_start, v_rule.cycle_end, v_sum, p_line.amount, v_rule.cap_per_service, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. The rule half: a correction cannot shrink the cycle out from under
--    existing lines; a rule with lines cannot be retracted — and it runs
--    under READ COMMITTED, behind the line writers' FOR SHARE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_regulatory_surcharge_rule() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_taxable_versions  integer;
    v_taxable_overrides integer;
    v_non_gas           integer;
    v_lines             integer;
    v_code              text;
BEGIN
    PERFORM public.assert_same_tenant_user(NEW.changed_by, NEW.tenant_id, 'regulatory_surcharge_rules.changed_by');
    PERFORM public.assert_same_tenant_user(NEW.closed_by, NEW.tenant_id, 'regulatory_surcharge_rules.closed_by');
    IF TG_OP = 'UPDATE' THEN
        -- v5.4.2-08: a rule with billed / drafted lines in its cycle cannot be
        -- retracted — "the fact never existed" cannot be declared over bills
        -- that were checked against it (and retract-then-reassert would route
        -- around the successor-shrink check below).
        IF NEW.closed_type = 'retracted' AND OLD.closed_type IS NULL THEN
            IF current_setting('transaction_isolation') <> 'read committed' THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'regulatory_surcharge_rules: retract under READ COMMITTED — the line check needs statement snapshots to see the in-flight lines this close just waited for (CI-038)',
                    ERRCODE = 'invalid_transaction_state';
            END IF;
            SELECT count(*) INTO v_lines
              FROM public.invoice_line_items l
              JOIN public.invoices i ON i.id = l.invoice_id
             WHERE l.rate_item_id = OLD.rate_item_id AND i.status <> 'void'
               AND i.invoice_date >= OLD.cycle_start AND i.invoice_date <= OLD.cycle_end;
            IF v_lines > 0 THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('regulatory_surcharge_rules: rule %s has %s non-void line(s) billed in its cycle %s..%s and cannot be retracted — correct it (close as superseded with a successor) or void those bills first (CI-038)', OLD.id, v_lines, OLD.cycle_start, OLD.cycle_end),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        RETURN NEW;      -- content is frozen by the bi-temporal guard; only the close and notes/metadata get here
    END IF;
    -- v5.4.2-08: a successor's cycle cannot be shrunk out from under existing
    -- lines — the orphaned line would silently leave the cap sum and the
    -- compliance view, freeing the meter to be billed to the cap again
    -- (Codex, the rule-correction route to the same 2x-cap outcome).
    IF NEW.supersedes_id IS NOT NULL THEN
        -- The predecessor's close (this same transaction) waited on every
        -- in-flight line writer's FOR SHARE; under READ COMMITTED this
        -- statement's snapshot therefore sees their lines. Any other
        -- isolation level would re-open the race (Fable) — refused.
        IF current_setting('transaction_isolation') <> 'read committed' THEN
            RAISE EXCEPTION USING
                MESSAGE = 'regulatory_surcharge_rules: run corrections under READ COMMITTED — the orphan check needs statement snapshots to see the in-flight lines the predecessor''s close just waited for (CI-038)',
                ERRCODE = 'invalid_transaction_state';
        END IF;
        SELECT count(*) INTO v_lines
          FROM public.regulatory_surcharge_rules pred
          JOIN public.invoice_line_items l ON l.rate_item_id = pred.rate_item_id
          JOIN public.invoices i ON i.id = l.invoice_id
         WHERE pred.id = NEW.supersedes_id AND i.status <> 'void'
           AND i.invoice_date >= pred.cycle_start AND i.invoice_date <= pred.cycle_end
           AND (i.invoice_date < NEW.cycle_start OR i.invoice_date > NEW.cycle_end);
        IF v_lines > 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('regulatory_surcharge_rules: the successor cycle %s..%s leaves %s non-void line(s) of this rider outside it that the predecessor''s cycle covered — a correction cannot shrink the cycle out from under billed lines; void or delete those bills first, or keep the cycle over them (CI-038)', NEW.cycle_start, NEW.cycle_end, v_lines),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    SELECT ri.item_code INTO v_code FROM public.rate_items ri WHERE ri.id = NEW.rate_item_id AND ri.tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('regulatory_surcharge_rules: rate item %s is not visible in tenant %s', NEW.rate_item_id, NEW.tenant_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF NEW.excluded_from_tax_bases THEN
        SELECT count(*) INTO v_taxable_versions
          FROM public.rate_item_versions v
         WHERE v.rate_item_id = NEW.rate_item_id AND v.recorded_until IS NULL AND (v.is_taxable_default OR v.is_a_tax);
        SELECT count(*) INTO v_taxable_overrides
          FROM public.rate_schedule_items s
         WHERE s.rate_item_id = NEW.rate_item_id AND s.recorded_until IS NULL AND s.is_taxable_override = true;
        IF v_taxable_versions > 0 OR v_taxable_overrides > 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('regulatory_surcharge_rules: rider %s cannot be excluded from tax bases while %s open version(s) are taxable / a tax and %s open schedule override(s) say taxable — correct those assertions first (CI-038 / CI-045)', v_code, v_taxable_versions, v_taxable_overrides),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF NEW.surcharge_kind = 'pipeline_safety_fee' THEN
        SELECT count(*) INTO v_non_gas
          FROM public.rate_item_versions v
         WHERE v.rate_item_id = NEW.rate_item_id AND v.recorded_until IS NULL AND v.service_type NOT IN ('gas', 'all');
        IF v_non_gas > 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('regulatory_surcharge_rules: the Pipeline Safety Fee is a gas-distribution assessment (16 TAC §8.201) but rider %s has %s open version(s) of another service type', v_code, v_non_gas),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_regulatory_surcharge_rule() IS
    'v5.4.2-07, re-issued v5.4.2-08 (A-7 follow-up): BEFORE INSERT/UPDATE on regulatory_surcharge_rules. Actors must belong to the tenant; on INSERT the rider must be visible in the tenant, an excluded rider may have no open taxable version / override, a pipeline_safety_fee rider is gas or all-service, and (-08) a successor''s cycle must still cover the bill date of every non-void line the predecessor''s cycle covered — a shrink that orphans lines is refused (the orphan would leave the cap sum and the compliance view, freeing the meter to be re-billed to the cap). On UPDATE (-08) a rule cannot be closed as ''retracted'' while any non-void line''s bill date lies in its cycle. Runs after a_enforce_bitemporal_assertion (name order).';

-- ----------------------------------------------------------------------------
-- 4. The invoice half: invoice_date cannot walk a ruled line out of its cycle
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_invoice_date_rule_membership() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    r          record;
    v_old_rule public.regulatory_surcharge_rules%ROWTYPE;
    v_new_id   uuid;
BEGIN
    IF NEW.invoice_date IS NOT DISTINCT FROM OLD.invoice_date THEN
        RETURN NEW;
    END IF;
    FOR r IN
        SELECT l.rate_item_id, min(l.description) AS description
          FROM public.invoice_line_items l
         WHERE l.invoice_id = NEW.id AND l.rate_item_id IS NOT NULL
         GROUP BY l.rate_item_id
    LOOP
        SELECT ru.* INTO v_old_rule FROM public.regulatory_surcharge_rule_as_of(r.rate_item_id, OLD.invoice_date, now()) ru;
        IF FOUND THEN
            SELECT ru.id INTO v_new_id FROM public.regulatory_surcharge_rule_as_of(r.rate_item_id, NEW.invoice_date, now()) ru;
            IF v_new_id IS DISTINCT FROM v_old_rule.id THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('invoice %s carries a %s surcharge line (%s, rule %s, cycle %s..%s): its bill date cannot leave that rule''s cycle (%s -> %s would drop the line from the per-service total and the compliance report) — delete the ruled line(s) first, or keep the date in the cycle (CI-038)', NEW.invoice_number, v_old_rule.surcharge_kind, r.description, v_old_rule.id, v_old_rule.cycle_start, v_old_rule.cycle_end, OLD.invoice_date, NEW.invoice_date),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_invoice_date_rule_membership() IS
    'v5.4.2-08 (A-7 follow-up, CI-038): BEFORE UPDATE OF invoice_date on invoices — for every rider on the invoice whose rule covers the OLD bill date, the NEW bill date must be covered by the SAME rule row. Closes the sibling of the re-parent vector (both -08 reviewers, independently): re-dating a draft walked its ruled lines out of the cap sum and out of regulatory_surcharge_billing_summary. A date move within the cycle is free; an unruled invoice is untouched; issued invoices are frozen by A-4 anyway.';

DROP TRIGGER IF EXISTS b_enforce_invoice_date_rule_membership ON public.invoices;
CREATE TRIGGER b_enforce_invoice_date_rule_membership BEFORE UPDATE OF invoice_date ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_date_rule_membership();

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'b_enforce_invoice_date_rule_membership' AND tgrelid = 'public.invoices'::regclass AND tgenabled <> 'A') THEN
        ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER b_enforce_invoice_date_rule_membership;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.enforce_surcharge_line() IS 'v5.4.2-07, re-issued v5.4.2-08: BEFORE INSERT / UPDATE on invoice_line_items — a ruled surcharge line''s rate_item_id AND invoice_id are frozen (the OLD rider''s rule for the OLD invoice''s bill date decides; -08 closed the out-of-cycle re-parent that freed the per-meter cap); a draft line that has a base composition (either side) cannot be moved to another invoice, and a cited line cannot change amount under what a base took from it; then assert_surcharge_line(NEW, now()).';
