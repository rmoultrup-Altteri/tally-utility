-- ============================================================================
-- PATCH v5.4.2-12 — backbilling caps: how far back the law lets us bill, and
--                    the per-period evidence that makes a trim defensible
--                    (schema-parity-plan Phase 4 Wave 3, item A-2)
-- ============================================================================
-- Authority:   Kyle's A-2 record, rulings R-19…R-31 (closed 2026-09-14), the
--              customer-class-keying record CCK-1…CCK-14, and the
--              consolidation GBM application/a2-implementation-brief-2026-09-21.md.
--              Statutory basis is 16 TAC §7.45, read in full by Kyle on
--              2026-09-02 and quoted to the clause in his record. NOTHING in
--              this patch is a fresh reading of the rule; R-28 carries an
--              explicit caveat that the (4)(E)(vi) closing clause was not
--              re-read on 2026-09-14, and that caveat travels here unchanged.
--
--              Ryan, 2026-09-22 (brief §7, plain language):
--                (1) ship the simple protection default — CCK-14's
--                    all_non_residential_protected, no volumetric resolver,
--                    no per-meter determination record, no promote/demote
--                    hysteresis inside A-2 (F-5);
--                (2) the under-reach override gets a database-stamped
--                    write-once home, NOT a row in invoice_events — that log
--                    is app-insertable, so the software could otherwise clear
--                    its own warning (F-3);
--                (3) the correction-run target rows get their own append-only
--                    log for setup-time events, because invoice_events.
--                    invoice_id is NOT NULL and at gate (ii) no correction
--                    invoice exists yet (F-1);
--                (4) build narrow on both Kyle questions — backbill_cause and
--                    anchor_date freeze at snapshot existence rather than at
--                    post (F-4), and the override takes a short
--                    evidentiary-impossibility reason-code list rather than
--                    free text. Both are narrower than R-19 / R-27 as
--                    written, both are with Kyle
--                    (application/kyle-questions-2026-09-22-a2-override-and-cause-freeze.md),
--                    and narrow-first is the cheap direction under an
--                    append-only schema: widening a CHECK later is one line,
--                    narrowing means judging every row already written under
--                    the loose rule (D-2026-09-09-03).
--
--              Ryan, 2026-09-22: A-2 lands BEFORE the tenant-blind foreign
--              key remediation patch (brief §8's open call, answered). A-2
--              still repairs the three links it resolves through, below.
--
-- The rule, in one sentence: when a utility discovers it under-charged a
-- customer, §7.45 limits how far back it may bill — and for a meter found
-- more than 2% fast the limit runs the OTHER way, making the refund
-- mandatory rather than optional.
--
-- ----------------------------------------------------------------------------
-- The two shapes this patch exists to avoid
-- ----------------------------------------------------------------------------
--
--   A NULLABLE INTEGER WHERE NULL MEANS SOMETHING. R-20 ruled the enforceable
--   bound an explicit enum precisely because a nullable month count where
--   NULL means "never" is the NULL-poisoning class from the 2026-08-26 coda:
--   a CHECK passes on NULL, so the guard fails open silently, and a guard
--   that fails open is worse than none because it is trusted. F-7 found the
--   billable side had the same three-shape problem and no discriminator —
--   and there a NULL read as "no limit" bills PAST STATUTORY AUTHORITY, which
--   is the more expensive direction. Both sides get an explicit non-null
--   scope enum with an IS NOT NULL conjunct in the CHECK.
--
--   AN APP-WRITTEN EVENT STANDING IN FOR A GUARD'S FACT. invoice_events is
--   insertable by tally_app (tu.sql policy invoice_events_insert), so an
--   under-reach override recorded only as an event is assertable by the
--   application: any session that can write the event can clear the warning,
--   with no human in it. That is the same shape as the app.void_operation
--   carve-out recorded in Appendix A-23 (1). The override therefore lives in
--   database-stamped write-once columns that only this patch's trigger sets;
--   the log backfills the audit trail rather than carrying the decision.
--
-- Verified on the v5.4.2-11 build before drafting, not assumed:
--   meter_readings.access_status      CHECK at tu.sql:3575 — twelve values
--   meter_readings.estimation_reason  CHECK at tu.sql:3578 — ten values
--   meters test columns               tu.sql:3691-3694
--   correction_run_targets            tu.sql:1581-1598; its freeze trigger
--                                     (v5.4.2-10:332) is COLUMN-LISTED, so a
--                                     new column is unfrozen by construction
--   invoice_events.invoice_id         NOT NULL (tu.sql:3252); event_type
--                                     CHECK carries eleven values (3262)
--   jurisdictions                     tu.sql:11569-11604 — NO UNIQUE (id, tenant_id)
--   service_locations.jurisdiction_id FK at 11608 is TENANT-BLIND
--   pg_constraint                     15 tables carry UNIQUE (id, tenant_id);
--                                     neither jurisdictions nor
--                                     correction_run_targets is among them
--
-- ----------------------------------------------------------------------------
-- What lands
-- ----------------------------------------------------------------------------
--
--   1. THE PROTECTION MODE (CCK-14, F-5). tenants.regulatory_class_mode,
--      three values, default all_non_residential_protected. Under the default
--      every non-residential account is in §7.45 scope, which is correct for
--      any tenant whose filed tariff has no size tier and fails toward
--      protection. explicit_class and volumetric_threshold are declared here
--      so the later CCK patch widens nothing; volumetric_threshold is
--      REFUSED at resolve time until that patch ships its substrate, rather
--      than silently behaving like the default.
--
--   2. COMPOSITE-KEY GROUNDWORK (F-6). UNIQUE (id, tenant_id) on
--      jurisdictions and on correction_run_targets, so this patch's own links
--      can be tenant-composite, plus the repair of
--      service_locations.jurisdiction_id — A-2 resolves a cap through that
--      column, so its blindness is A-2's business. This is three of the 229
--      links in the inventory; the rest are their own patch.
--
--   3. THE CAP TABLE (R-20, R-26, F-7). backbilling_cap_rules, two bounds per
--      row because the billable and enforceable limits diverge and do not
--      coincide for the metering causes, keyed
--      (tenant_id, jurisdiction_id NULLABLE, service_type, customer_class,
--      cause) with most-specific-wins over two levels only. Seeded with the
--      Texas gas rows for both classes — an unprotected row is written
--      EXPLICITLY uncapped rather than left absent, so a missing rule is an
--      error rather than a silent permission.
--
--   4. THE TARGET COLUMNS (R-19). backbill_cause and anchor_date on
--      correction_run_targets, findings-based not intent-based: the statute
--      triggers on "if any meter test reveals" and on the meter being "found
--      not to register", so the cause is created by evidence. The void-reason
--      enum is NOT extended and stays operational (decision table Open
--      question 1). anchor_date exists because (v)(II) runs back from
--      DISCOVERY and (v)(I) from the TEST — treating both as discovery
--      silently misdates one of them.
--
--   5. THE OVERRIDE'S PROTECTED HOME (R-27, F-3). Write-once, database-
--      stamped columns on the target, set only by this patch's trigger from a
--      short evidentiary-impossibility reason-code list.
--
--   6. THE SETUP-TIME LOG (F-1). correction_run_target_events, append-only,
--      for the decisions taken before any correction invoice exists.
--
--   7. THE READ CLASSIFICATION (R-30). access_status / estimation_reason
--      mapped to three buckets as a platform-fixed mapping, with the four
--      ambiguous values left in the safe third bucket per refinement 3.
--
--   8. THE EVIDENCE RECORD (R-25). backbilling_period_evaluations, append-
--      only, one row per original billing period evaluated. Direction is
--      tested PER ORIGINAL BILLING PERIOD, not per invoice: periods where the
--      customer owes more are capped and trimmed if outside the window;
--      periods where the customer is OWED money always pass, uncapped.
--
--   9. THE TWO GATES (R-22, R-23, R-25, R-27). Gate (ii) at correction-run
--      setup — refuse where the entire period sits beyond the bound, raise
--      the under-reach warning otherwise. Gate (iii) at correction-invoice
--      creation — the per-period test and the TRIM (R-23: the rebill proceeds
--      for the permitted window and the out-of-bounds remainder is forfeited;
--      outright rejection only where the whole target period is beyond the
--      bound). Neither is inside void_invoice() (R-22): the regulated act is
--      the charge, not the void.
--
--  10. THE FREEZE EXTENSION (F-4). backbill_cause and anchor_date join the
--      v5.4.2-10 target freeze at SNAPSHOT EXISTENCE. R-19 says the cause
--      freezes at correction-invoice post, but the calculation snapshot is
--      validated BEFORE issuance and the evidence record is written against
--      the cause in force at gate (iii) — a cause changed between snapshot
--      and post would leave frozen evidence describing a window the target no
--      longer claims. Stated here as an amendment to R-19, not an oversight.
--
--  11. THE AC-32 TAIL. Both new tables are born leaky; the patch ends by
--      calling public.assert_tenant_isolation_invariants(), and the battery
--      shows it RAISES on planted drift rather than merely passing.
--
-- ----------------------------------------------------------------------------
-- What is deliberately NOT here
-- ----------------------------------------------------------------------------
--
--   The meter test history table (R-31 / CI-091) — its own brief and patch,
--   immediately behind this one, required before the first gas tenant goes
--   live because meters.last_test_date is a single mutable field overwritten
--   by each test, so any period without history is a permanent hole. The
--   hard constraint R-31 places on THIS patch is honoured below: NEVER derive
--   a test date from test_interval_months. Back-computing a plausible
--   last-test date manufactures evidence for the exact figure a dispute will
--   contest.
--
--   The CCK volumetric resolver (CCK-4…CCK-13) — mode-only in v1 per F-5.
--   Collections behaviour on the enforceable bound — R-20 hands it to
--   Family 9 as a recorded value, not a wired behaviour.
--   The Phase 8 correction diff view and the gate (ii) operator surface.
--   estimation_reason's cause/method conflation (R-30's separate defect).
--   CI-093's incorporated/unincorporated question, which R-26 de-gated.
--
--   Two bill-content duties attach to a backbill and belong to the invoice
--   renderer, recorded here as consumers rather than enforced: (6)(B)(v)
--   requires adjustment totals AND the amount per billing unit, and
--   (6)(B)(viii) requires distinct marking of an estimated bill — which a
--   (v)(II) backbill is by definition, since the rule computes it from
--   like-period consumption or from similarly situated customers.
--
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The protection mode (CCK-14, F-5)
-- ----------------------------------------------------------------------------
-- §7.45 protects residential and small commercial customers, so the system
-- must decide which side of that line an account falls on. Kyle designed a
-- full mechanism (measure each meter against a configured threshold, move
-- accounts across the line only after three consecutive periods, require
-- operator approval before REMOVING protection, keep a permanent
-- determination record). None of that substrate exists in tu.sql, and
-- building it inside A-2 roughly doubles the patch. CCK-14 makes the default
-- tractable on its own.
--
-- All three modes are declared now so the later CCK patch widens no CHECK.
-- volumetric_threshold is accepted by the CHECK but REFUSED at resolve time
-- until that patch ships its substrate — a mode that silently degraded to the
-- default would be a guard failing open under a name that says otherwise.

ALTER TABLE public.tenants
    ADD COLUMN IF NOT EXISTS regulatory_class_mode text
        DEFAULT 'all_non_residential_protected'::text NOT NULL;

ALTER TABLE public.tenants DROP CONSTRAINT IF EXISTS tenants_regulatory_class_mode_check;
ALTER TABLE public.tenants ADD CONSTRAINT tenants_regulatory_class_mode_check
    CHECK ((regulatory_class_mode = ANY (ARRAY[
        'all_non_residential_protected'::text,
        'explicit_class'::text,
        'volumetric_threshold'::text])));

COMMENT ON COLUMN public.tenants.regulatory_class_mode IS
    'CCK-14. How this tenant decides whether an account is inside 16 TAC §7.45''s protected class (residential and small commercial). all_non_residential_protected (default, v1): every non-residential account is in scope — correct for any tenant whose filed tariff has no size tier, fails toward protection, touches no rate calculation, so under-billing risk is zero and the over-protection cost is bounded and operator-visible. explicit_class: trust the size-tier values on customers.customer_type. volumetric_threshold: the CCK-4…CCK-13 resolver — DECLARED here so that patch widens no CHECK, and REFUSED by backbilling_customer_class() until its substrate exists, because a mode that silently behaved like the default would be a guard failing open under a name that says otherwise.';


-- ----------------------------------------------------------------------------
-- 2. Composite-key groundwork (F-6)
-- ----------------------------------------------------------------------------
-- A tenant-composite foreign key needs a UNIQUE (id, tenant_id) on its
-- target. Neither jurisdictions nor correction_run_targets carries one, so
-- this patch's own links could not be tenant-checked without adding them —
-- the same move v5.4.2-10 made for invoices.replaces_invoice_id.
--
-- Both are cheap and neither is speculative: A-2 resolves a cap row through a
-- jurisdiction and hangs two append-only tables off a correction target.
--
-- KNOWINGLY PROVISIONAL: if the shared-place restructure goes ahead
-- (GBM application/jurisdictions-shared-place-modelling-2026-09-22.md), the
-- jurisdiction half of this is partly redone. One constraint and one foreign
-- key — cheap to redo, recorded here rather than discovered later.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'jurisdictions_id_tenant_id_key'
                      AND conrelid = 'public.jurisdictions'::regclass) THEN
        ALTER TABLE public.jurisdictions
            ADD CONSTRAINT jurisdictions_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'correction_run_targets_id_tenant_id_key'
                      AND conrelid = 'public.correction_run_targets'::regclass) THEN
        ALTER TABLE public.correction_run_targets
            ADD CONSTRAINT correction_run_targets_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;

-- The premise-side repair. service_locations.jurisdiction_id named a city's
-- id with nothing requiring the city to belong to the same utility. Row-level
-- security still governed reads, so this was never a browse-another-tenant
-- vector; the realistic routes are a bad import or backfill (which runs with
-- elevated rights), a platform administrator (who bypasses RLS by design), or
-- an application bug writing an id it should not have. It is a data-integrity
-- hole rather than an attack vector — but jurisdiction already decides
-- weather-normalisation applicability and the tariff variant, and under this
-- patch it also decides how far back the law lets us bill.
--
-- Refuse to create the composite key over data that already violates it: a
-- silent ALTER that succeeded because NOT VALID was passed would be exactly
-- the fails-open shape this patch is about.
DO $$
DECLARE v_bad bigint;
BEGIN
    SELECT count(*) INTO v_bad
      FROM public.service_locations sl
      JOIN public.jurisdictions j ON j.id = sl.jurisdiction_id
     WHERE sl.jurisdiction_id IS NOT NULL
       AND j.tenant_id IS DISTINCT FROM sl.tenant_id;
    IF v_bad > 0 THEN
        RAISE EXCEPTION 'v5.4.2-12: % service_locations row(s) point at another tenant''s jurisdiction; repair the data before applying this patch', v_bad
            USING ERRCODE = 'integrity_constraint_violation',
                  HINT = 'SELECT sl.id, sl.tenant_id, sl.jurisdiction_id FROM public.service_locations sl JOIN public.jurisdictions j ON j.id = sl.jurisdiction_id WHERE j.tenant_id IS DISTINCT FROM sl.tenant_id;';
    END IF;
END;
$$;

ALTER TABLE public.service_locations DROP CONSTRAINT IF EXISTS service_locations_jurisdiction_id_fkey;
ALTER TABLE public.service_locations ADD CONSTRAINT service_locations_jurisdiction_id_fkey
    FOREIGN KEY (jurisdiction_id, tenant_id) REFERENCES public.jurisdictions(id, tenant_id);

COMMENT ON COLUMN public.service_locations.jurisdiction_id IS
    'The premise''s jurisdiction (D5-2, v5.4.0-03) — the service-location attribute through which WNA applicability, the WNA tariff variant and (since v5.4.2-12) the §7.45 backbilling cap resolve. Its foreign key was tenant-blind until v5.4.2-12 and is now composite on jurisdictions(id, tenant_id); it is one of the 229 links inventoried in GBM application/tenant-blind-foreign-keys-2026-09-22.md and is repaired here because A-2 resolves a statutory cap through this column. Nullable: population is a tenant-onboarding/backfill concern, and the existing inside_city_limits/franchise_city columns remain as-is.';


-- ----------------------------------------------------------------------------
-- 3. The cap table (R-20, R-26, F-7)
-- ----------------------------------------------------------------------------
-- Two bounds per row, because R-20 found the billable and enforceable limits
-- DIVERGE and do not coincide for the metering causes. The billable bound is
-- how far back we may BILL; the enforceable bound is how far back we may
-- pursue COLLECTION on what we billed. For a meter found not to register,
-- three months may be billed and none of it may ever be enforced.
--
-- Both scopes are explicit non-null enums with the month count nullable ONLY
-- under the counted variants, with an IS NOT NULL conjunct in the CHECK.
-- R-20 ruled this for the enforceable side against the NULL-poisoning class
-- from the 2026-08-26 coda; F-7 found the billable side had the same
-- three-shape problem and no discriminator, where a NULL read as "no limit"
-- bills past statutory authority.

CREATE TABLE IF NOT EXISTS public.backbilling_cap_rules (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    jurisdiction_id     uuid,
    service_type        text NOT NULL,
    customer_class      text NOT NULL,
    cause               text NOT NULL,
    billable_scope      text NOT NULL,
    billable_months     integer,
    enforceable_scope   text NOT NULL,
    enforceable_months  integer,
    source_note         text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    updated_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT backbilling_cap_rules_pkey PRIMARY KEY (id),
    CONSTRAINT backbilling_cap_rules_id_tenant_id_key UNIQUE (id, tenant_id),
    -- Refinement 1 (R-26 mechanics). NULLS NOT DISTINCT so that two conflicting
    -- state-default rows cannot both exist: under ordinary UNIQUE semantics
    -- every NULL jurisdiction_id is distinct from every other, and resolution
    -- would become nondeterministic — the same fails-open-on-NULL class R-20
    -- ruled against. PG16 cluster; two partial indexes split on
    -- jurisdiction_id IS NULL is the fallback if this form causes trouble.
    CONSTRAINT backbilling_cap_rules_key UNIQUE NULLS NOT DISTINCT
        (tenant_id, jurisdiction_id, service_type, customer_class, cause),
    CONSTRAINT backbilling_cap_rules_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT backbilling_cap_rules_jurisdiction_fkey
        FOREIGN KEY (jurisdiction_id, tenant_id)
        REFERENCES public.jurisdictions(id, tenant_id),
    CONSTRAINT backbilling_cap_rules_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT backbilling_cap_rules_customer_class_check
        CHECK ((customer_class = ANY (ARRAY['protected'::text, 'unprotected'::text]))),
    CONSTRAINT backbilling_cap_rules_cause_check
        CHECK ((cause = ANY (ARRAY['non_registering_meter'::text, 'meter_error'::text, 'rate_misapplication'::text, 'estimation_catchup'::text, 'tampering_theft'::text]))),
    CONSTRAINT backbilling_cap_rules_billable_scope_check
        CHECK ((billable_scope = ANY (ARRAY['uncapped'::text, 'months_from_anchor'::text, 'shorter_of_months_or_last_test'::text]))),
    CONSTRAINT backbilling_cap_rules_enforceable_scope_check
        CHECK ((enforceable_scope = ANY (ARRAY['uncapped'::text, 'months'::text, 'never'::text, 'conditional_on_read_classification'::text]))),
    -- The month count is present exactly under the counted variants and absent
    -- otherwise. Written as an equivalence, not as two one-way implications:
    -- a one-way rule lets the uncounted variants carry a stray integer that
    -- reads as a limit nobody applies.
    CONSTRAINT backbilling_cap_rules_billable_months_check
        CHECK ((((billable_scope = ANY (ARRAY['months_from_anchor'::text, 'shorter_of_months_or_last_test'::text])) AND (billable_months IS NOT NULL) AND (billable_months > 0))
             OR ((billable_scope = 'uncapped'::text) AND (billable_months IS NULL)))),
    CONSTRAINT backbilling_cap_rules_enforceable_months_check
        CHECK ((((enforceable_scope = 'months'::text) AND (enforceable_months IS NOT NULL) AND (enforceable_months > 0))
             OR ((enforceable_scope <> 'months'::text) AND (enforceable_months IS NULL)))),
    -- R-21 rejected inheriting meter_error's six months for estimation_catchup
    -- as exactly the uncited-number failure the water-rule miscitation already
    -- cost this project once. Every row must say where its numbers come from.
    CONSTRAINT backbilling_cap_rules_source_note_check
        CHECK ((source_note ~ '[[:alnum:]]'::text))
);

CREATE INDEX IF NOT EXISTS idx_backbilling_cap_rules_tenant ON public.backbilling_cap_rules USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_backbilling_cap_rules_resolve ON public.backbilling_cap_rules USING btree (tenant_id, service_type, customer_class, cause);

ALTER TABLE public.backbilling_cap_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backbilling_cap_rules FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.backbilling_cap_rules;
CREATE POLICY tenant_isolation ON public.backbilling_cap_rules USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

DROP TRIGGER IF EXISTS set_updated_at ON public.backbilling_cap_rules;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.backbilling_cap_rules FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

COMMENT ON TABLE public.backbilling_cap_rules IS
    'A-2 (v5.4.2-12). How far back 16 TAC §7.45 lets this tenant bill, and separately how far back it may enforce collection, per (jurisdiction, service type, customer class, cause). Two bounds because R-20 found they diverge: for a non-registering meter three months may be BILLED and none of it may ever be ENFORCED. Resolution is most-specific-wins over exactly two levels (R-26) — the service location''s jurisdiction, else the NULL-jurisdiction state/filed-tariff default row; municipal rows are admitted only where the tenant operates under a lawfully established differing municipal standard evidenced by an ordinance or filed instrument, never created speculatively per franchise city. Seeded by seed_backbilling_cap_defaults() with the Texas gas rows for BOTH customer classes: an unprotected row is written explicitly uncapped rather than left absent, so a missing rule is an error the gate raises rather than a silent permission.';

COMMENT ON COLUMN public.backbilling_cap_rules.jurisdiction_id IS
    'R-26. NULL is the state / filed-tariff default row, not "unknown" — and the UNIQUE carries NULLS NOT DISTINCT so two conflicting defaults cannot coexist and make resolution nondeterministic.';

COMMENT ON COLUMN public.backbilling_cap_rules.customer_class IS
    'Whether the account is inside §7.45''s protected class. Resolved by backbilling_customer_class() from tenants.regulatory_class_mode (CCK-14), NOT stored on the customer: the class is a finding about an account at a moment, and v1''s default makes it a constant.';

COMMENT ON COLUMN public.backbilling_cap_rules.billable_scope IS
    'F-7. The discriminator R-20 gave the enforceable side and the billable side lacked. uncapped = no §7.45 billing limit for this cause. months_from_anchor = billable_months back from anchor_date. shorter_of_months_or_last_test = the shorter of billable_months and the interval back to the last meter test, from the test date — (7)(B)(v)(I). A nullable integer here would fail open in the expensive direction: NULL read as "no limit" bills past statutory authority.';

COMMENT ON COLUMN public.backbilling_cap_rules.enforceable_scope IS
    'R-20. How far back collection may be pursued on what was billed. never = billed but never enforceable, the (4)(E)(vi) outcome for the metering causes. conditional_on_read_classification = the estimation_catchup case, resolved per billing period from the contemporaneous read record by backbilling_read_classification() (R-30), defaulting to never where no basis was recorded. Handed to Family 9 as a recorded value; this patch wires no collections behaviour.';

COMMENT ON COLUMN public.backbilling_cap_rules.source_note IS
    'The clause these numbers come from. Required and non-blank: R-21 rejected inheriting meter_error''s six months for estimation_catchup as exactly the uncited-number failure the water-rule miscitation already cost this project once.';

-- The Texas gas seed rows (R-20's table), as NULL-jurisdiction defaults.
--
-- Written as a re-runnable function rather than a one-shot INSERT because a
-- tenant created AFTER this patch would otherwise have no cap rules at all,
-- and the gates below fail closed — correct, but it would bite every new
-- tenant's first correction. Tenant onboarding calls this. It is idempotent
-- and never overwrites a row a tenant has edited.

CREATE OR REPLACE FUNCTION public.seed_backbilling_cap_defaults(p_tenant_id uuid)
    RETURNS integer
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inserted integer;
BEGIN
    INSERT INTO public.backbilling_cap_rules
        (tenant_id, jurisdiction_id, service_type, customer_class, cause,
         billable_scope, billable_months, enforceable_scope, enforceable_months, source_note)
    VALUES
    -- PROTECTED — residential and small commercial, the §7.45 class.
        (p_tenant_id, NULL, 'gas', 'protected', 'non_registering_meter',
         'months_from_anchor', 3, 'never', NULL,
         '16 TAC 7.45(7)(B)(v)(II) — three months back from discovery where the meter is found not to register; (4)(E)(vi) bars enforcement.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'meter_error',
         'shorter_of_months_or_last_test', 6, 'never', NULL,
         '16 TAC 7.45(7)(B)(v)(I) — the shorter of six months and the interval back to the last test, from the test date; (4)(E)(vi) bars enforcement.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'rate_misapplication',
         'uncapped', NULL, 'months', 6,
         '16 TAC 7.45(4)(E)(v) — no billing cap on correcting a misapplied rate; (3)(C)(iii) bounds enforcement at six months.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'estimation_catchup',
         'uncapped', NULL, 'conditional_on_read_classification', NULL,
         'No 7.45 billing cap on an estimation catch-up; estimation is governed by (6)(C) and enforcement by (4)(E)(vii), which turns on whether the failure to read was beyond the utility''s control. R-21 expressly REJECTED inheriting meter_error''s six months here — that number has no citation for this cause.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'tampering_theft',
         'uncapped', NULL, 'uncapped', NULL,
         '16 TAC 7.45(4)(D)(v) — tampering and theft of service sit outside the backbilling limits; (4)(E)(vi) carve-out.'),
    -- UNPROTECTED — written explicitly rather than left absent, so that a
    -- missing rule stays an error the gate raises instead of quietly reading
    -- as permission. Under v1's all_non_residential_protected mode nothing
    -- resolves to this class; the rows exist so that enabling explicit_class
    -- later is a settings change rather than a data migration.
        (p_tenant_id, NULL, 'gas', 'unprotected', 'non_registering_meter',
         'uncapped', NULL, 'uncapped', NULL,
         '16 TAC 7.45 does not reach this class; ordinary limitations law governs and is outside this table.'),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'meter_error',
         'uncapped', NULL, 'uncapped', NULL,
         '16 TAC 7.45 does not reach this class; ordinary limitations law governs and is outside this table.'),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'rate_misapplication',
         'uncapped', NULL, 'uncapped', NULL,
         '16 TAC 7.45 does not reach this class; ordinary limitations law governs and is outside this table.'),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'estimation_catchup',
         'uncapped', NULL, 'uncapped', NULL,
         '16 TAC 7.45 does not reach this class; ordinary limitations law governs and is outside this table.'),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'tampering_theft',
         'uncapped', NULL, 'uncapped', NULL,
         '16 TAC 7.45 does not reach this class; ordinary limitations law governs and is outside this table.')
    ON CONFLICT ON CONSTRAINT backbilling_cap_rules_key DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted;
END;
$$;

COMMENT ON FUNCTION public.seed_backbilling_cap_defaults(uuid) IS
    'A-2 (v5.4.2-12). Seeds one tenant''s Texas GAS backbilling cap defaults (R-20''s table) as NULL-jurisdiction rows, for both customer classes. Idempotent — ON CONFLICT DO NOTHING, so a tenant''s edited row is never overwritten. Tenant onboarding must call this: a tenant with no cap rules cannot run a correction at all, because the gates fail closed. Texas-only launch scope — no water/sewer/electric rows are seeded, and no jurisdiction-specific rows; a municipal row is admitted only where the tenant operates under a lawfully established differing municipal standard evidenced by an ordinance or filed instrument (R-26).';

DO $$
DECLARE r record; v_n integer; v_total integer := 0; v_tenants integer := 0;
BEGIN
    FOR r IN SELECT id FROM public.tenants LOOP
        v_n := public.seed_backbilling_cap_defaults(r.id);
        v_total := v_total + v_n;
        v_tenants := v_tenants + 1;
    END LOOP;
    RAISE NOTICE 'v5.4.2-12: seeded % backbilling cap rule(s) across % tenant(s); onboarding must call seed_backbilling_cap_defaults() for tenants created after this patch', v_total, v_tenants;
END;
$$;


-- ----------------------------------------------------------------------------
-- 4. The target columns, and the override's protected home (R-19, R-27, F-3)
-- ----------------------------------------------------------------------------
-- backbill_cause is FINDINGS-BASED, not intent-based: the statute triggers on
-- "if any meter test reveals" and on the meter being "found not to register",
-- so the cause is created by evidence — a test result, a tamper
-- investigation, a rate audit — not by an operator's stated purpose. The
-- void-reason enum is NOT extended and stays operational (decision table
-- Open question 1, answered by R-19 this way).
--
-- Revision is real and expected: meter_error -> tampering_theft is the common
-- progression, because the test result is often what opens the tamper
-- investigation. The cap re-evaluates on every cause change. Section 10
-- below is where that revisability stops.
--
-- anchor_date exists because the two anchors DIFFER: (7)(B)(v)(II) runs back
-- from DISCOVERY and (v)(I) from the TEST. Treating both as discovery
-- silently misdates one of them by however long the investigation took.
--
-- NULLABLE, and deliberately so. Not every correction is a §7.45 backbill —
-- a clerical re-issue has no statutory cause, and forcing one would mean
-- operators picking the least-wrong value from a list none of which is true.
-- The discipline sits at gate (iii) instead: a target with no cause may only
-- REDUCE what the customer owes. Nothing may be billed ADDITIONALLY without a
-- cause on the record.

ALTER TABLE public.correction_run_targets
    ADD COLUMN IF NOT EXISTS backbill_cause text,
    ADD COLUMN IF NOT EXISTS anchor_date date,
    ADD COLUMN IF NOT EXISTS underreach_override_reason text,
    ADD COLUMN IF NOT EXISTS underreach_override_at timestamp with time zone,
    ADD COLUMN IF NOT EXISTS underreach_override_by uuid;

ALTER TABLE public.correction_run_targets DROP CONSTRAINT IF EXISTS correction_run_targets_backbill_cause_check;
ALTER TABLE public.correction_run_targets ADD CONSTRAINT correction_run_targets_backbill_cause_check
    CHECK ((backbill_cause IS NULL OR (backbill_cause = ANY (ARRAY['non_registering_meter'::text, 'meter_error'::text, 'rate_misapplication'::text, 'estimation_catchup'::text, 'tampering_theft'::text]))));

-- The cause and its anchor travel together. A cause with no anchor has no
-- window to compute; an anchor with no cause names a window nothing claims.
ALTER TABLE public.correction_run_targets DROP CONSTRAINT IF EXISTS correction_run_targets_anchor_pairing_check;
ALTER TABLE public.correction_run_targets ADD CONSTRAINT correction_run_targets_anchor_pairing_check
    CHECK (((backbill_cause IS NULL) = (anchor_date IS NULL)));

-- R-27's override, narrowed per Ryan's decision 4 to a short
-- evidentiary-impossibility list rather than free text. Kyle recorded the
-- constraint himself: (7)(B)(v)(I) permits foregoing the correction only
-- where the error is to the UTILITY'S disadvantage, so an unrestricted
-- override lets an operator decline a duty the statute does not allow to be
-- declined. With Kyle; narrow-first because widening this CHECK later is one
-- line where narrowing it means judging every free-text row already written.
ALTER TABLE public.correction_run_targets DROP CONSTRAINT IF EXISTS correction_run_targets_underreach_reason_check;
ALTER TABLE public.correction_run_targets ADD CONSTRAINT correction_run_targets_underreach_reason_check
    CHECK ((underreach_override_reason IS NULL OR (underreach_override_reason = ANY (ARRAY['no_read_history'::text, 'meter_replaced'::text, 'records_predate_acquisition'::text]))));

-- The stamp and the reason travel together, and the stamp is the database's.
ALTER TABLE public.correction_run_targets DROP CONSTRAINT IF EXISTS correction_run_targets_underreach_pairing_check;
ALTER TABLE public.correction_run_targets ADD CONSTRAINT correction_run_targets_underreach_pairing_check
    CHECK (((underreach_override_reason IS NULL) = (underreach_override_at IS NULL)));

COMMENT ON COLUMN public.correction_run_targets.backbill_cause IS
    'R-19 (A-2, v5.4.2-12). Why this bill is being corrected, as a FINDING from evidence — a test result, a tamper investigation, a rate audit — not an operator''s stated intent: §7.45 triggers on "if any meter test reveals" and on the meter being "found not to register". Selects the governing backbilling_cap_rules row. Revisable (meter_error -> tampering_theft is the common progression) until a calculation snapshot exists for the correction, at which point it freezes with the rest of the election (F-4, an amendment to R-19''s "freezes at post"). NULL is legitimate — a clerical re-issue has no statutory cause — but a target with no cause may only REDUCE what the customer owes.';

COMMENT ON COLUMN public.correction_run_targets.anchor_date IS
    'R-19 (A-2, v5.4.2-12). The date the billable window counts back FROM. It exists because the two anchors differ: (7)(B)(v)(II) runs from DISCOVERY and (v)(I) from the TEST, so treating both as discovery silently misdates one of them by however long the investigation took. Which reading produced it is recorded per period on backbilling_period_evaluations.anchor_basis (R-29), so a reversal is a re-resolution rather than archaeology.';

COMMENT ON COLUMN public.correction_run_targets.underreach_override_reason IS
    'R-27 (A-2, v5.4.2-12), narrowed by Ryan 2026-09-22. The operator''s recorded ground for correcting LESS than (7)(B)(v)(I) mandates where a meter over-registered. A short evidentiary-impossibility list, not free text: Kyle recorded that (v)(I) permits foregoing the correction only where the error is to the UTILITY''S disadvantage, so an unrestricted override would let an operator decline a duty the statute does not allow to be declined. With Kyle (kyle-questions-2026-09-22-a2-override-and-cause-freeze.md); widening this CHECK later is one line.';

COMMENT ON COLUMN public.correction_run_targets.underreach_override_at IS
    'When the override was recorded — the DATABASE''S clock, write-once, never caller-supplied (superusers exempt for migrations). This column and its reason are what the gate believes. They are deliberately NOT an invoice_events row: that log is insertable by tally_app, so an override recorded only as an event would be assertable by the application with no human in it — the same shape as the app.void_operation carve-out in Appendix A-23 (1). The log backfills the audit trail; it does not carry the decision (F-3).';

-- The write-once guard. This is what decision 2 bought: the override becomes
-- a fact the DATABASE stamped, not a claim the application made about itself.
-- Same shape as v5.4.2-10's invoices.first_issued_at.
--
-- Pins public, pg_temp rather than '': this is a trigger function that reads
-- pg_roles and is called under RLS. A-23 (1c) now permits '' for trigger
-- functions, but the ~190 existing ones are not re-pinned and consistency
-- with its neighbours is worth more here than the pin.

CREATE OR REPLACE FUNCTION public.enforce_underreach_override_write_once() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_super boolean := (SELECT r.rolsuper FROM pg_roles r WHERE r.rolname = current_user);
    v_user  uuid;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- A target is never born overridden: the warning has not been raised
        -- yet, so there is nothing to override.
        IF NOT v_super AND (NEW.underreach_override_reason IS NOT NULL
                         OR NEW.underreach_override_at IS NOT NULL
                         OR NEW.underreach_override_by IS NOT NULL) THEN
            RAISE EXCEPTION USING
                MESSAGE = 'correction target: the under-reach override cannot be set at INSERT — the warning it answers is raised at gate (ii), after the target exists (R-27; v5.4.2-12)',
                ERRCODE = 'restrict_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- Write-once: once stamped, neither the reason, the stamp nor the actor moves.
    IF OLD.underreach_override_at IS NOT NULL AND NOT v_super
       AND (NEW.underreach_override_reason IS DISTINCT FROM OLD.underreach_override_reason
         OR NEW.underreach_override_at     IS DISTINCT FROM OLD.underreach_override_at
         OR NEW.underreach_override_by     IS DISTINCT FROM OLD.underreach_override_by) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s: the under-reach override is write-once — it was recorded at %s and cannot be changed or cleared (R-27, F-3; v5.4.2-12)', OLD.id, OLD.underreach_override_at),
            ERRCODE = 'restrict_violation';
    END IF;

    -- Setting it: the caller supplies the REASON only. The clock and the
    -- actor are the database's, so a caller cannot backdate its own override
    -- or attribute it to someone else.
    IF OLD.underreach_override_reason IS NULL AND NEW.underreach_override_reason IS NOT NULL THEN
        IF NOT v_super THEN
            -- The actor from the RLS session context, read the way every
            -- other stamping trigger in this schema reads it (tu.sql:13114):
            -- tolerate a missing or malformed GUC rather than failing the
            -- write, and record NULL when the caller set none.
            BEGIN
                v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
            EXCEPTION WHEN OTHERS THEN
                v_user := NULL;
            END;
            NEW.underreach_override_at := now();
            NEW.underreach_override_by := v_user;
        ELSE
            NEW.underreach_override_at := coalesce(NEW.underreach_override_at, now());
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_underreach_override_write_once() IS
    'A-2 (v5.4.2-12), R-27 / F-3. BEFORE INSERT OR UPDATE OF underreach_override_reason, underreach_override_at, underreach_override_by on correction_run_targets: a target is never born overridden; the caller supplies only the reason code and the database stamps the clock and the actor; once stamped nothing moves (superusers exempt for migrations). This is what makes the override a fact the gate can believe — an invoice_events row would not be, because tally_app can write that log itself.';

DROP TRIGGER IF EXISTS a_enforce_underreach_override_write_once ON public.correction_run_targets;
CREATE TRIGGER a_enforce_underreach_override_write_once
    BEFORE INSERT OR UPDATE OF underreach_override_reason, underreach_override_at, underreach_override_by
    ON public.correction_run_targets
    FOR EACH ROW EXECUTE FUNCTION public.enforce_underreach_override_write_once();


-- ----------------------------------------------------------------------------
-- 5. The setup-time log (F-1, Ryan's decision 3)
-- ----------------------------------------------------------------------------
-- R-19 and R-27 both specify appended event rows for cause changes and
-- under-reach overrides. invoice_events cannot hold them: its invoice_id is
-- NOT NULL (tu.sql:3252) and at correction-run setup the correction invoice
-- does not exist — correction_run_targets.correction_invoice_id stays NULL
-- until Phase 7. The only invoice in hand is the VOIDED ORIGINAL, and
-- attaching the correction's decisions to the original's event stream
-- conflates two bills' histories: a reader of the original's timeline would
-- find decisions about a bill that had not been written yet.
--
-- So the target gets its own log. Append-only in the strict sense — no
-- UPDATE, no DELETE, for anyone but a superuser.

CREATE TABLE IF NOT EXISTS public.correction_run_target_events (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    target_id           uuid NOT NULL,
    event_type          text NOT NULL,
    operator_id         uuid,
    occurred_at         timestamp with time zone DEFAULT now() NOT NULL,
    metadata            jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT correction_run_target_events_pkey PRIMARY KEY (id),
    CONSTRAINT correction_run_target_events_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT correction_run_target_events_target_fkey
        FOREIGN KEY (target_id, tenant_id)
        REFERENCES public.correction_run_targets(id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT correction_run_target_events_event_type_check
        CHECK ((event_type = ANY (ARRAY[
            'backbill_cause_set'::text,
            'backbill_cause_changed'::text,
            'underreach_warning_raised'::text,
            'underreach_override_recorded'::text,
            'read_classification_overridden'::text,
            'target_refused_beyond_cap'::text])))
);

CREATE INDEX IF NOT EXISTS idx_correction_run_target_events_tenant ON public.correction_run_target_events USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_correction_run_target_events_target ON public.correction_run_target_events USING btree (target_id, occurred_at);

ALTER TABLE public.correction_run_target_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.correction_run_target_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.correction_run_target_events;
CREATE POLICY tenant_isolation ON public.correction_run_target_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.correction_run_target_events IS
    'A-2 (v5.4.2-12), F-1. The append-only setup-time history of one correction_run_targets row: cause set and changed (R-19), under-reach warning raised and overridden (R-27), read classification overridden (R-30), target refused as wholly beyond the cap (R-22). It exists because these decisions are taken BEFORE any correction invoice does — invoice_events.invoice_id is NOT NULL and correction_invoice_id is NULL until Phase 7 — and hanging them on the voided original would conflate two bills'' histories. This log is the AUDIT TRAIL, not the guard''s fact: tally_app can write it, so what the gate believes is the write-once column on the target (F-3).';

-- Append-only: this log records what happened, and what happened does not
-- change afterwards. Superusers are exempt so a migration can still repair it.
CREATE OR REPLACE FUNCTION public.enforce_target_events_append_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_super boolean := (SELECT r.rolsuper FROM pg_roles r WHERE r.rolname = current_user);
BEGIN
    IF v_super THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = format('correction_run_target_events is append-only (v5.4.2-12): %s is refused', TG_OP),
        ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.enforce_target_events_append_only() IS
    'A-2 (v5.4.2-12). BEFORE UPDATE OR DELETE on correction_run_target_events: refused for everyone but a superuser. CI-014''s discipline for a log that a regulator may read years later.';

DROP TRIGGER IF EXISTS a_enforce_target_events_append_only ON public.correction_run_target_events;
CREATE TRIGGER a_enforce_target_events_append_only
    BEFORE UPDATE OR DELETE ON public.correction_run_target_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_target_events_append_only();


-- ----------------------------------------------------------------------------
-- 6. The invoice_events domain (F-2)
-- ----------------------------------------------------------------------------
-- Widened, not replaced. Two values, for the two things that happen to a
-- correction AFTER its invoice exists and therefore do belong on the
-- invoice's own timeline: the cap trimmed the bill, and the bill was refused
-- outright. The setup-time decisions stay on the target's log above.
--
-- D-2026-09-09-03: widening a CHECK is one line; narrowing means finding and
-- judging every row already routed under the loose rule.

ALTER TABLE public.invoice_events DROP CONSTRAINT IF EXISTS invoice_events_event_type_check;
ALTER TABLE public.invoice_events ADD CONSTRAINT invoice_events_event_type_check
    CHECK ((event_type = ANY (ARRAY['created'::text, 'sent'::text, 'held'::text, 'released_from_hold'::text, 'voided'::text, 'void_attempted_blocked'::text, 'correction_initiated'::text, 'correction_posted'::text, 'payment_applied'::text, 'written_off'::text, 'status_changed'::text, 'backbill_cap_trimmed'::text, 'backbill_cap_refused'::text])));


-- ----------------------------------------------------------------------------
-- 7. The read classification (R-30)
-- ----------------------------------------------------------------------------
-- (4)(E)(vii) turns on whether the failure to read was beyond the utility's
-- control. R-30 ruled that this is DERIVED FROM THE CONTEMPORANEOUS READ
-- RECORD wherever possible, on the reasoning that the field tech who could
-- not read the meter recorded why AT THE TIME, and that is better evidence
-- than a billing operator reconstructing it months later.
--
-- THE MAPPING IS PLATFORM-FIXED, NEVER TENANT-CONFIGURABLE. It is a reading
-- of the rule, not a business preference. A tenant able to reclassify
-- ami_offline as beyond its control would be granting itself a disconnection
-- right §7.45 does not give. That is why this is a function and not a table.
--
-- THE BUCKET ASSIGNMENTS ARE AN ENGINEERING PROPOSAL, NOT KYLE'S RULING.
-- Kyle ruled the mechanism and the default. The customer-side / utility-side
-- line on meter_buried, meter_obstructed, key_required and seasonal_closure
-- is arguably a question for tariff counsel and rides with the R-28/R-29
-- referral. Until then they sit in the third bucket, which is the safe
-- direction and costs only operator friction (refinement 3).
--
-- historical_average and same_period_prior_year are in the third bucket for a
-- different reason: they describe HOW the estimate was computed, not WHY the
-- read was missed, so a read carrying either has no recorded cause at all.
-- That conflation is R-30's separately-recorded schema defect and is NOT
-- fixed here.

CREATE OR REPLACE FUNCTION public.backbilling_read_classification(
        p_access_status     text,
        p_estimation_reason text)
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = pg_catalog, pg_temp
    AS $$
DECLARE
    -- Rank by CONSERVATISM, most protective first, so that "the more
    -- conservative bucket wins" is a max() and not a chain of IFs that can
    -- be got wrong. within_utility_control outranks determination_required:
    -- both yield 'never' today, but determination_required can be lifted by
    -- an operator basis and within_utility_control cannot.
    v_access text;
    v_reason text;
    v_rank_access int;
    v_rank_reason int;
    v_best int;
BEGIN
    -- access_status
    v_access := CASE p_access_status
        WHEN 'locked_gate'          THEN 'beyond_utility_control'
        WHEN 'aggressive_dog'       THEN 'beyond_utility_control'
        WHEN 'unsafe_conditions'    THEN 'beyond_utility_control'
        WHEN 'no_access_permission' THEN 'beyond_utility_control'
        WHEN 'ami_offline'          THEN 'within_utility_control'
        WHEN 'meter_damaged'        THEN 'within_utility_control'
        WHEN 'meter_not_found'      THEN 'within_utility_control'
        WHEN 'meter_buried'         THEN 'determination_required'
        WHEN 'meter_obstructed'     THEN 'determination_required'
        WHEN 'key_required'         THEN 'determination_required'
        WHEN 'other'                THEN 'determination_required'
        -- 'accessed' contributes nothing: the meter WAS read, so it carries
        -- no evidence about a failure to read. It must not be allowed to
        -- read as "beyond control" by omission.
        ELSE NULL
    END;

    -- estimation_reason. 'access_issue' DELEGATES: R-30's resolution rule is
    -- that where estimation_reason = 'access_issue' the classification is
    -- taken from access_status, which carries the detail.
    v_reason := CASE p_estimation_reason
        WHEN 'access_issue'               THEN NULL
        WHEN 'weather_prevented_read'     THEN 'beyond_utility_control'
        WHEN 'ami_sync_failure'           THEN 'within_utility_control'
        WHEN 'meter_malfunction'          THEN 'within_utility_control'
        WHEN 'new_meter_install'          THEN 'within_utility_control'
        WHEN 'prior_estimation_correction' THEN 'within_utility_control'
        WHEN 'seasonal_closure'           THEN 'determination_required'
        WHEN 'other'                      THEN 'determination_required'
        -- method, not cause — no recorded reason at all (R-30's defect)
        WHEN 'historical_average'         THEN 'determination_required'
        WHEN 'same_period_prior_year'     THEN 'determination_required'
        ELSE NULL
    END;

    v_rank_access := CASE v_access
        WHEN 'within_utility_control'  THEN 3
        WHEN 'determination_required'  THEN 2
        WHEN 'beyond_utility_control'  THEN 1
        ELSE NULL END;
    v_rank_reason := CASE v_reason
        WHEN 'within_utility_control'  THEN 3
        WHEN 'determination_required'  THEN 2
        WHEN 'beyond_utility_control'  THEN 1
        ELSE NULL END;

    v_best := greatest(coalesce(v_rank_access, 0), coalesce(v_rank_reason, 0));

    -- Nothing classifiable — including a period with no read row at all,
    -- which reaches here as (NULL, NULL). R-30: the standing default, not a
    -- fallback of last resort.
    IF v_best = 0 THEN
        RETURN 'determination_required';
    END IF;
    RETURN CASE v_best
        WHEN 3 THEN 'within_utility_control'
        WHEN 2 THEN 'determination_required'
        ELSE        'beyond_utility_control'
    END;
END;
$$;

COMMENT ON FUNCTION public.backbilling_read_classification(text, text) IS
    'A-2 (v5.4.2-12), R-30. Classifies one billing period''s contemporaneous read record into (4)(E)(vii)''s three buckets: beyond_utility_control (disconnection permitted for that period), within_utility_control (protection stands, enforceable_scope never), determination_required (never until an operator records a basis). PLATFORM-FIXED, never tenant-configurable — it is a reading of the rule, not a business preference, and a tenant able to reclassify ami_offline as beyond its control would be granting itself a disconnection right §7.45 does not give. Where estimation_reason = access_issue the classification is taken from access_status, which carries the detail; where the two disagree the more conservative bucket wins. (NULL, NULL) — a period with no read row — returns determination_required, R-30''s standing default. The bucket assignments for meter_buried, meter_obstructed, key_required and seasonal_closure are an ENGINEERING PROPOSAL riding with the R-28/R-29 counsel referral, not Kyle''s ruling; they sit in the safe third bucket meanwhile.';


-- ----------------------------------------------------------------------------
-- 8. The resolvers: which class, and which cap row (CCK-14, R-26)
-- ----------------------------------------------------------------------------
-- Both run with INVOKER rights and read tenant-scoped tables under RLS, so a
-- caller sees only its own tenant's configuration. Neither is SECURITY
-- DEFINER: nothing here needs to outrank the caller, and v5.4.2-11 spent five
-- review rounds removing definers that did.

CREATE OR REPLACE FUNCTION public.backbilling_customer_class(p_customer_id uuid)
    RETURNS text
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_mode text;
    v_type text;
BEGIN
    SELECT t.regulatory_class_mode, c.customer_type
      INTO v_mode, v_type
      FROM public.customers c
      JOIN public.tenants t ON t.id = c.tenant_id
     WHERE c.id = p_customer_id;

    IF v_mode IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling class: customer %s is not visible in this session', p_customer_id),
            ERRCODE = 'no_data_found',
            HINT = 'The customer must exist and be visible under this session''s tenant isolation.';
    END IF;

    IF v_mode = 'volumetric_threshold' THEN
        -- Declared in the CHECK so the CCK patch widens nothing, and refused
        -- here because its substrate (tenant_regulatory_class_rules,
        -- meter_regulatory_class_determinations) does not exist. Silently
        -- behaving like the default would be a guard failing open under a
        -- name that says otherwise.
        RAISE EXCEPTION USING
            MESSAGE = 'backbilling class: regulatory_class_mode = volumetric_threshold is not implemented — its resolver and determination record (CCK-4…CCK-13) ship in their own patch',
            ERRCODE = 'feature_not_supported',
            HINT = 'Set tenants.regulatory_class_mode to all_non_residential_protected (the v1 default) or explicit_class.';
    END IF;

    IF v_mode = 'all_non_residential_protected' THEN
        -- CCK-14. Residential is protected by statute; every non-residential
        -- account is swept in by the mode. So in v1 this is a constant — and
        -- deliberately so: it is correct for any tenant whose filed tariff
        -- has no size tier, it touches no rate calculation, and it fails
        -- toward protection. The cost is flexibility, never a violation.
        RETURN 'protected';
    END IF;

    -- explicit_class: trust the size-tier values on customer_type. §7.45
    -- reaches residential and SMALL commercial; a bare 'commercial' is
    -- ambiguous on this axis and is read as protected, the safe direction.
    RETURN CASE
        WHEN v_type IN ('residential', 'small_commercial', 'commercial') THEN 'protected'
        ELSE 'unprotected'
    END;
END;
$$;

COMMENT ON FUNCTION public.backbilling_customer_class(uuid) IS
    'A-2 (v5.4.2-12), CCK-14. Whether this customer sits inside 16 TAC §7.45''s protected class, per tenants.regulatory_class_mode. Under the v1 default all_non_residential_protected the answer is always protected — residential by statute, everything else by the mode — which errs toward protection and can never be a violation. Under explicit_class a bare commercial reads as protected, because that value is ambiguous on the size-tier axis and the safe direction is in-scope. volumetric_threshold RAISES: it is declared so the CCK patch widens no CHECK, and refused because its substrate does not exist — a mode that silently degraded to the default would be a guard failing open under a name that says otherwise.';


CREATE OR REPLACE FUNCTION public.backbilling_resolve_cap(
        p_tenant_id       uuid,
        p_jurisdiction_id uuid,
        p_service_type    text,
        p_customer_class  text,
        p_cause           text)
    RETURNS public.backbilling_cap_rules
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_rule public.backbilling_cap_rules;
BEGIN
    -- R-26: most-specific-wins over EXACTLY TWO LEVELS — the service
    -- location's jurisdiction, else the NULL-jurisdiction state /
    -- filed-tariff default. No deeper hierarchy, and no silent widening: an
    -- ORDER BY over a jurisdiction that does not match would quietly pick
    -- another city's rule, so the match is explicit.
    SELECT r.* INTO v_rule
      FROM public.backbilling_cap_rules r
     WHERE r.tenant_id      = p_tenant_id
       AND r.service_type   = p_service_type
       AND r.customer_class = p_customer_class
       AND r.cause          = p_cause
       AND (r.jurisdiction_id = p_jurisdiction_id
            OR r.jurisdiction_id IS NULL)
     ORDER BY (r.jurisdiction_id IS NULL)      -- false (specific) sorts first
     LIMIT 1;

    IF v_rule.id IS NULL THEN
        -- Fail CLOSED and loudly. An absent rule is not permission: the
        -- unprotected rows are seeded EXPLICITLY uncapped precisely so that
        -- nothing has to infer "no rule means no limit".
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: no rule for (service %s, class %s, cause %s) in this tenant — a correction cannot be evaluated against a cap that is not configured', p_service_type, p_customer_class, p_cause),
            ERRCODE = 'no_data_found',
            HINT = 'SELECT public.seed_backbilling_cap_defaults(<tenant_id>); — tenant onboarding must seed the statutory defaults. A tenant created after v5.4.2-12 has none until it does.';
    END IF;
    RETURN v_rule;
END;
$$;

COMMENT ON FUNCTION public.backbilling_resolve_cap(uuid, uuid, text, text, text) IS
    'A-2 (v5.4.2-12), R-26. Resolves the governing backbilling_cap_rules row, most-specific-wins over exactly two levels: the service location''s jurisdiction, else the NULL-jurisdiction state / filed-tariff default. RAISES where no rule resolves rather than returning NULL — an absent rule is not permission, which is why the unprotected rows are seeded explicitly uncapped. Municipal rows are admitted only where the tenant operates under a lawfully established differing municipal standard evidenced by an ordinance or filed instrument, never created speculatively per franchise city.';


-- ----------------------------------------------------------------------------
-- 8b. What the customer is actually charged (review round 1, CRITICAL)
-- ----------------------------------------------------------------------------
-- BOTH reviewers found this independently, which by this project's own rule
-- makes it near-certain. The first draft took the bill's total from
-- `invoices.amount_due`. That column is a caller-set denormalised field:
-- nothing in tu.sql's 21,916 lines derives it from `invoice_line_items`, no
-- trigger sums the lines into it, and the calculation snapshot pins line ids
-- and amounts but never a total. The only place the schema itself computes a
-- bill total is a reporting view, and it does it as sum(line_items.amount)
-- (tu.sql:19713).
--
-- So every arithmetic test in the first draft's gate read a number the caller
-- set, on BOTH sides of the comparison. Reproduced: a correction carrying
-- `amount_due` 100.00 and a single line item of 5,000.00 evaluated as
-- `neutral, delta 0.00` and issued clean; so did a "reduction" to 99.00 with
-- the same 5,000.00 line.
--
-- BUT THE LINE ITEMS ALONE ARE NOT THE ANSWER EITHER, and the first round-2
-- draft of this function proved it by reading only them. `amount_due` is what
-- posts to the ledger — void_invoice() reverses exactly `-(amount_due)`
-- (tu.sql:1276) — so it lands on the customer's account whatever the lines
-- say. Reading the lines alone closed one direction and opened its mirror: a
-- correction with honest $105 of itemised lines and `amount_due` set to
-- $5,000 issued clean.
--
-- TWO PATHS, SO THE MEASURE IS THE GREATER OF THE TWO: the most the customer
-- can be exposed to by either route. Inflating either one raises it, and the
-- raised figure then has to match the evidence, so neither path is a way
-- around the window.
--
-- Requiring the two to be EQUAL was tried and rejected: the existing
-- corpus carries `amount_due = 0` against non-zero lines (there is no billing
-- engine to maintain it), so an equality rule refused bills the earlier
-- patches' own batteries build — it broke battery-10 and battery-11 on
-- measurement, not on argument. The invariant that they should agree belongs
-- to the invoice, not to A-2; it is recorded as residual R9.
--
-- `amount_due` having no tie to the lines is a PRE-EXISTING schema defect,
-- not one A-2 introduced — but A-2 is the first thing to rest a statutory
-- gate on a bill total, so it is recorded for the register rather than
-- silently worked around (residual R9).

CREATE OR REPLACE FUNCTION public.backbilling_invoice_charge(p_invoice_id uuid)
    RETURNS numeric
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT greatest(
             (SELECT coalesce(sum(l.amount), 0) FROM public.invoice_line_items l
               WHERE l.invoice_id = p_invoice_id),
             (SELECT coalesce(i.amount_due, 0) FROM public.invoices i
               WHERE i.id = p_invoice_id)
           )::numeric(12,2);
$$;

COMMENT ON FUNCTION public.backbilling_invoice_charge(uuid) IS
    'A-2 (v5.4.2-12). What this invoice can charge the customer, by either path: the GREATER of its line-item sum and its amount_due. Two numbers are both the money and nothing ties them together — the lines are the itemised content (6)(B)(v) requires a backbill to break down, amount_due is what posts to the ledger (void_invoice reverses exactly -(amount_due), tu.sql:1276). Both round-1 reviewers found the first draft resting the statutory gate on amount_due alone; reading the lines alone was the same defect mirrored, and reproduced. Taking the greater means inflating either path raises the measured charge, which must then match the evidence. Equality was tried and rejected on measurement: the existing corpus carries amount_due = 0 against non-zero lines, so requiring agreement refused bills the earlier patches'' own batteries build. Runs invoker-rights.';

-- ----------------------------------------------------------------------------
-- 9. The per-period evidence record (R-25, R-29, R-30)
-- ----------------------------------------------------------------------------
-- R-25 is the STRUCTURAL ruling of this patch: direction is tested PER
-- ORIGINAL BILLING PERIOD, not per invoice. Periods where the customer owes
-- more are capped and trimmed if outside the window; periods where the
-- customer is OWED money always pass, uncapped.
--
-- The rejected alternatives are worth carrying, because each names a failure
-- this shape avoids:
--   * NETTING PER INVOICE lets time-barred charges ride into a bill hidden
--     behind favourable months — the customer pays for a period the statute
--     put out of reach, and the arithmetic conceals it.
--   * OPERATOR-DECLARED DIRECTION is a computed fact dressed as a judgment
--     call.
--   * SUPPRESSING ADVERSE DELTAS WITHOUT PERIOD STRUCTURE leaves no clean way
--     to present the result against (6)(B)(v)'s per-billing-unit requirement.
--
-- This record is CI-008's uniform-evaluation evidence, and it is what makes a
-- trim defensible eighteen months later.

-- Monotonic within and across transactions, so "the evaluation that governs"
-- is a fact rather than a coin toss. GRANTed explicitly: a sequence default
-- under SET ROLE tally_app fails without USAGE, and the blanket ALTER DEFAULT
-- PRIVILEGES in tu.sql covers TABLES, not SEQUENCES.
CREATE SEQUENCE IF NOT EXISTS public.backbilling_period_evaluations_seq;
GRANT USAGE, SELECT ON SEQUENCE public.backbilling_period_evaluations_seq TO tally_app;

CREATE TABLE IF NOT EXISTS public.backbilling_period_evaluations (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    target_id               uuid NOT NULL,
    period_start            date NOT NULL,
    period_end              date NOT NULL,
    direction               text NOT NULL,
    delta_amount            numeric(12,2) NOT NULL,
    cap_rule_id             uuid NOT NULL,
    jurisdiction_level      text NOT NULL,
    cause                   text NOT NULL,
    anchor_date             date NOT NULL,
    anchor_basis            text NOT NULL,
    billable_scope          text NOT NULL,
    window_start            date,
    enforceable_scope       text NOT NULL,
    enforceable_months      integer,
    read_classification     text,
    read_id                 uuid,
    meter_id                uuid,
    last_test_date_used     date,
    trimmed                 boolean DEFAULT false NOT NULL,
    trimmed_amount          numeric(12,2) DEFAULT 0.00 NOT NULL,
    underreach_warning      boolean DEFAULT false NOT NULL,
    underreach_override_reason text,
    evaluated_at            timestamp with time zone DEFAULT now() NOT NULL,
    evaluation_seq          bigint DEFAULT nextval('public.backbilling_period_evaluations_seq') NOT NULL,
    CONSTRAINT backbilling_period_evaluations_pkey PRIMARY KEY (id),
    CONSTRAINT backbilling_period_evaluations_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT backbilling_period_evaluations_target_fkey
        FOREIGN KEY (target_id, tenant_id)
        REFERENCES public.correction_run_targets(id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT backbilling_period_evaluations_cap_rule_fkey
        FOREIGN KEY (cap_rule_id, tenant_id)
        REFERENCES public.backbilling_cap_rules(id, tenant_id),
    CONSTRAINT backbilling_period_evaluations_read_fkey
        FOREIGN KEY (read_id, tenant_id)
        REFERENCES public.meter_readings(id, tenant_id),
    -- DELIBERATELY NOT UNIQUE on (target_id, period_start, period_end). A
    -- draft moves while it is worked, and gate (iii) refuses to issue on an
    -- evaluation that no longer describes the bill — so RE-EVALUATION is a
    -- normal part of the flow, and on an append-only table a re-evaluation is
    -- a new row. A unique key here would have made the two rules
    -- contradictory: the gate demands a fresh answer, the table forbids
    -- editing the old one, and the constraint forbids adding one, so a
    -- changed draft could never be issued at all. (Caught by battery I2.)
    --
    -- Which row governs is not left to chance: evaluation_seq is monotonic
    -- and the gate reads the highest. now() is constant within a
    -- transaction, so ordering on evaluated_at would be a tie — and a tie
    -- here silently picks one of two different answers.
    CONSTRAINT backbilling_period_evaluations_period_check
        CHECK ((period_end >= period_start)),
    CONSTRAINT backbilling_period_evaluations_direction_check
        CHECK ((direction = ANY (ARRAY['customer_owes'::text, 'customer_owed'::text, 'neutral'::text]))),
    CONSTRAINT backbilling_period_evaluations_jurisdiction_level_check
        CHECK ((jurisdiction_level = ANY (ARRAY['municipal'::text, 'state_default'::text]))),
    CONSTRAINT backbilling_period_evaluations_cause_check
        CHECK ((cause = ANY (ARRAY['non_registering_meter'::text, 'meter_error'::text, 'rate_misapplication'::text, 'estimation_catchup'::text, 'tampering_theft'::text]))),
    CONSTRAINT backbilling_period_evaluations_anchor_basis_check
        CHECK ((anchor_basis = ANY (ARRAY['test_date'::text, 'discovery_date'::text, 'tariff_specified'::text]))),
    CONSTRAINT backbilling_period_evaluations_billable_scope_check
        CHECK ((billable_scope = ANY (ARRAY['uncapped'::text, 'months_from_anchor'::text, 'shorter_of_months_or_last_test'::text]))),
    CONSTRAINT backbilling_period_evaluations_enforceable_scope_check
        CHECK ((enforceable_scope = ANY (ARRAY['uncapped'::text, 'months'::text, 'never'::text, 'conditional_on_read_classification'::text]))),
    CONSTRAINT backbilling_period_evaluations_read_classification_check
        CHECK ((read_classification IS NULL OR (read_classification = ANY (ARRAY['beyond_utility_control'::text, 'within_utility_control'::text, 'determination_required'::text])))),
    -- An uncapped scope has no window; a counted scope must have computed one.
    -- Left as two implications rather than an equivalence on purpose: the
    -- window is genuinely absent under uncapped, and present otherwise.
    CONSTRAINT backbilling_period_evaluations_window_check
        CHECK ((((billable_scope = 'uncapped'::text) AND (window_start IS NULL))
             OR ((billable_scope <> 'uncapped'::text) AND (window_start IS NOT NULL)))),
    -- A trim must carry its amount, and an untrimmed period must not claim one.
    CONSTRAINT backbilling_period_evaluations_trim_check
        CHECK (((trimmed AND (trimmed_amount <> (0)::numeric)) OR ((NOT trimmed) AND (trimmed_amount = (0)::numeric)))),
    -- An override reason without the warning it answers is a record of
    -- nothing; it would read as an override of a duty that never attached.
    CONSTRAINT backbilling_period_evaluations_override_check
        CHECK (((underreach_override_reason IS NULL) OR underreach_warning))
);

CREATE INDEX IF NOT EXISTS idx_backbilling_period_evaluations_tenant ON public.backbilling_period_evaluations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_backbilling_period_evaluations_target ON public.backbilling_period_evaluations USING btree (target_id, period_start, period_end, evaluation_seq DESC);

ALTER TABLE public.backbilling_period_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backbilling_period_evaluations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.backbilling_period_evaluations;
CREATE POLICY tenant_isolation ON public.backbilling_period_evaluations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.backbilling_period_evaluations IS
    'A-2 (v5.4.2-12), R-25. One append-only row per ORIGINAL billing period evaluated by a correction — the structural ruling of A-2: direction is tested per period, never per invoice. Periods where the customer owes more are capped and trimmed if outside the window; periods where the customer is OWED money always pass, uncapped. Netting per invoice was rejected because it lets time-barred charges ride into a bill hidden behind favourable months. Each row carries the governing cap rule, the direction and delta found, the computed window and the anchor used, the jurisdiction level that resolved (R-26), the R-30 read classification with the read row it came from, whether the period was trimmed and by how much, and the under-reach warning state with any override (R-27). This is CI-008''s uniform-evaluation evidence, and it is what makes a trim defensible eighteen months later.';

COMMENT ON COLUMN public.backbilling_period_evaluations.anchor_basis IS
    'R-29. Which reading produced the window, so that a reversal is a re-resolution rather than archaeology. HARD-CODED to test_date in v1 — no operator choice and no tenant setting; discovery_date and tariff_specified are declared so a later patch widens no CHECK.';

COMMENT ON COLUMN public.backbilling_period_evaluations.evaluation_seq IS
    'Which evaluation governs. A period may be evaluated more than once — a draft moves while it is worked and gate (iii) refuses stale evidence — and on an append-only table each re-evaluation is a new row, so the gate reads the HIGHEST seq. Not evaluated_at: now() is constant within a transaction, so two evaluations in one transaction would tie and the gate would silently pick one of two different answers.';

COMMENT ON COLUMN public.backbilling_period_evaluations.direction IS
    'R-25. Which way this period moves for the CUSTOMER. customer_owes = the correction increases what they owe, so the cap applies. customer_owed = the correction returns money, which always passes uncapped — a limit on refunding a customer is not what §7.45 is for. neutral = no change.';

COMMENT ON COLUMN public.backbilling_period_evaluations.meter_id IS
    'Which meter''s test date produced the window, and (with last_test_date_used) the two facts the trim turns on. Recorded because meters.last_test_date is a single MUTABLE field: without these the window on an eighteen-month-old evidence row cannot be re-derived, which is the whole purpose of the record (round 1, HIGH).';

COMMENT ON COLUMN public.backbilling_period_evaluations.last_test_date_used IS
    'The meter''s recorded last test date AT THE MOMENT OF EVALUATION. meters.last_test_date is overwritten by each test, so the value that produced this window is not recoverable later from the meter row. See also the Q-D question with Kyle: whether "the last test" means this test or the last one that found the meter ACCURATE.';

COMMENT ON COLUMN public.backbilling_period_evaluations.read_id IS
    'The contemporaneous read row the R-30 classification came from (v5.4.2-12). NULL where the period has no read row at all, which R-30 classifies as determination_required — the standing default, not a fallback of last resort.';

-- Append-only, for the same reason as the target log: a regulator may read it
-- years later and it must say what was decided at the time.
CREATE OR REPLACE FUNCTION public.enforce_period_evaluations_append_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_super boolean := (SELECT r.rolsuper FROM pg_roles r WHERE r.rolname = current_user);
BEGIN
    IF v_super THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = format('backbilling_period_evaluations is append-only (v5.4.2-12): %s is refused — a re-evaluation is a new row, not an edit of the old answer', TG_OP),
        ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.enforce_period_evaluations_append_only() IS
    'A-2 (v5.4.2-12). BEFORE UPDATE OR DELETE on backbilling_period_evaluations: refused for everyone but a superuser. The evidence record is what a trim is defended with; an editable one defends nothing.';

DROP TRIGGER IF EXISTS a_enforce_period_evaluations_append_only ON public.backbilling_period_evaluations;
CREATE TRIGGER a_enforce_period_evaluations_append_only
    BEFORE UPDATE OR DELETE ON public.backbilling_period_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_period_evaluations_append_only();


-- ----------------------------------------------------------------------------
-- 10. The window (R-20's three shapes, R-31's hard constraint)
-- ----------------------------------------------------------------------------
-- window_start is the EARLIEST date the billable bound reaches back to. A
-- period ending before it is wholly beyond the cap; a period straddling it is
-- trimmed to the part at or after it.
--
-- "The SHORTER of six months and the last test" means the LATER of the two
-- candidate start dates: a shorter reach starts later. Getting that backwards
-- reads as a longer reach and over-collects, which is the expensive
-- direction, so both sides of the comparison are pinned in the battery.
--
-- R-31'S HARD CONSTRAINT, WHICH BINDS THIS PATCH AND NOT ONLY CI-091:
-- NEVER DERIVE A TEST DATE FROM test_interval_months. Back-computing a
-- plausible last-test date manufactures evidence for the exact figure a
-- dispute will contest. Where the meter carries no recorded test date and the
-- period is adverse, this function REFUSES rather than guessing — see the
-- residual note in the tail.

CREATE OR REPLACE FUNCTION public.backbilling_window_start(
        p_billable_scope  text,
        p_billable_months integer,
        p_anchor_date     date,
        p_last_test_date  date,
        p_direction       text)
    RETURNS date
    LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = pg_catalog, pg_temp
    AS $$
DECLARE
    v_by_months date;
BEGIN
    IF p_billable_scope = 'uncapped' THEN
        RETURN NULL;                       -- no §7.45 billing limit for this cause
    END IF;

    v_by_months := p_anchor_date - make_interval(months => p_billable_months);

    IF p_billable_scope = 'months_from_anchor' THEN
        RETURN v_by_months;
    END IF;

    -- shorter_of_months_or_last_test — (7)(B)(v)(I)
    IF p_last_test_date IS NULL THEN
        -- A favourable period is uncapped anyway (R-25), so the missing test
        -- date cannot hurt the customer there and the months bound stands.
        IF p_direction <> 'customer_owes' THEN
            RETURN v_by_months;
        END IF;
        -- Adverse, and the meter has no recorded test. Reaching the full six
        -- months over-collects wherever an unrecorded test sits inside the
        -- window, and reversing that means refunds rather than a patch
        -- (refinement 5, Kyle's reasoning). Refuse; do NOT infer a date.
        RAISE EXCEPTION USING
            MESSAGE = 'backbilling window: this meter has no recorded last test date, so the (7)(B)(v)(I) window cannot be computed for a period that increases what the customer owes',
            ERRCODE = 'no_data_found',
            HINT = 'Record the meter''s last test date. It must NOT be derived from test_interval_months (R-31): back-computing a plausible test date manufactures evidence for the exact figure a dispute will contest.';
    END IF;

    -- The SHORTER window is the LATER start.
    RETURN greatest(v_by_months, p_last_test_date);
END;
$$;

COMMENT ON FUNCTION public.backbilling_window_start(text, integer, date, date, text) IS
    'A-2 (v5.4.2-12), R-20. The earliest date the billable bound reaches back to; NULL under uncapped. months_from_anchor counts back from the anchor. shorter_of_months_or_last_test returns the LATER of (anchor - months) and the last test date, because a shorter reach starts later — reading that backwards over-collects. Where the meter has no recorded test date the months bound stands for a favourable period (uncapped anyway under R-25) and the function REFUSES for an adverse one: R-31 forbids deriving a test date from test_interval_months, because back-computing one manufactures evidence for the exact figure a dispute will contest.';


-- ----------------------------------------------------------------------------
-- 11. Gate (ii) — correction-run setup (R-22, R-27)
-- ----------------------------------------------------------------------------
-- The coarse pre-check. Refuse the target where the ENTIRE original period
-- sits beyond the billable bound — there is nothing left to bill, so letting
-- setup proceed only defers the refusal to a point where more work has been
-- done. Otherwise raise the under-reach warning where it applies.
--
-- AFTER, not BEFORE: this gate appends to correction_run_target_events, whose
-- foreign key needs the target row to exist. A BEFORE INSERT trigger would
-- have nothing to point at.
--
-- The under-reach warning is a SINGLE-CAUSE guard — meter_error only —
-- because (7)(B)(v)(I) is the only MANDATORY bound. (v)(II) is permissive on
-- its face and the other three causes are billable-uncapped, so there is no
-- window to fall short of. A warning on those would be noise that teaches
-- operators to dismiss the one that matters.
--
-- Direction is not known at setup — no correction lines exist yet — so the
-- window is computed on the favourable branch, which yields the LONGEST
-- window the cap can produce. A refusal against the longest window is a
-- refusal against every shorter one, so this cannot refuse a target that
-- gate (iii) would have allowed.

CREATE OR REPLACE FUNCTION public.enforce_backbilling_gate_setup() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv           record;
    v_inv_id        uuid;
    v_meter         record;
    v_class         text;
    v_jurisdiction  uuid;
    v_rule          public.backbilling_cap_rules;
    v_window        date;
BEGIN
    -- A correction with no statutory cause is a clerical re-issue. It is
    -- bounded at gate (iii) instead, where it may only REDUCE what is owed.
    IF NEW.backbill_cause IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT i.period_start, i.period_end, i.invoice_number, i.customer_id, i.location_id
      INTO v_inv
      FROM public.invoices i
     WHERE i.id = NEW.voided_invoice_id AND i.tenant_id = NEW.tenant_id;
    IF v_inv IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s: the voided invoice is not visible in this session', NEW.id),
            ERRCODE = 'no_data_found';
    END IF;

    v_inv_id := NEW.voided_invoice_id;

    -- THE TARGET MUST DESCRIBE THE BILL IT CORRECTS (review round 1, HIGH).
    -- correction_run_targets.customer_id and meter_id are plain foreign keys
    -- to customers(id) and meters(id); nothing tied either to the voided
    -- invoice. Both choose the cap, so both were levers:
    --
    --   * the METER supplies last_test_date, which sets the (7)(B)(v)(I)
    --     window. Reproduced: the same voided December bill was REFUSED on
    --     the meter that actually served it and ACCEPTED on a sibling meter
    --     at the same location with an older test date.
    --   * the CUSTOMER supplies the protected class. Reproduced under
    --     explicit_class: naming a large-commercial customer on a
    --     residential customer's bill resolved `unprotected`, which is
    --     billable-uncapped, and a $5,000 correction issued against the
    --     residential customer. Dormant under the v1 default mode, live the
    --     day a tenant switches modes — which is exactly the kind of
    --     latent-until-a-setting-moves defect this project keeps finding.
    IF NEW.customer_id IS DISTINCT FROM v_inv.customer_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s: names customer %s but invoice %s was billed to %s — the target''s customer decides the §7.45 protected class, so it must be the bill''s own customer', NEW.id, NEW.customer_id, v_inv.invoice_number, v_inv.customer_id),
            ERRCODE = 'restrict_violation';
    END IF;

    -- The meter must be one the voided bill actually billed. Where that bill
    -- named no meter on any line (a bill with only non-metered charges), fall
    -- back to requiring the meter serve the bill's premise — refusing
    -- outright would brick a legitimate correction, and the premise is the
    -- narrowest fact still available.
    IF EXISTS (SELECT 1 FROM public.invoice_line_items l
                WHERE l.invoice_id = v_inv_id AND l.meter_id IS NOT NULL) THEN
        IF NOT EXISTS (SELECT 1 FROM public.invoice_line_items l
                        WHERE l.invoice_id = v_inv_id AND l.meter_id = NEW.meter_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('correction target %s: names meter %s, which invoice %s did not bill — the meter''s last test date sets the billable window, so it must be a meter the bill actually charged for', NEW.id, NEW.meter_id, v_inv.invoice_number),
                ERRCODE = 'restrict_violation';
        END IF;
    ELSIF v_inv.location_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.meters m
                        WHERE m.id = NEW.meter_id AND m.tenant_id = NEW.tenant_id
                          AND m.location_id = v_inv.location_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('correction target %s: invoice %s billed no meter, and meter %s does not serve that bill''s premise', NEW.id, v_inv.invoice_number, NEW.meter_id),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;

    SELECT m.service_type, m.last_test_date INTO v_meter
      FROM public.meters m
     WHERE m.id = NEW.meter_id AND m.tenant_id = NEW.tenant_id;
    IF v_meter IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s: the meter is not visible in this session', NEW.id),
            ERRCODE = 'no_data_found';
    END IF;

    v_class := public.backbilling_customer_class(NEW.customer_id);

    -- The premise's jurisdiction, where the target names one. NULL resolves
    -- to the state / filed-tariff default row (R-26).
    SELECT sl.jurisdiction_id INTO v_jurisdiction
      FROM public.service_locations sl
     WHERE sl.id = NEW.location_id AND sl.tenant_id = NEW.tenant_id;

    v_rule := public.backbilling_resolve_cap(
        NEW.tenant_id, v_jurisdiction, v_meter.service_type, v_class, NEW.backbill_cause);

    v_window := public.backbilling_window_start(
        v_rule.billable_scope, v_rule.billable_months, NEW.anchor_date,
        v_meter.last_test_date, 'customer_owed');

    -- The whole period is out of reach. R-23 trims rather than rejects, but a
    -- trim that removes everything is a rejection, and saying so here is
    -- clearer than issuing a correction for nothing.
    IF v_window IS NOT NULL AND v_inv.period_end < v_window THEN
        INSERT INTO public.correction_run_target_events
            (tenant_id, target_id, event_type, metadata)
        VALUES (NEW.tenant_id, NEW.id, 'target_refused_beyond_cap',
                jsonb_build_object('cause', NEW.backbill_cause,
                                   'anchor_date', NEW.anchor_date,
                                   'window_start', v_window,
                                   'period_start', v_inv.period_start,
                                   'period_end', v_inv.period_end,
                                   'cap_rule_id', v_rule.id));
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: invoice %s covers %s..%s, which is wholly before the %s window opening %s — there is nothing within the billable bound to correct (16 TAC 7.45; %s)', v_inv.invoice_number, v_inv.period_start, v_inv.period_end, NEW.backbill_cause, v_window, v_rule.source_note),
            ERRCODE = 'restrict_violation';
    END IF;

    -- The under-reach warning (R-27). The corrected period begins after the
    -- mandatory window opened, so in-window periods earlier than this one are
    -- going uncorrected — the utility is reaching back less far than
    -- (7)(B)(v)(I) requires where a meter over-registered.
    IF NEW.backbill_cause = 'meter_error'
       AND v_window IS NOT NULL
       AND v_inv.period_start > v_window
       AND NEW.underreach_override_reason IS NULL THEN
        INSERT INTO public.correction_run_target_events
            (tenant_id, target_id, event_type, metadata)
        VALUES (NEW.tenant_id, NEW.id, 'underreach_warning_raised',
                jsonb_build_object('window_start', v_window,
                                   'period_start', v_inv.period_start,
                                   'anchor_date', NEW.anchor_date,
                                   'cap_rule_id', v_rule.id));
        RAISE WARNING 'backbilling under-reach: the (7)(B)(v)(I) window for invoice % opens %, but this correction begins % — periods between those dates are not being corrected. Where the meter over-registered the correction is MANDATORY back to the window; record an evidentiary-impossibility override on the target if it genuinely cannot be made (R-27).', v_inv.invoice_number, v_window, v_inv.period_start;
    END IF;

    -- Log the cause itself, so the target's history says when the finding was
    -- made and what it was. TG_OP tells set from changed.
    INSERT INTO public.correction_run_target_events
        (tenant_id, target_id, event_type, metadata)
    VALUES (NEW.tenant_id, NEW.id,
            CASE WHEN TG_OP = 'INSERT' OR OLD.backbill_cause IS NULL
                 THEN 'backbill_cause_set' ELSE 'backbill_cause_changed' END,
            jsonb_build_object('cause', NEW.backbill_cause,
                               'previous_cause', CASE WHEN TG_OP = 'UPDATE' THEN OLD.backbill_cause END,
                               'anchor_date', NEW.anchor_date,
                               'window_start', v_window,
                               'cap_rule_id', v_rule.id,
                               'customer_class', v_class,
                               'jurisdiction_level', CASE WHEN v_rule.jurisdiction_id IS NULL THEN 'state_default' ELSE 'municipal' END));
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.enforce_backbilling_gate_setup() IS
    'A-2 (v5.4.2-12), gate (ii) — R-22 / R-27. AFTER INSERT OR UPDATE OF backbill_cause, anchor_date on correction_run_targets. Refuses a target whose entire original period sits before the billable window, and raises the under-reach warning where a meter_error correction begins after the (7)(B)(v)(I) window opened — a SINGLE-CAUSE guard, because (v)(I) is the only mandatory bound: (v)(II) is permissive on its face and the other three causes are billable-uncapped. Direction is unknown at setup, so the window is computed on the favourable branch, which yields the LONGEST window the cap can produce — a refusal against it is a refusal against every shorter one. AFTER rather than BEFORE because it appends to correction_run_target_events, whose foreign key needs the target to exist. A target with no cause returns immediately; it is bounded at gate (iii), where it may only reduce what is owed.';

DROP TRIGGER IF EXISTS z_enforce_backbilling_gate_setup ON public.correction_run_targets;
CREATE TRIGGER z_enforce_backbilling_gate_setup
    AFTER INSERT OR UPDATE OF backbill_cause, anchor_date ON public.correction_run_targets
    FOR EACH ROW EXECUTE FUNCTION public.enforce_backbilling_gate_setup();


-- ----------------------------------------------------------------------------
-- 12. The per-period evaluation (R-25, R-23, R-29, R-30)
-- ----------------------------------------------------------------------------
-- What the billing engine calls, once per (target, original period), before
-- the correction invoice may be issued. It writes the evidence row gate (iii)
-- then checks.
--
-- THE STRADDLE, AND WHAT IS NOT RULED. R-25 makes the ORIGINAL BILLING PERIOD
-- the unit of evaluation, and R-23 says the rebill proceeds for the permitted
-- window with the out-of-bounds remainder forfeited. Between them they settle
-- the two clean cases — a period wholly at or after window_start is billable
-- in full, a period wholly before it is forfeited in full — and leave the
-- STRADDLING period unaddressed, because a period that begins before the
-- window opens and ends after it is partly billable and partly not.
--
-- This patch prorates the adverse delta by DAYS: the forfeited share is the
-- days before window_start over the days in the period. That assumes uniform
-- consumption across the period, which for gas is false — a January period
-- straddling a window is not consumed evenly across its days. It is the only
-- method available without per-day reads, it errs in no consistent direction,
-- and it is therefore RECORDED AS AN OPEN QUESTION for Kyle and tariff
-- counsel rather than presented as settled. The alternatives are to forfeit
-- the whole straddling period (protective, over-forfeits) or to bill it whole
-- (over-collects, and over-collection is the direction §7.45 exists to stop).
-- The evidence row carries the window and the trimmed amount either way, so
-- changing this rule later is a re-evaluation, not archaeology.

CREATE OR REPLACE FUNCTION public.backbilling_evaluate_period(
        p_target_id             uuid,
        p_correction_invoice_id uuid)
    RETURNS uuid
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_t             record;
    v_orig          record;
    v_corr          record;
    v_meter         record;
    v_class         text;
    v_jurisdiction  uuid;
    v_rule          public.backbilling_cap_rules;
    v_window        date;
    v_delta         numeric(12,2);
    v_direction     text;
    v_read          record;
    v_classification text;
    v_trimmed       boolean := false;
    v_trim_amount   numeric(12,2) := 0.00;
    v_days_total    integer;
    v_days_out      integer;
    v_id            uuid;
BEGIN
    SELECT t.* INTO v_t FROM public.correction_run_targets t WHERE t.id = p_target_id;
    IF v_t IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling evaluation: correction target %s is not visible in this session', p_target_id),
            ERRCODE = 'no_data_found';
    END IF;
    IF v_t.backbill_cause IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling evaluation: correction target %s has no backbill_cause — there is no statutory window to evaluate against', p_target_id),
            ERRCODE = 'invalid_parameter_value',
            HINT = 'Set backbill_cause and anchor_date on the target first. A correction with no cause may only REDUCE what the customer owes, and needs no evaluation.';
    END IF;

    SELECT i.period_start, i.period_end, i.invoice_number, i.customer_id,
           public.backbilling_invoice_charge(i.id) AS charge INTO v_orig
      FROM public.invoices i WHERE i.id = v_t.voided_invoice_id AND i.tenant_id = v_t.tenant_id;
    SELECT i.replaces_invoice_id, i.billing_run_id,
           public.backbilling_invoice_charge(i.id) AS charge INTO v_corr
      FROM public.invoices i WHERE i.id = p_correction_invoice_id AND i.tenant_id = v_t.tenant_id;
    IF v_orig IS NULL OR v_corr IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'backbilling evaluation: the original or the correction invoice is not visible in this session',
            ERRCODE = 'no_data_found';
    END IF;
    -- The correction must be the one this target names, or the evidence row
    -- would describe a window some other bill claims.
    IF v_corr.replaces_invoice_id IS DISTINCT FROM v_t.voided_invoice_id
       OR v_corr.billing_run_id   IS DISTINCT FROM v_t.billing_run_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling evaluation: invoice %s does not replace this target''s voided invoice on this target''s run', p_correction_invoice_id),
            ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT m.service_type, m.last_test_date INTO v_meter
      FROM public.meters m WHERE m.id = v_t.meter_id AND m.tenant_id = v_t.tenant_id;
    -- Gate (ii) checks this; the evaluator did not, so an invisible meter
    -- reached the resolver with a NULL service_type and failed there with a
    -- misleading "no rule for (service <NULL> ...)" (round 1, LOW).
    IF v_meter IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling evaluation: the target''s meter is not visible in this session (target %s)', p_target_id),
            ERRCODE = 'no_data_found';
    END IF;
    v_class := public.backbilling_customer_class(v_t.customer_id);
    SELECT sl.jurisdiction_id INTO v_jurisdiction
      FROM public.service_locations sl WHERE sl.id = v_t.location_id AND sl.tenant_id = v_t.tenant_id;

    v_rule := public.backbilling_resolve_cap(
        v_t.tenant_id, v_jurisdiction, v_meter.service_type, v_class, v_t.backbill_cause);

    -- R-25's direction test, from the DATABASE's arithmetic rather than an
    -- operator's declaration: a computed fact dressed as a judgment call was
    -- one of the rejected alternatives.
    -- From the LINE ITEMS on both sides (round 1, CRITICAL): amount_due is
    -- caller-set and tied to nothing.
    v_delta := coalesce(v_corr.charge, 0) - coalesce(v_orig.charge, 0);
    v_direction := CASE WHEN v_delta > 0 THEN 'customer_owes'
                        WHEN v_delta < 0 THEN 'customer_owed'
                        ELSE 'neutral' END;

    v_window := public.backbilling_window_start(
        v_rule.billable_scope, v_rule.billable_months, v_t.anchor_date,
        v_meter.last_test_date, v_direction);

    -- R-30: the contemporaneous read for this period, and its classification.
    -- Most recent read within the original period; NULL where there is none,
    -- which classifies as determination_required.
    SELECT mr.id, mr.access_status, mr.estimation_reason INTO v_read
      FROM public.meter_readings mr
     WHERE mr.tenant_id = v_t.tenant_id
       AND mr.meter_id  = v_t.meter_id
       AND mr.reading_date BETWEEN v_orig.period_start AND v_orig.period_end
     ORDER BY mr.reading_date DESC
     LIMIT 1;
    v_classification := public.backbilling_read_classification(v_read.access_status, v_read.estimation_reason);

    -- R-25: a period where the customer is OWED money always passes, uncapped.
    -- A limit on refunding a customer is not what §7.45 is for.
    IF v_direction = 'customer_owes' AND v_window IS NOT NULL THEN
        IF v_orig.period_end < v_window THEN
            -- Wholly outside: the entire adverse delta is forfeited.
            v_trimmed := true;
            v_trim_amount := v_delta;
        ELSIF v_orig.period_start < v_window THEN
            -- Straddling. See the note above: day-proration, stated as an
            -- approximation and carried to Kyle as an open question.
            v_days_total := (v_orig.period_end - v_orig.period_start) + 1;
            v_days_out   := (v_window - v_orig.period_start);
            IF v_days_total > 0 AND v_days_out > 0 THEN
                v_trimmed := true;
                v_trim_amount := round(v_delta * v_days_out::numeric / v_days_total::numeric, 2);
            END IF;
        END IF;
    END IF;

    INSERT INTO public.backbilling_period_evaluations
        (tenant_id, target_id, period_start, period_end, direction, delta_amount,
         cap_rule_id, jurisdiction_level, cause, anchor_date, anchor_basis,
         billable_scope, window_start, enforceable_scope, enforceable_months,
         read_classification, read_id, meter_id, last_test_date_used, trimmed, trimmed_amount,
         underreach_warning, underreach_override_reason)
    VALUES
        (v_t.tenant_id, v_t.id, v_orig.period_start, v_orig.period_end, v_direction, v_delta,
         v_rule.id,
         CASE WHEN v_rule.jurisdiction_id IS NULL THEN 'state_default' ELSE 'municipal' END,
         v_t.backbill_cause, v_t.anchor_date,
         'test_date',                       -- R-29: hard-coded in v1
         v_rule.billable_scope, v_window, v_rule.enforceable_scope, v_rule.enforceable_months,
         v_classification, v_read.id, v_t.meter_id, v_meter.last_test_date, v_trimmed, v_trim_amount,
         (v_t.backbill_cause = 'meter_error' AND v_window IS NOT NULL AND v_orig.period_start > v_window),
         v_t.underreach_override_reason)
    RETURNING id INTO v_id;

    IF v_trimmed THEN
        INSERT INTO public.invoice_events (tenant_id, invoice_id, event_type, metadata)
        VALUES (v_t.tenant_id, p_correction_invoice_id, 'backbill_cap_trimmed',
                jsonb_build_object('window_start', v_window,
                                   'period_start', v_orig.period_start,
                                   'period_end', v_orig.period_end,
                                   'delta_amount', v_delta,
                                   'trimmed_amount', v_trim_amount,
                                   'cause', v_t.backbill_cause,
                                   'evaluation_id', v_id,
                                   'source_note', v_rule.source_note));
        -- R-23: there is NO statutory duty to disclose the forfeited portion
        -- — (v)(II) is permissive, so billing less than the ceiling is
        -- expressly contemplated. The event exists for the operator and the
        -- regulator, not for the customer's bill.
        RAISE NOTICE 'backbilling cap: % of the % adverse delta on invoice % is outside the window opening % and is forfeited (%)', v_trim_amount, v_delta, v_orig.invoice_number, v_window, v_rule.source_note;
    END IF;

    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.backbilling_evaluate_period(uuid, uuid) IS
    'A-2 (v5.4.2-12), R-25 / R-23 / R-29 / R-30. Evaluates one (target, original billing period) pair and appends its evidence row, which gate (iii) then requires before the correction may be issued. Direction is computed from the database''s own arithmetic (correction amount_due minus original amount_due), never declared by an operator. A period where the customer is OWED money passes uncapped. An adverse period wholly before window_start forfeits its whole delta; a STRADDLING period is prorated by days — an approximation that assumes uniform consumption, recorded as an open question for Kyle and tariff counsel rather than presented as settled, because R-23 does not address the straddle. anchor_basis is hard-coded test_date (R-29, v1). No statutory duty attaches to disclosing the forfeited portion on the customer''s bill: (v)(II) is permissive, so billing less than the ceiling is expressly contemplated.';


-- ----------------------------------------------------------------------------
-- 13. Gate (iii) — correction-invoice issuance (R-22, R-23, R-25, R-27)
-- ----------------------------------------------------------------------------
-- NOT inside void_invoice() (R-22). The regulated act is the CHARGE, not the
-- void: a void with rebill_expected = false charges nothing, and gating the
-- void would refuse an act §7.45 does not reach while missing the one it
-- does. This answers the decision table's Open question 4, which had argued
-- for the void as the single funnel.
--
-- The gate is on ISSUANCE, which is the moment the customer is charged.

CREATE OR REPLACE FUNCTION public.enforce_backbilling_gate_issue() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_new_charge   numeric;
    v_prior_charge numeric;
    v_orig_charge  numeric;
    v_delta        numeric;
    v_t            record;
    v_orig         record;
    v_eval         record;
BEGIN
    -- Only the transition INTO an issued status, and never into void: a void
    -- charges nothing.
    IF public.is_invoice_issued(OLD.status) OR NOT public.is_invoice_issued(NEW.status)
       OR NEW.status = 'void' THEN
        RETURN NEW;
    END IF;

    -- TWO NUMBERS ARE BOTH "THE MONEY", AND NOTHING MAKES THEM AGREE.
    -- The line items are the bill's itemised content, which is what
    -- (6)(B)(v) requires a backbill to break down per billing unit. But
    -- `amount_due` is what posts to the ledger — void_invoice() reverses
    -- exactly `-(amount_due)` (tu.sql:1276) — so it is what actually lands on
    -- the customer's account. They ought to be equal and no constraint says
    -- so (residual R9).
    --
    -- The first round-2 draft of this gate read only the LINE ITEMS, having
    -- just been told by both reviewers that amount_due could not be trusted.
    -- That closed one direction and opened its mirror: a correction with
    -- honest $105 of lines (evaluated, inside the window) and `amount_due`
    -- set to $5,000 issued clean, and the ledger would have posted $5,000.
    -- Reproduced before it was closed (battery J7).
    --
    -- So: engage on the GREATER of the two for the bill being issued — the
    -- most the customer could be exposed to by either path — and on the
    -- LESSER for what was previously billed, so an already-divergent legacy
    -- bill cannot raise the bar. Once engaged, the two must AGREE.
    v_new_charge := public.backbilling_invoice_charge(NEW.id);

    -- IS THIS A REBILL, AND DOES IT CHARGE MORE?
    --
    -- Round 1 found the first draft asking the wrong question. It keyed on
    -- `invoice_type = 'correction'`, and three separate things walked past it:
    -- a `duplicate` and a `credit_memo` may both legally carry
    -- replaces_invoice_id (and v5.4.2-10 explicitly exempts both from its
    -- coordinate binding), and — simplest of all — voiding a bill and issuing
    -- a fresh `regular` invoice for the same premise and period needs no
    -- replaces_invoice_id at all. A $9,999 "duplicate" of a live $100 bill
    -- and a $5,000 "regular" rebill of a voided $100 period both issued clean.
    --
    -- R-22's own reasoning is the fix: THE REGULATED ACT IS THE CHARGE. The
    -- patch used that to keep the gate out of void_invoice() and then
    -- immediately keyed the gate on a type label anyway. So the question is
    -- now asked of the facts: was this premise and period billed before, and
    -- is this bill charging more than it did?
    --
    -- The comparison is against the HIGHEST previously-issued charge for the
    -- period, not the most recent, so a chain of void-and-reissue cannot walk
    -- the figure up one bill at a time.
    SELECT max(public.backbilling_invoice_charge(i.id)) INTO v_prior_charge
      FROM public.invoices i
     WHERE i.tenant_id = NEW.tenant_id
       AND i.id <> NEW.id
       AND i.status = 'void'
       AND i.first_issued_at IS NOT NULL          -- a discarded draft was never a bill (A-3)
       AND ((NEW.replaces_invoice_id IS NOT NULL AND i.id = NEW.replaces_invoice_id)
         OR (NEW.location_id IS NOT NULL
             AND i.location_id  = NEW.location_id
             AND i.period_start = NEW.period_start
             AND i.period_end   = NEW.period_end));

    IF v_prior_charge IS NULL THEN
        RETURN NEW;                 -- nothing was ever billed here; not a rebill
    END IF;
    IF v_new_charge <= v_prior_charge THEN
        RETURN NEW;                 -- reducing or holding: §7.45 caps the increase
    END IF;

    -- FROM HERE THE BILL CHARGES MORE FOR A PERIOD ALREADY BILLED. That is
    -- the regulated act, whatever the bill is called, and it may only proceed
    -- as an evaluated correction.

    IF NEW.invoice_type <> 'correction' OR NEW.replaces_invoice_id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: invoice %s charges %s for %s..%s at this premise, which was already billed %s on a bill since voided — charging more for a period already billed is a backbilling correction whatever the invoice is typed, and it must be evaluated against the §7.45 window first (16 TAC 7.45; invoice_type %s)', NEW.invoice_number, v_new_charge, NEW.period_start, NEW.period_end, v_prior_charge, NEW.invoice_type),
            ERRCODE = 'restrict_violation',
            HINT = 'Issue it as invoice_type = correction on a correction run, with a correction_run_targets row naming the voided bill, a backbill_cause, and an evaluation from public.backbilling_evaluate_period().';
    END IF;

    SELECT t.* INTO v_t
      FROM public.correction_run_targets t
     WHERE t.tenant_id         = NEW.tenant_id
       AND t.billing_run_id    = NEW.billing_run_id
       AND t.voided_invoice_id = NEW.replaces_invoice_id;
    IF v_t IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: invoice %s increases what is charged for an already-billed period but has no correction_run_targets row on its run — there is no recorded cause or rate-date election to evaluate it against', NEW.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;

    SELECT i.period_start, i.period_end, i.invoice_number,
           public.backbilling_invoice_charge(i.id) AS charge INTO v_orig
      FROM public.invoices i
     WHERE i.id = v_t.voided_invoice_id AND i.tenant_id = v_t.tenant_id;
    v_orig_charge := coalesce(v_orig.charge, 0);
    v_delta := v_new_charge - v_orig_charge;

    -- A correction with no statutory cause is a clerical re-issue, and may
    -- only REDUCE. Reaching here means it does not.
    IF v_t.backbill_cause IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: invoice %s increases the charge for this period (%s -> %s) but its correction target records no backbill_cause — an additional charge cannot be evaluated against a §7.45 window that has not been established', NEW.invoice_number, v_orig_charge, v_new_charge),
            ERRCODE = 'restrict_violation',
            HINT = 'Set backbill_cause and anchor_date on the correction target (the cause is a FINDING from evidence — a test result, a tamper investigation, a rate audit), then call public.backbilling_evaluate_period(target_id, correction_invoice_id).';
    END IF;

    -- The evidence record must exist, and describe THIS cause. Same shape as
    -- AC-31's snapshot requirement: the gate judges on a record written
    -- before it, not on arithmetic it redoes at issuance.
    SELECT e.* INTO v_eval
      FROM public.backbilling_period_evaluations e
     WHERE e.target_id    = v_t.id
       AND e.period_start = v_orig.period_start
       AND e.period_end   = v_orig.period_end
     ORDER BY e.evaluation_seq DESC
     LIMIT 1;

    IF v_eval IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: invoice %s has no per-period evaluation for the original period %s..%s — CI-008 requires the uniform evaluation to be on the record before the charge is made', NEW.invoice_number, v_orig.period_start, v_orig.period_end),
            ERRCODE = 'restrict_violation',
            HINT = 'SELECT public.backbilling_evaluate_period(<target_id>, <correction_invoice_id>);';
    END IF;

    IF v_eval.cause IS DISTINCT FROM v_t.backbill_cause THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: invoice %s was evaluated under cause %s but its target now records %s — the evidence describes a window this correction no longer claims; re-evaluate', NEW.invoice_number, v_eval.cause, v_t.backbill_cause),
            ERRCODE = 'restrict_violation';
    END IF;

    -- AND THE EVIDENCE MUST STILL DESCRIBE THIS BILL. The evaluation is
    -- written against a DRAFT, and a draft's line items are not frozen by the
    -- -10 snapshot guard (which freezes invoice_type, replaces_invoice_id,
    -- billing_run_id, the period and created_at — not the money). Without
    -- this conjunct the sequence
    --     evaluate a $5 correction -> inflate the draft to $5,000 -> issue
    -- passes every other check in this gate. Found by the author before
    -- round 1; the round-1 reviewers then showed the first version of this
    -- check was reading amount_due, which the caller sets on both sides, so
    -- it is now re-derived from the LINE ITEMS (battery I1).
    IF v_delta IS DISTINCT FROM v_eval.delta_amount THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: invoice %s was evaluated at a delta of %s but its line items now total %s against the replaced bill''s %s (delta %s) — the evidence on the record describes a different bill; re-evaluate before issuing', NEW.invoice_number, v_eval.delta_amount, v_new_charge, v_orig_charge, v_delta),
            ERRCODE = 'restrict_violation',
            HINT = 'SELECT public.backbilling_evaluate_period(<target_id>, <correction_invoice_id>); — the evaluation is append-only, so re-evaluating adds the current answer rather than editing the old one.';
    END IF;

    -- R-27. The under-reach warning stands until an evidentiary-impossibility
    -- override is recorded ON THE TARGET, where the database stamped it.
    -- Deliberately NOT read from invoice_events: tally_app can write that log,
    -- so an override recorded there would let the software clear its own
    -- warning (F-3).
    IF v_eval.underreach_warning AND v_t.underreach_override_reason IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling under-reach: invoice %s corrects a meter_error from %s, but the (7)(B)(v)(I) window opens %s — where a meter over-registered the correction is MANDATORY back to the window, and reaching less far needs a recorded evidentiary-impossibility ground', NEW.invoice_number, v_eval.period_start, v_eval.window_start),
            ERRCODE = 'restrict_violation',
            HINT = 'Either extend the correction back to the window, or record the ground on the target: UPDATE public.correction_run_targets SET underreach_override_reason = ''no_read_history'' | ''meter_replaced'' | ''records_predate_acquisition'' WHERE id = ...; the clock and the actor are the database''s.';
    END IF;

    -- THE TRIM IS NOT ENFORCED HERE, AND THAT IS DELIBERATE AS OF ROUND 2.
    -- Round 1 found the first draft computing a forfeited amount, writing it
    -- to the evidence row, announcing it — and then issuing the bill at the
    -- full delta, because this gate only refused when the trim consumed
    -- EVERYTHING. By this patch's own standard that is worse than no guard:
    -- the log said forfeited and the bill was not.
    --
    -- It is not patched over here because the fix depends on a ruling that
    -- does not exist yet. The trim was proportional to a delta derived from
    -- the draft, so it has no fixed point — re-drafting at the trimmed figure
    -- re-prorates the already-trimmed number, and no draft amount ever yields
    -- untrimmed evidence. Whether a straddling period is billable whole,
    -- forfeited whole, or divisible at all is Q-C with Kyle
    -- (kyle-questions-2026-09-22-a2-straddle-and-last-test.md). Until it is
    -- answered this gate refuses the straddle outright rather than pretending
    -- to trim it: fail closed, and loudly, on the case nobody has ruled.
    IF v_eval.direction = 'customer_owes' AND v_eval.trimmed THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: the period %s..%s on invoice %s straddles or precedes the window opening %s, so %s of the %s adverse delta falls outside the billable bound — how a straddling period is treated is not yet ruled (16 TAC 7.45(7)(B)(v); Kyle Q-C), and this correction is refused rather than billed at an amount the evidence itself calls partly forfeited', v_eval.period_start, v_eval.period_end, NEW.invoice_number, v_eval.window_start, v_eval.trimmed_amount, v_eval.delta_amount),
            ERRCODE = 'restrict_violation',
            HINT = 'Re-draft the correction to cover only billing periods that begin at or after the window, or wait for the straddle ruling. Do NOT reduce the draft to the post-trim figure: the trim is proportional to the delta, so re-evaluating simply trims again.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_backbilling_gate_issue() IS
    'A-2 (v5.4.2-12), gate (iii) — R-22 / R-23 / R-25 / R-27, re-keyed after review round 1. BEFORE UPDATE OF status on invoices, on the transition INTO an issued status: the moment the customer is charged. Deliberately NOT inside void_invoice() (R-22) — the regulated act is the charge, not the void. It engages on the FACTS rather than on invoice_type: it asks whether this premise and period were billed before (on a bill since voided, once issued) and whether this bill charges MORE, measuring both from the LINE ITEMS rather than the caller-set amount_due. Round 1 walked three things past the earlier type-keyed version — a duplicate, a credit_memo and a plain regular rebill of the voided period. A bill that charges more must be a correction with a target, a cause, and a current evaluation whose delta still matches the line items; it is refused while an under-reach warning stands unoverridden, and refused outright where the evaluation shows any trim, because the straddle is unruled (Kyle Q-C).';

DROP TRIGGER IF EXISTS a_enforce_backbilling_gate_issue ON public.invoices;
CREATE TRIGGER a_enforce_backbilling_gate_issue
    BEFORE UPDATE OF status ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_backbilling_gate_issue();


-- ----------------------------------------------------------------------------
-- 14. The freeze extension (F-4 — an amendment to R-19, stated)
-- ----------------------------------------------------------------------------
-- The v5.4.2-10 target freeze is COLUMN-LISTED, so backbill_cause and
-- anchor_date were unfrozen by construction. R-19 says the cause "freezes
-- per-invoice at correction-invoice post" — but the calculation snapshot is
-- validated BEFORE issuance, and the R-25 evidence record is written against
-- the cause in force at gate (iii). A cause changed between snapshot and post
-- would leave the frozen evidence describing a window the target no longer
-- claims.
--
-- So the two columns join the freeze at SNAPSHOT EXISTENCE, not at post. That
-- FOLLOWS from AC-31 rather than contradicting R-19, but it narrows the
-- revisability R-19 deliberately granted — meter_error -> tampering_theft is
-- a real progression, and after a snapshot exists it now requires deleting
-- the draft snapshot first. That is the same cost every other election on
-- this row already pays. With Kyle.
--
-- The function is re-issued with the two columns added to its early-return,
-- and the trigger re-created with them in its column list. Both must change
-- together: the column list decides when the function runs, the early-return
-- decides what it ignores, and adding a column to only one of them produces a
-- guard that either never fires or fires on every unrelated update.

CREATE OR REPLACE FUNCTION public.enforce_correction_target_frozen_under_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.billing_run_id     IS NOT DISTINCT FROM OLD.billing_run_id
       AND NEW.voided_invoice_id  IS NOT DISTINCT FROM OLD.voided_invoice_id
       AND NEW.rate_date_mode     IS NOT DISTINCT FROM OLD.rate_date_mode
       AND NEW.rate_date_override IS NOT DISTINCT FROM OLD.rate_date_override
       AND NEW.backbill_cause     IS NOT DISTINCT FROM OLD.backbill_cause
       AND NEW.anchor_date        IS NOT DISTINCT FROM OLD.anchor_date THEN
        RETURN NEW;                            -- nothing the binding reads is changing
    END IF;
    -- This statement already holds the row lock (UPDATE / DELETE), so it has
    -- waited behind any snapshot writer's mutex UPDATE on the same row and,
    -- under READ COMMITTED, now sees that writer's snapshot.
    IF EXISTS (
        SELECT 1
          FROM public.invoice_calculation_snapshots s
          JOIN public.invoices i ON i.id = s.invoice_id
         WHERE i.billing_run_id      = OLD.billing_run_id
           AND i.replaces_invoice_id = OLD.voided_invoice_id
           AND i.invoice_type        = 'correction') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s (run %s, voided invoice %s): a calculation snapshot was checked against this election; the target cannot change or be removed while that snapshot exists (v5.4.2-10; extended to backbill_cause and anchor_date by v5.4.2-12) — delete the draft snapshot first', OLD.id, OLD.billing_run_id, OLD.voided_invoice_id),
            ERRCODE = 'restrict_violation';
    END IF;
    -- No isolation pin: the validator's mutex is a real UPDATE of this row,
    -- so a REPEATABLE READ editor racing a writer fails on the row version
    -- natively (Fable round-2 LOW-4, Codex round 2 — independently).
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_correction_target_frozen_under_snapshot() IS
    'v5.4.2-10 (A-3 follow-up), extended by v5.4.2-12 (A-2, F-4). BEFORE UPDATE OF billing_run_id, voided_invoice_id, rate_date_mode, rate_date_override, backbill_cause, anchor_date OR DELETE on correction_run_targets: refused while an invoice_calculation_snapshots row exists for the correction invoice (same run, replaces_invoice_id = voided_invoice_id) — its valid_at was checked against this election, and since v5.4.2-12 the R-25 evidence record is written against this cause. R-19 placed the cause''s freeze at correction-invoice POST; this moves it to snapshot existence, because the snapshot is validated before issuance and a cause that moved afterwards would leave frozen evidence describing a window the target no longer claims. The snapshot validator takes the target row''s lock via an UPDATE of updated_at, so this guard waits behind in-flight writers and a REPEATABLE READ racer fails natively — no isolation pin needed.';

DROP TRIGGER IF EXISTS a_enforce_correction_target_frozen_under_snapshot ON public.correction_run_targets;
CREATE TRIGGER a_enforce_correction_target_frozen_under_snapshot
    BEFORE UPDATE OF billing_run_id, voided_invoice_id, rate_date_mode, rate_date_override, backbill_cause, anchor_date OR DELETE ON public.correction_run_targets
    FOR EACH ROW EXECUTE FUNCTION public.enforce_correction_target_frozen_under_snapshot();


-- ----------------------------------------------------------------------------
-- 15. Residuals, stated (R1–R8)
-- ----------------------------------------------------------------------------
-- R1. THE STRADDLING PERIOD IS PRORATED BY DAYS, and that assumes uniform
--     consumption, which for gas is false. R-23 does not address the straddle;
--     the two alternatives are forfeiting the whole period (over-forfeits) and
--     billing it whole (over-collects, the direction §7.45 exists to stop).
--     OPEN QUESTION for Kyle and tariff counsel. The evidence row carries the
--     window and the trimmed amount, so a different rule is a re-evaluation.
--
-- R2. THE UNKNOWN-PRIOR-TEST PATH REFUSES rather than asking. Refinement 5
--     rules that an operator confirms before an adverse charge lands; there is
--     no confirmation surface, so backbilling_window_start() refuses an
--     adverse period on a meter with no recorded test date. That is the
--     conservative direction and it is loud, but it is narrower than the
--     ruling: an operator who KNOWS there was no prior test cannot say so.
--     The CI-091 test-history patch is the natural home for the fix.
--
-- R3. A TENANT CREATED AFTER THIS PATCH HAS NO CAP RULES, and its first
--     correction fails closed with a HINT naming seed_backbilling_cap_defaults().
--     No trigger seeds on tenant creation: platform-fixed statutory data
--     written by a trigger on a tenant-scoped table is a surface this schema
--     does not otherwise have, and the failure is loud rather than silent.
--     Onboarding must call the function.
--
-- R4. ONLY TEXAS GAS IS SEEDED. Water, sewer and electric resolve to no rule
--     and therefore refuse. Correct for the Texas-only launch scope, wrong the
--     moment a second service goes live.
--
-- R5. THE R-30 BUCKET ASSIGNMENTS for meter_buried, meter_obstructed,
--     key_required and seasonal_closure are an engineering proposal riding
--     with the R-28/R-29 counsel referral, not Kyle's ruling. They sit in the
--     safe third bucket meanwhile. historical_average and
--     same_period_prior_year are there for a different reason — they describe
--     method, not cause — which is R-30's separately recorded schema defect,
--     NOT fixed here.
--
-- R6. THE READ CHOSEN FOR CLASSIFICATION is the most recent one inside the
--     original period. A period with several reads of differing access status
--     is classified on the last of them, not the worst. R-30's "more
--     conservative wins" governs the two COLUMNS of one read, not two reads.
--
-- R7. anchor_basis IS HARD-CODED test_date (R-29, v1). A (v)(II) discovery
--     anchor is recorded on the target as a date but the evidence row still
--     says test_date, which for that cause is wrong on its face. Widening it
--     is a later patch; the domain is already declared so that patch widens
--     no CHECK.
--
-- R7b. THE EVIDENCE ROW IS RE-CHECKED AGAINST THE BILL AT ISSUANCE, because a
--     draft's amount_due is not frozen by the -10 snapshot guard. Found by
--     the author before review: evaluate cheap, inflate the draft, issue.
--     Gate (iii) now re-derives the delta and refuses a mismatch. The
--     evaluation stays append-only, so re-evaluating adds the current answer.
--
-- R9. invoices.amount_due IS NOT DERIVED FROM invoice_line_items, and both are
--     "the money": the lines are the itemised bill content (6)(B)(v) requires,
--     amount_due is what posts to the ledger (void_invoice reverses exactly
--     -(amount_due)). Nothing in tu.sql ties them together. This patch
--     requires them to AGREE on a bill that increases what a customer owes
--     for an already-billed period, which is the narrowest rule that makes a
--     §7.45 window meaningful — but the schema-wide invariant belongs to the
--     invoice, not to A-2, and is recorded here for the register. Both
--     round-1 reviewers found the first draft resting on amount_due alone;
--     the first round-2 draft then rested on the lines alone, which was the
--     same defect mirrored.
--
-- R8. THE ENFORCEABLE BOUND IS RECORDED, NOT WIRED. R-20 hands it to Family 9
--     as a value; nothing in this patch stops collections pursuing a debt
--     whose enforceable_scope is 'never'. The evidence row carries it.
--
-- ----------------------------------------------------------------------------
-- 16. The AC-32 tail
-- ----------------------------------------------------------------------------
-- Every patch from v5.4.2-11 on ends by calling this, because the tenant
-- isolation invariants are true when a patch applies and drift at the next
-- CREATE: tu.sql:11388's ALTER DEFAULT PRIVILEGES ... ON TABLES TO tally_app
-- reaches views and matviews too, so a new table is born with NO RLS at all.
-- This patch created three tables, which is exactly the case that gate is for.

DO $$
BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE NOTICE 'v5.4.2-12: tenant isolation invariants hold — backbilling_cap_rules, correction_run_target_events and backbilling_period_evaluations each carry RLS, FORCE and the canonical tenant_isolation policy; no view, matview or definer regressed (AC-32).';
END;
$$;

-- ============================================================================
-- END PATCH v5.4.2-12
-- ============================================================================
