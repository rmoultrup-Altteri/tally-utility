-- ============================================================================
-- PATCH v5.4.2-09 — A-9: tax exemption certificate evidence and renewal
--                    surfacing (schema-parity-plan Phase 4 Wave 3,
--                    Appendix A-9; CI-046)
-- ============================================================================
-- Authority:   canonical-invariants.md CI-046 (Tax Exemption Certificate
--              Lifecycle and Period Validity) and Appendix A-9; the v5.2.1
--              gap analysis Family 6 entry for CI-046 ("A-9 scope shrinks
--              significantly — add renewal-prompt surfacing, the renewal-
--              notice config, and the certificate-required-vs-flag-only
--              designation per category"); Kyle rulings R-12 and R-13
--              (kyle-decisions-2026-08-26-a1-bitemporal.md): exemptions
--              lock at active with a verification signature (Comptroller
--              Rule 3.287 puts certificate liability on the seller), and
--              customer_tax_exemptions holds CERTIFICATE-BACKED exemptions
--              only; knowledge/11-taxes-and-gl-accounting.md "Certificates
--              expire — typically 1-5 years. System must track and prompt
--              renewal before expiry".
--
-- What A-1 already closed, so this patch does not re-land it. v5.4.2-03
-- rebuilt customer_tax_exemptions in place: bi-temporal assertions
-- (recorded_at / recorded_until, enforce_bitemporal_assertion,
-- enforce_superseded_has_successor, open-rows-only EXCLUDE per (customer,
-- exemption_type) on the valid bracket), the R-12 verification lock
-- (born pending_verification; active requires verified_by AND verified_at;
-- in-place status flips on asserted rows refused — expiry / revocation are
-- successor rows), the R-13 enum narrowing ('industrial' out), and the
-- coordinate-pair reads (customer_tax_exemption_as_of / should_charge_tax,
-- both coordinates required, NULL raises). The v5.2.1 gap analysis predates
-- all of that; what CI-046 still lacked when this patch was drafted is
-- exactly three things:
--
--   1. tax_exemption_certificate_required(tenant, exemption_type) — the
--      certificate-required-vs-flag-only designation per category (CI-046's
--      configurable boundary), read from tenants.settings the way A-20's
--      max_consecutive_estimates is: tenants.settings ->
--      {tax_exemptions, certificate_required, <exemption_type>}, DEFAULT
--      TRUE for every category. The default direction is not a choice this
--      patch invents: R-13 ruled the table holds certificate-backed
--      exemptions only, and under Comptroller Rule 3.287 an exemption the
--      seller cannot evidence at audit is the seller's tax plus penalty.
--      A tenant in a jurisdiction where a category is exempt by status
--      (no certificate issued — e.g. a jurisdiction that exempts
--      government entities by law) flips that category to flag-only in
--      settings; the flip is per category, never per row.
--
--   2. The certificate-evidence gate, folded into the existing lifecycle
--      trigger (enforce_tax_exemption_lifecycle is redefined; same trigger,
--      same firing): a row may ENTER an asserted state (active, or an
--      expired / revoked successor) only if its category is flag-only for
--      its tenant OR it carries documentary evidence — a non-blank
--      certificate_number OR a non-blank certificate_url — non-blank
--      meaning at least one alphanumeric character (a Comptroller
--      exemption letter has an artifact but not necessarily a number, so
--      either suffices; requiring the number alone would refuse letter-
--      backed exemptions R-13 explicitly includes). Drafts stay freely
--      editable — the gate sits where R-12 put the verification lock, at
--      the entry to assertion, and asserted rows are already frozen by the
--      bi-temporal guard. Successor rows (expired / revoked) carry the
--      same requirement: they assert the ending of a certificate and must
--      document WHICH certificate ended.
--
--      Self-verifying precondition (the R-13 / R-4 pattern — refuse and
--      report, never audit first): the patch refuses to apply while any
--      CURRENT assertion head (recorded_until IS NULL, status active OR
--      expired OR revoked) lacks evidence its tenant's config requires.
--      All three statuses, because customer_tax_exemption_as_of does not
--      filter on status — a current expired / revoked head still
--      suppresses tax for the dates its bracket covers on any rebill of
--      those periods, and unlike a draft it can never be fixed in place
--      (review finding, round 1). Closed (superseded / retracted) history
--      is reported by NOTICE count only — as_of never returns it at
--      current knowledge, and cleanup of history is not this patch's
--      business. Evidence here and in the gate means "contains at least
--      one alphanumeric character" — a btrim-blank check let a single tab
--      or NBSP pass as evidence (review finding, round 1).
--
--   3. Renewal surfacing: tax_exemption_renewal_notice_days(tenant)
--      (tenants.settings -> {tax_exemptions, renewal_notice_days_before},
--      DEFAULT 60 — the figure the legacy customer_summary /
--      compliance_statistics columns hard-code — must be >= 1) and
--      customer_tax_exemptions_renewal_due (security_invoker): every
--      CURRENT active assertion with an effective_end inside the tenant's
--      notice window or already past. A renewal on file (a later-bracketed
--      open active assertion for the same (customer, exemption_type))
--      quiets a row still inside its bracket; a LAPSED row stays listed
--      even with a renewal on file — it still owes its valid-time expiry
--      succession (review finding, round 1). renewal_state = 'lapsed' when
--      effective_end has passed — the certificate stops exempting AFTER
--      effective_end (the bracket is inclusive of the end date) and the
--      expiry successor has not been written; 'renewal_due' otherwise.
--      This is CI-046's "system surfaces
--      upcoming expirations to operations", sourced from the exemptions
--      table — NOT from the legacy customers.tax_exemption_* columns.
--
-- What this patch deliberately does NOT land, and why:
--
--   * No stored renewal_due_at and no renewal_notice_sent_at on the
--     exemption row. Both are later facts about a frozen assertion — the
--     exact shape D4-1's remitted_on rejection named on A-7 (a bi-temporal
--     row asserts what was known when it was asserted; a mutable timestamp
--     on it is a hole in the freeze). renewal_due_at is derivable
--     (effective_end and the tenant window — the view derives it);
--     notice-sent tracking belongs to the communication-log work CI-046's
--     scope note already assigns it to.
--
--   * No guard on the legacy customers.is_tax_exempt /
--     tax_exemption_* columns. They are a manually-maintained display
--     path (customer_summary, compliance_statistics) that the tax engine
--     never reads — should_charge_tax reads only the exemptions table.
--     The divergence (a flag flipped with no certificate row, or real
--     exemptions the flag ignores) is real but its fix is a DB-written
--     projection in the A-21 deposit_* style, which rebuilds
--     compliance_statistics — out of A-9's named scope. RECORDED RESIDUAL:
--     see the register note under CI-046.
--
--   * No per-category validity period ("typically 1-5 years") and no
--     per-category notice window. The certificate's own effective_end IS
--     the validity period (set per row from the document); a per-category
--     default-length knob invents a figure no rule states (the R-21 /
--     water-rule lesson: never seed a number nobody can cite).
--
-- Contracts (APPLICATION-CONTRACTS AC-30):
--   * Verifying an exemption into active (or writing an expired / revoked
--     successor) requires certificate evidence — certificate_number or
--     certificate_url containing AT LEAST ONE ALPHANUMERIC character (a
--     blank-only or punctuation-only value is not evidence; btrim-blankness
--     was rejected in review: a tab or NBSP passed it) — unless the tenant
--     flipped that category to flag-only. The refusal is check_violation
--     23514.
--   * The flag-only flip is consulted at ENTRY to assertion only and never
--     re-judges asserted rows; flips are audited by v5.4.1-02's
--     tenant_configuration_history. The knob is an omission barrier, not a
--     fraud barrier — an admin who can flip it can equally type a fake
--     certificate number.
--   * tenants.settings -> tax_exemptions must be an object when present,
--     and tax_exemptions.certificate_required an object of per-category
--     JSON true / false when present ("true"/"false" strings accepted); a
--     wrong-shape node AT EITHER LEVEL or any other value raises at
--     evaluation time — in both accessors — refusing the read that
--     consulted it rather than guessing a direction.
--   * The renewal queue admits a row ON the day exactly
--     renewal_notice_days_before days remain (<=, not <): "notify N days
--     before expiry" means the first notice day has N days remaining.
--   * tenants.settings -> tax_exemptions.renewal_notice_days_before must
--     be a positive integer of at most nine digits when present; the view
--     raises for that tenant's rows until corrected (loud, like
--     max_consecutive_estimates).
--   * customer_tax_exemptions_renewal_due is the renewal work queue:
--     'lapsed' rows are certificates that no longer exempt (write the
--     valid-time expiry successor or obtain a renewal); 'renewal_due' rows
--     want a renewal entered as a NEW row (succession), never an
--     effective_end edit (the bracket is frozen with the assertion).
--
-- Apply AFTER v5.4.2-08. Idempotent (CREATE OR REPLACE / DROP IF EXISTS).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Precondition — self-verifying, the R-13 pattern: refuse while a CURRENT
--    active assertion lacks the evidence its tenant's config requires.
--    (Runs BEFORE the trigger redefinition so a failing deploy changes
--    nothing. Uses the same settings read the accessor below formalizes.)
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    n bigint;
    m bigint;
BEGIN
    -- The evidence test — HERE and in the lifecycle gate below — is "contains
    -- at least one alphanumeric character", NOT a btrim-blank check: btrim()
    -- strips ASCII space only, so a tab, newline or NBSP would pass a blank
    -- check as "evidence" (Codex CRITICAL, round 1). Keep the two expressions
    -- identical or the precondition and the gate drift.
    --
    -- CURRENT heads of every asserted status block, not just active:
    -- customer_tax_exemption_as_of does not filter on status — a current
    -- (unsuperseded) expired/revoked row still suppresses tax for the dates
    -- its bracket covers on any rebill of those periods, so an evidence-less
    -- one is the same live audit liability, and unlike a draft it can never
    -- be fixed in place (Codex HIGH, round 1). Closed history (recorded_until
    -- set) is NOTICE-only.
    SELECT count(*) INTO n
      FROM public.customer_tax_exemptions e
      JOIN public.tenants t ON t.id = e.tenant_id
     WHERE e.status IN ('active', 'expired', 'revoked')
       AND e.recorded_at IS NOT NULL
       AND e.recorded_until IS NULL
       AND NOT (   coalesce(e.certificate_number ~ '[[:alnum:]]', false)
                OR coalesce(e.certificate_url    ~ '[[:alnum:]]', false))
       AND lower(coalesce(t.settings #>> ARRAY['tax_exemptions','certificate_required', e.exemption_type], 'true')) <> 'false';
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-09 refused: % current customer_tax_exemptions assertion(s) (active, or an unsuperseded expired/revoked head — those still suppress tax for the dates they cover on a rebill) carry no certificate evidence while their category requires it (CI-046 / Comptroller Rule 3.287 — the live audit liability R-12 named). Remediate each: record the evidence on a correction row (close the head, insert the corrected row with change_type = ''correction''), retract a certificate that never existed (close as retracted), or flip the category to flag-only in tenants.settings.tax_exemptions.certificate_required. Then re-apply.', n
            USING ERRCODE = 'check_violation';
    END IF;

    -- Closed (superseded/retracted) history without evidence is history,
    -- not a deploy blocker — as_of never returns it at current knowledge.
    SELECT count(*) INTO m
      FROM public.customer_tax_exemptions e
     WHERE e.recorded_at IS NOT NULL
       AND e.recorded_until IS NOT NULL
       AND NOT (   coalesce(e.certificate_number ~ '[[:alnum:]]', false)
                OR coalesce(e.certificate_url    ~ '[[:alnum:]]', false));
    IF m > 0 THEN
        RAISE NOTICE 'v5.4.2-09: % closed exemption assertion(s) in history lack certificate evidence; left as-is — closed rows never reach current-knowledge reads', m;
    END IF;

    -- Malformed config is surfaced now rather than at the first refused
    -- write — at BOTH levels: a wrong-shape tax_exemptions node makes every
    -- path under it read as absent (Codex round 2), so it is flagged the
    -- same as a wrong-shape certificate_required node (round 1).
    SELECT count(*) INTO m
      FROM public.tenants t
     WHERE (t.settings ? 'tax_exemptions' AND jsonb_typeof(t.settings -> 'tax_exemptions') <> 'object')
        OR (jsonb_typeof(t.settings -> 'tax_exemptions') = 'object'
            AND t.settings -> 'tax_exemptions' ? 'certificate_required'
            AND jsonb_typeof(t.settings #> '{tax_exemptions,certificate_required}') <> 'object');
    IF m > 0 THEN
        RAISE NOTICE 'v5.4.2-09: % tenant(s) carry a wrong-shape tax_exemptions or tax_exemptions.certificate_required node; both accessors will raise for them until corrected', m;
    END IF;

    -- The one valid shape is 1-999,999,999 (optional leading zeros): the
    -- length bound keeps the ::integer cast from overflowing into a raw
    -- out-of-range error instead of the friendly refusal (Codex LOW, rd 1).
    SELECT count(*) INTO m
      FROM public.tenants t
     WHERE (t.settings #>> '{tax_exemptions,renewal_notice_days_before}') IS NOT NULL
       AND (t.settings #>> '{tax_exemptions,renewal_notice_days_before}') !~ '^0*[1-9][0-9]{0,8}$';
    IF m > 0 THEN
        RAISE NOTICE 'v5.4.2-09: % tenant(s) carry an invalid tax_exemptions.renewal_notice_days_before; tax_exemption_renewal_notice_days() and the renewal view will raise for them until corrected', m;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. tax_exemption_certificate_required(tenant, exemption_type)
--    The per-category certificate-required-vs-flag-only designation.
--    Pattern: max_consecutive_estimates (v5.4.2-05) — settings-sourced,
--    validated, loud on bad config, defaulted where absent.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.tax_exemption_certificate_required(p_tenant_id uuid, p_exemption_type text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_raw   text;
    v_seen  boolean;
    v_shape jsonb;
BEGIN
    IF p_exemption_type IS NULL OR p_exemption_type NOT IN
       ('non_profit', 'government', 'agricultural', 'sales_for_resale', 'religious', 'educational', 'medical', 'other') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tax_exemption_certificate_required: %L is not a customer_tax_exemptions.exemption_type (R-13 domain)', p_exemption_type),
            ERRCODE = 'check_violation';
    END IF;

    SELECT true,
           t.settings ->  'tax_exemptions',
           t.settings #>> ARRAY['tax_exemptions', 'certificate_required', p_exemption_type]
      INTO v_seen, v_shape, v_raw
      FROM public.tenants t WHERE t.id = p_tenant_id;
    IF v_seen IS NOT TRUE THEN
        RAISE EXCEPTION USING MESSAGE = format('tenant %s not found (or not visible)', p_tenant_id), ERRCODE = 'no_data_found';
    END IF;

    -- A wrong-shape node ANYWHERE on the path would make the per-category
    -- read come back absent and silently fall back to the default; a
    -- compliance knob that half-exists raises instead. Checked at both
    -- levels — the tax_exemptions node itself (Codex round 2: an ancestor
    -- malformation reads as "absent" too) and the certificate_required node
    -- under it (Codex MEDIUM / Fable T28, round 1).
    IF v_shape IS NOT NULL AND jsonb_typeof(v_shape) <> 'object' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenants.settings.tax_exemptions is %s, not an object (CI-046)', jsonb_typeof(v_shape)),
            ERRCODE = 'check_violation';
    END IF;
    IF v_shape ? 'certificate_required' AND jsonb_typeof(v_shape -> 'certificate_required') <> 'object' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenants.settings.tax_exemptions.certificate_required is %s, not an object of per-category booleans (CI-046)', jsonb_typeof(v_shape -> 'certificate_required')),
            ERRCODE = 'check_violation';
    END IF;

    IF v_raw IS NULL THEN
        RETURN true;  -- the default: certificate-backed only (R-13 / Rule 3.287)
    ELSIF lower(v_raw) IN ('true', 't') THEN
        RETURN true;
    ELSIF lower(v_raw) IN ('false', 'f') THEN
        RETURN false;
    ELSE
        RAISE EXCEPTION USING
            MESSAGE = format('tenants.settings.tax_exemptions.certificate_required.%s = %L is invalid: true or false only (CI-046)', p_exemption_type, v_raw),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.tax_exemption_certificate_required(uuid, text) IS
    'CI-046''s certificate-required-vs-flag-only designation per exemption category (v5.4.2-09, A-9): tenants.settings.tax_exemptions.certificate_required.<exemption_type>, DEFAULT TRUE (R-13: the table holds certificate-backed exemptions only; Comptroller Rule 3.287 puts certificate liability on the seller). Flip a category to false only where the jurisdiction exempts that category by status with no document issued. Unknown category, a malformed value, or a non-object certificate_required node raises — no guessed direction on a compliance knob. The gate consults this at ENTRY to assertion only; a later flip never re-judges asserted rows, and every settings change is audited (tenant_configuration_history, v5.4.1-02, trigger-written) — the knob is an omission barrier, not a fraud barrier (an admin who can flip it can equally type a fake certificate number).';

-- ----------------------------------------------------------------------------
-- 2. The certificate-evidence gate: enforce_tax_exemption_lifecycle
--    redefined in place (same trigger a_enforce_tax_exemption_lifecycle,
--    BEFORE INSERT OR UPDATE). Everything above the marked block is
--    v5.4.2-03's behaviour, unchanged.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_tax_exemption_lifecycle() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'rejected' AND NEW.status <> 'rejected' THEN
            RAISE EXCEPTION 'customer_tax_exemptions %: rejected is terminal; enter a new exemption', OLD.id;
        END IF;
        IF OLD.status = 'pending_verification' AND NEW.status NOT IN ('pending_verification', 'active', 'rejected') THEN
            RAISE EXCEPTION 'customer_tax_exemptions %: pending_verification moves to active (verified) or rejected only, not %', OLD.id, NEW.status;
        END IF;
        IF OLD.recorded_at IS NOT NULL AND NEW.status IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'customer_tax_exemptions %: an asserted exemption does not change status in place — revocation (valid-time: the authority pulled the certificate) or expiry is a new row with effective_end/status set and supersedes_id = %, after closing this row; a certificate that never existed is a retraction (close as retracted)', OLD.id, OLD.id;
        END IF;
    END IF;

    -- v5.4.2-09 (A-9 / CI-046): entry to an asserted state requires
    -- documentary evidence unless the tenant flipped the category to
    -- flag-only. Fires exactly where R-12's verification lock sits — on
    -- the transition into assertion (INSERT born asserted, or the verify
    -- UPDATE that stamps recorded_at) — so drafts stay freely editable
    -- and already-asserted rows (frozen by the bi-temporal guard) are
    -- never re-judged by later config changes.
    -- Evidence = at least one alphanumeric character (same expression as the
    -- deploy precondition — keep them identical). NOT a btrim-blank check:
    -- btrim() strips ASCII space only, so a single tab / newline / NBSP would
    -- pass as "evidence" (Codex CRITICAL, round 1); requiring an alnum also
    -- refuses punctuation-only placeholders. coalesce() closes the NULL leg:
    -- NULL ~ x is NULL, and an IF that lands NULL would not fire.
    IF NEW.status IN ('active', 'expired', 'revoked')
       AND (TG_OP = 'INSERT' OR OLD.recorded_at IS NULL)
       AND NOT (   coalesce(NEW.certificate_number ~ '[[:alnum:]]', false)
                OR coalesce(NEW.certificate_url    ~ '[[:alnum:]]', false))
       AND public.tax_exemption_certificate_required(NEW.tenant_id, NEW.exemption_type) THEN
        RAISE EXCEPTION 'customer_tax_exemptions%: a % row cannot be asserted without certificate evidence — record certificate_number or certificate_url (the Form 01-339 number or the Comptroller-letter artifact; Rule 3.287 puts the liability on the seller), or flip exemption_type ''%'' to flag-only in tenants.settings.tax_exemptions.certificate_required (CI-046, v5.4.2-09)',
            CASE WHEN TG_OP = 'UPDATE' THEN ' ' || OLD.id ELSE '' END, NEW.status, NEW.exemption_type
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.status IN ('active', 'expired', 'revoked') AND NEW.recorded_at IS NULL THEN
        NEW.recorded_at := now();
    END IF;
    RETURN NEW;
END;
$$;

-- (Trigger a_enforce_tax_exemption_lifecycle already binds this function;
-- CREATE OR REPLACE changes the behaviour under the existing trigger.)

-- ----------------------------------------------------------------------------
-- 3. tax_exemption_renewal_notice_days(tenant) — the renewal-notice window.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.tax_exemption_renewal_notice_days(p_tenant_id uuid) RETURNS integer
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_raw   text;
    v_seen  boolean;
    v_shape jsonb;
BEGIN
    SELECT true, t.settings -> 'tax_exemptions', t.settings #>> '{tax_exemptions,renewal_notice_days_before}'
      INTO v_seen, v_shape, v_raw
      FROM public.tenants t WHERE t.id = p_tenant_id;
    IF v_seen IS NOT TRUE THEN
        RAISE EXCEPTION USING MESSAGE = format('tenant %s not found (or not visible)', p_tenant_id), ERRCODE = 'no_data_found';
    END IF;
    -- Same ancestor-shape rule as tax_exemption_certificate_required: a
    -- malformed tax_exemptions node must not read as "absent" and default.
    IF v_shape IS NOT NULL AND jsonb_typeof(v_shape) <> 'object' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenants.settings.tax_exemptions is %s, not an object (CI-046)', jsonb_typeof(v_shape)),
            ERRCODE = 'check_violation';
    END IF;
    IF v_raw IS NULL THEN
        RETURN 60;
    END IF;
    -- Validated as text before the cast: the regex is the friendly refusal
    -- for non-integers AND zero AND anything long enough to overflow the
    -- ::integer cast into a raw out-of-range error (Codex LOW, round 1).
    IF v_raw !~ '^0*[1-9][0-9]{0,8}$' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenants.settings.tax_exemptions.renewal_notice_days_before = %L is invalid: a positive integer of at most nine digits (CI-046)', v_raw),
            ERRCODE = 'check_violation';
    END IF;
    RETURN v_raw::integer;
END;
$$;

COMMENT ON FUNCTION public.tax_exemption_renewal_notice_days(uuid) IS
    'The tenant''s renewal-notice window in days (v5.4.2-09, A-9 / CI-046): tenants.settings.tax_exemptions.renewal_notice_days_before, default 60 (the figure the legacy customer_summary / compliance_statistics columns hard-code), must be >= 1. Consumed by customer_tax_exemptions_renewal_due; a non-integer value raises at read (a numeric config that fails silent is the CCK-9 defect class).';

-- ----------------------------------------------------------------------------
-- 4. customer_tax_exemptions_renewal_due — the operator renewal queue.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.customer_tax_exemptions_renewal_due WITH (security_invoker = true) AS
SELECT e.tenant_id,
       e.id            AS exemption_id,
       e.customer_id,
       c.customer_number,
       e.exemption_type,
       e.certificate_number,
       e.issuing_authority,
       e.service_types,
       e.effective_end,
       (e.effective_end - CURRENT_DATE)                                        AS days_remaining,
       (e.effective_end - public.tax_exemption_renewal_notice_days(e.tenant_id)) AS notice_window_opened_on,
       CASE WHEN e.effective_end < CURRENT_DATE THEN 'lapsed' ELSE 'renewal_due' END AS renewal_state
  FROM public.customer_tax_exemptions e
  JOIN public.customers c ON c.id = e.customer_id
 WHERE e.status = 'active'
   AND e.recorded_at IS NOT NULL
   AND e.recorded_until IS NULL
   AND e.effective_end IS NOT NULL
   -- <= not <: "notify N days before expiry" begins ON the day exactly N
   -- days remain (round 2 shipped < with the display column bent to match —
   -- the advance notice was silently N-1 days; Codex MEDIUM, round 2).
   AND e.effective_end <= CURRENT_DATE + public.tax_exemption_renewal_notice_days(e.tenant_id)
   -- A renewal on file quiets only a row still inside its bracket. A LAPSED
   -- row stays listed regardless (Fable LOW, round 1: a later-bracketed
   -- renewal used to hide it entirely): its remaining operator action — the
   -- valid-time expiry succession that closes it — is owed whether or not a
   -- renewal exists, and it leaves the queue exactly when that succession
   -- lands (the head is then closed).
   AND (e.effective_end < CURRENT_DATE
        OR NOT EXISTS (
        SELECT 1
          FROM public.customer_tax_exemptions r
         WHERE r.customer_id = e.customer_id
           AND r.exemption_type = e.exemption_type
           AND r.recorded_at IS NOT NULL
           AND r.recorded_until IS NULL
           AND r.status = 'active'
           AND r.effective_start > e.effective_start
           AND (r.effective_end IS NULL OR r.effective_end > e.effective_end)
   ));

COMMENT ON VIEW public.customer_tax_exemptions_renewal_due IS
    'CI-046''s "system surfaces upcoming expirations to operations" (v5.4.2-09, A-9): every CURRENT active exemption assertion whose effective_end is inside the tenant''s renewal-notice window (tax_exemption_renewal_notice_days, default 60; a row enters the queue ON the day exactly N days remain, i.e. notice_window_opened_on = effective_end - N) or already past. A renewal on file (a later-bracketed open active assertion for the same customer and category) quiets a row still inside its bracket; a LAPSED row stays listed even with a renewal on file — it still owes its valid-time expiry succession, and leaves the queue when that succession closes it. renewal_state = ''lapsed'': effective_end has passed (should_charge_tax is date-driven and stops honouring the row AFTER effective_end — the end date itself is still covered, the bracket is inclusive); ''renewal_due'': prompt the customer. Renewal is a NEW row, never an effective_end edit — the bracket froze with the assertion. Sourced from the exemptions table, NOT the legacy customers.tax_exemption_* columns (a manually-maintained display path the tax engine never reads — recorded residual, register note under CI-046). security_invoker: RLS applies.';

-- ----------------------------------------------------------------------------
-- 5. Comment refresh on the table and status column (append the -09 rule).
-- ----------------------------------------------------------------------------

COMMENT ON TABLE public.customer_tax_exemptions IS
    'Certificate-backed sales-tax exemptions only (R-13, v5.4.2-03): exempt organisations under Form 01-339 / Comptroller letter. Residential (§151.317) is derived from rate class, not a row; predominant-use (manufacturing) exemptions are per point of delivery and usually partial and get their own table later — ''industrial'' was removed from exemption_type. Bi-temporal in place (A-1): a row is a draft while pending_verification (recorded_at NULL, freely editable, DEFAULT — flipped from active by R-12), becomes an assertion when verified into active (recorded_at stamps; verified_by/verified_at required — Comptroller Rule 3.287 puts certificate liability on the seller), and is then frozen except notes/metadata. v5.4.2-09 (A-9 / CI-046): entering ANY asserted state also requires certificate evidence — certificate_number or certificate_url with at least one alphanumeric character — unless the tenant flipped the category to flag-only (tax_exemption_certificate_required); renewals surface through customer_tax_exemptions_renewal_due. Revocation is a valid-time event (a new row with effective_end/revoked_* and status revoked, superseding the active row); a certificate that never existed is a retraction (close with closed_type = retracted). A revocation discovered late means issued bills were under-taxed — that routes to the void/rebill infrastructure as a correction run, not merely a status change. Read through customer_tax_exemption_as_of(customer, p_valid_at, p_recorded_at) / should_charge_tax().';

COMMENT ON COLUMN public.customer_tax_exemptions.status IS
    'pending_verification (default; draft, editable) -> active (verified; asserted, frozen) | rejected (terminal draft). expired / revoked are asserted end states written as NEW rows superseding the active one (valid-time closings), never in-place flips. CHECKs: active/expired/revoked require verified_by AND verified_at; revoked requires revoked_at, revoked_by AND effective_end; expired requires effective_end; drafts have recorded_at NULL, asserted rows have it set. v5.4.2-09: entry to any asserted state additionally requires certificate_number or certificate_url unless the category is flag-only for the tenant (tax_exemption_certificate_required).';

-- ============================================================================
-- END PATCH v5.4.2-09
-- ============================================================================
