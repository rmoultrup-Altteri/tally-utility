# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

---

## 2026-08-31 (A-7 lands — Wave 2 complete) — v5.4.2-07: regulatory cost-recovery surcharge riders — the Texas Pipeline Safety Fee

**What was done:** Drafted **v5.4.2-07** (`sql/v5.4.2-07-regulatory-surcharge-riders.sql`, 1,196 lines; reviewed body `439d125f…`, comment-only delta to `6a322537…`) for A-7 under Kyle D4-1 (no remittance gate, no billing window): `regulatory_surcharge_rules` (rider classification per (rate item, cycle of bill dates): kind, configured cap per service, tax-base exclusion, state-agency exemption; in-place bi-temporal; one PSF rule per tenant per bill date; `regulatory_surcharge_rule_as_of()`), `customers.is_state_agency` with attribute history and `customer_is_state_agency_as_of()` (period end, America/Chicago), `invoice_line_item_bases` (CI-045's materialized base composition; guard + deferred issuance gate; an excluded surcharge line is never a base; citing line re-checked), the surcharge line guard (never a tax, never taxable, 0.00 for a state agency, positive-only per-meter cap on a mutex row, `rate_item_id` frozen), two-way taxability refusal, an INSERT fence on both A-21 ledgers, provenance, the compliance-report view. Mirrored (tu.sql 19,779), fresh-build verified, docs in both repos.

**Review rounds:** Fable + Codex, fresh-load scratch DBs; the file changed four times during round 1 (both reviewers froze copies and re-verified by hash — recorded as a failed approach). Fable: HIGH ×4 (negative line lent cap headroom; issuance gate trusted the caller-chosen snapshot coordinate; direct inserts into the A-21 ledgers cancelled the exemption; advisory lock did not cover REPEATABLE READ snapshots), MEDIUM ×2 (TimeZone boundary; two capped PSF riders). Codex: CRITICAL ×2 (nulling `rate_item_id` detached a capped line → 999.00 issued as PSF; the ledger-insert hole), MEDIUM (stale base row after a rider re-classification). Author: re-parent kept bases; cited line could shrink; draft delete failed on the FK. Round 2 on `439d125f…`: all closed, nothing new, both "sound enough to mirror".

**Decisions:** D-2026-08-31-01…-08; AC-26…AC-28. Headline: D4-1 read strictly — the structural residue of CI-038 is cap + exemption + exclusion; the cap counts positive amounts only and is serialised on a mutex row; the issuance gate judges on current knowledge; the base composition is a table, not a promise; A-21's ledgers are now written only by the database.

**Failed approaches (mechanism):** `pg_trigger_depth() = 0` fence; advisory lock vs RR; netting negatives; trusting the snapshot pair; `remitted_on` on a frozen row; editing under reviewers; a shadowed helper parameter; INSERT … SELECT FROM (INSERT …). All in DECISION-LOG.

**Results:** tu.sql 19,779 lines; 82 tables / 250 triggers (182 ENABLE ALWAYS) / 357 CHECKs / 357 FKs / 10 EXCLUDE / 59 UNIQUEs / 81 policies / 80 FORCE RLS / 571 indexes / 383 functions; battery 161 green on the build. GBM: CI-038 → `partially-structurally-enforced`; CI-045 text; Appendix A-7 LANDED; A-23 (1e); parity plan **Wave 2 complete**; ingestion Section AU.

**Next:** Wave 3 — A-2 (jurisdiction-keyed backbill caps) → A-9 → A-10; A-8 held for a Kyle brief. Kyle: the $1.00 / $0.50 cap; whether `is_state_agency` needs a verifying document; meter change-out vs the per-meter cap; K1/K4 (is_taxable_default's silent false; applies_to vs is_taxable); A-3's unbound `valid_at`.

---

## 2026-08-28 (A-21 lands) — v5.4.2-06: account lifecycle state-events, date-effective account attributes, deposit / interest ledger

**What was done:** Drafted **v5.4.2-06** (`sql/v5.4.2-06-account-lifecycle-and-deposits.sql`, 1,328 lines) for A-21: `customer_state_events` written by the lifecycle guard (reason consumed into the event; closed reopens only to active; closed refused while a deposit is unsettled; `customer_status_as_of()`), `customer_attribute_history` (eight attributes, initial rows at insert, `customer_attribute_as_of()`), `deposit_interest_rates` (effective-dated, no-fallback lookup, backdating refused once settled), `deposit_waiver_determinations` (CI-129 — a §7.45 deposit refused while one is in force), `deposits` (basis / instrument / cap on the record; status projected from events), `deposit_events` (the append-only sub-ledger where the day-31 cliff, retroactive-to-day-1, contiguous periods, rate-in-force, principal-in-force, exact amount, exhaustion horizon, credited-in-full-at-refund are refusals), `deposit_balance()` / `deposit_refund_trigger_state()` / `deposits_refund_due`, `customers.deposit_*` as a database projection, payments reconciled + CHECK, credit lineage trigger, ledger enums, composite FKs, RLS/FORCE, **TEMP revoked on the database from PUBLIC/`tally_app`**, every guard ENABLE ALWAYS, reporting-only backfill. Battery 141 green (scratch + fresh build), seeded backfill verified, strict-applied ×2 and over the build, fresh rebuild with catalog parity; mirrored (tu.sql 17,704 → 18,822).

**Review rounds:** Fable + Codex, fresh-load + pre-seeded scratch DBs; four file revisions verified by hash. Codex: CRITICAL (a deposit consumed by the final bill could never be settled), HIGH (legacy applied/refunded scalars frozen), MEDIUM (no terminal status), then HIGH (exhaustion ≤ 30 days + a pre-exhaustion accrual blocked the zero refund), MEDIUM (apply after refund_initiated). Fable: CRITICAL ×2 (**`pg_trigger_depth()` bypassed via a pg_temp trigger function — the app role rewrote every projection**; superuser-owned view bypassed RLS), HIGH ×2, MEDIUM ×4, LOW ×3. All fixed by mechanism (D-2026-08-28-34…-43); Fable round 2 and Codex round 4: "sound enough to mirror" on md5 `66c8babf…`, each with a boundary matrix of the day-30/31 and exhaustion rules.

**Decisions:** D-2026-08-28-34…-43; AC-23…AC-25. Headline: the state log and the deposit ledger are written by the database, everything else is a projection; interest is events recomputed by the guard, never an accumulator; the accrual horizon is money held (return or exhaustion); TEMP revoked so the depth fence is structural; legacy history carried, never refused.

**Failed approaches (mechanism):** depth fence with TEMP; superuser view; NOT VALID CHECKs; horizon without exhaustion (twice); lingering reason; `now()` ordering; backfill stamp behind the guard; SRF in CASE; `<` on the application day. All in DECISION-LOG.

**Results:** tu.sql 18,822 lines; 79 tables / 237 triggers (170 ENABLE ALWAYS) / 344 CHECKs / 345 FKs / 8 EXCLUDE / 78 policies / 77 FORCE RLS / 56 UNIQUEs. GBM: CI-130 → `structurally-enforced`; CI-121/125/129/131 and CI-077 → `partially-structurally-enforced`; CI-126 text; Appendix A-21 LANDED; A-23 (1d); parity plan A-21 struck; ingestion Section AT.

**Next:** A-7 (PSF surcharge) closes Wave 2. Kyle: the lifecycle matrix, legacy-deposit refund policy, and the deposit-workflow questions (credit vs disbursement; residential non-cash; instrument expiry).

---

## 2026-08-28 (A-20 lands) — v5.4.2-05: read/bill exception queue and validation-state substrate

**What was done:** Drafted **v5.4.2-05** (`sql/v5.4.2-05-read-and-bill-exception-substrate.sql`, 1,081 lines) for A-20: `read_validation_exceptions` (CI-112 queue with the resolution state machine), the read gate (no open exception on any step into approved/released/locked; `validated_at` server-stamped on the first billable entry; validated-read facts frozen), the D14-1 counter on `meters` (stored, gate-maintained, `pg_trigger_depth` guarded, derived by `consecutive_estimate_state()`), the auto-raised over-cap exception + cap re-check at approval, `billing_run_meters` gates (open exception; CI-023 master completeness via `meter_master_incomplete_reasons()`), `invoice_exceptions` (CI-115 queue carrying table #35's routing outputs) with the pre-delivery gate on `invoices` and `invoice_events` lineage, tenant-bound composite FKs + same-tenant user/anomaly checks, RLS/FORCE/REVOKE/ENABLE ALWAYS, and a reporting-only backfill. Battery 154 green (scratch + fresh build), pre-seeded backfill verified, strict-applied ×2 (idempotent) and over the mirrored build, fresh rebuild with catalog parity; mirrored (tu.sql 16,811 → 17,704).

**Review rounds:** Fable + Codex, fresh-load scratch DBs (plain + pre-seeded), two rounds each; the file changed four times between rounds. The streak definition failed twice under review before it held — status-transition counting double-counted the rework loop and dropped excluded reads; validation-order counting let a back-dated actual clear later-dated estimates (Codex ran five estimates past a cap of 3). Other real defects: `void_released → released_to_billing` bypassed the gate; an exception raised after approval was not gated onward; the backfill aborted on a same-day estimate+actual and on queued deferred-FK events and broke under the strict prelude; a cap < 1 made the patch refuse; cross-tenant `resolved_by`; reviewed_* checks skipped INSERT; estimates pending together never auto-raised; a stray `validated_at`. All fixed by mechanism (D-2026-08-28-25…-33); round 2: both "sound enough to mirror" with independent batteries of the date-bounded rule.

**Decisions:** D-2026-08-28-25…-33; AC-20…AC-22. Headline: the streak is defined once — validated estimates dated after the latest-dated validated actual — and the gate, the derivation and the backfill share it (a refinement of D14-1b, flagged for Kyle); exceptions are rows born open and frozen at resolution; the database raises the over-cap exception itself; the pre-delivery gate refuses, it does not auto-hold; `validated_at` is repurposed as the server-stamped validation event.

**Failed approaches (mechanism):** two streak definitions; DISABLE/ENABLE TRIGGER around a backfill; `now()` as an ordering stamp; `length(btrim())` without `IS NOT NULL`; expected-error chunks containing their setup; a raising function inside a NOTICE query. All in DECISION-LOG.

**Results:** tu.sql 17,704 lines; 73 tables / 213 triggers (146 ENABLE ALWAYS) / 316 CHECKs / 324 FKs / 72 policies / 71 FORCE RLS / 50 UNIQUEs. GBM: CI-113 → `structurally-enforced`, CI-023 → `partially-structurally-enforced`, CI-112/115 text updated (tokens unchanged); Appendix A-20 LANDED; parity plan A-20 struck; decision table #4 annotated; ingestion Section AS.

**Next:** A-21 (account lifecycle state-events, date-effective attributes, deposit/interest ledger), then A-7. Kyle: the D14-1b refinement and the Texas cap ceiling.

---

## 2026-08-28 (A-3 lands) — v5.4.2-04: invoice calculation snapshots, Option B

**What was done:** Resumed from the A-1 handoff and drafted **v5.4.2-04** (`sql/v5.4.2-04-invoice-calculation-snapshots.sql`, 722 lines): `invoice_calculation_snapshots` (one per invoice, composite FK to `invoices(id, tenant_id)` — new UNIQUE; the run's `(valid_at, recorded_at)` pair per AC-15; `snapshot_schema_version` enforced by `validate_calculation_snapshot()` against an enumerated `v1` key contract incl. nested shapes; `formula_version`; eight JSONB sections mirroring CI-015's list; GENERATED sha256 `content_hash`), `invoice_snapshot_references` (provenance into the seven A-1 tables, verified open at the snapshot's `recorded_at`), the DEFERRABLE `enforce_invoice_has_snapshot` gate on `invoices` (exactly one snapshot, still agreeing with period/run/customer/lines, at commit of any move into an issued status; draft/held → void exempt), immutability (UPDATE never; INSERT/DELETE only while draft/held; cascade on draft delete; TRUNCATE rejected; `REVOKE UPDATE` from `tally_app`), RLS + FORCE, every guard `ENABLE ALWAYS`. Live-tested on a fresh-loaded scratch (90-check battery incl. an end-to-end `tally_app` issuance), strict-applied ×2 (idempotent), four two-session races, fresh rebuild with catalog parity, patch re-applied over the mirrored build, battery green there too; mirrored (tu.sql 16,245 → 16,811).

**Review rounds:** two independent adversarial reviews (Fable `general-purpose`, Codex `codex-rescue`), fresh-load scratch DBs, two rounds each. Round 1: both found the same CRITICAL — `SET search_path = ''` on the new functions made the first RLS policy evaluation call the unqualified v5.2.1 helpers, so `tally_app` could not write a snapshot or issue an invoice at all (the superuser battery had bypassed RLS); Fable also reproduced a two-session race (issued invoice with its snapshot deleted / a line edited / a citation added), `void_invoice()` blocked on held invoices, amounts compared after a `numeric(12,2)` cast, and two LOWs; the author's second pass found the draft-delete FK block. All fixed by mechanism (D-2026-08-28-16…-24): `public, pg_temp` pin, `FOR SHARE` on the invoice in the guards + line lock in the deferred check (the snapshot-row lock was tried and dropped — deadlock + privilege), void exemption, unrounded JSON-number amounts, cascades with ALTER-if-differs. Round 2: both "sound enough to mirror" — Fable re-ran every repro, Codex ran the races live with blocking timings.

**Decisions:** D-2026-08-28-16…-24 in `application/DECISION-LOG.md`; AC-18/AC-19 in `application/APPLICATION-CONTRACTS.md`. Headline calls: completeness is a commit-time gate, every invoice type included; schema version is a validator, not a label; the coordinate pair lives on the snapshot; lines stored twice and cross-checked twice; no snapshot after issuance (pre-patch invoices stay snapshot-less); provenance is a table with a visibility proof; `public, pg_temp` not `''` until A-23 pins the helpers.

**Failed approaches (mechanism):** `''` pin vs RLS helpers; snapshot-row `FOR UPDATE` in a deferred check; STABLE functions in a GENERATED column; `text[] || 'literal'`; assuming CHECK runs before BEFORE triggers; mirroring from the second banner (caught, reverted); running the battery outside a transaction. All in DECISION-LOG.

**Results:** tu.sql 16,811 lines; 71 tables / 201 triggers (134 ENABLE ALWAYS) / 294 CHECKs / 308 FKs / 7 EXCLUDE / 70 policies / 69 FORCE RLS. GBM: CI-015 → `structurally-enforced` (boundary stated; Ryan may prefer partial — flagged); Appendix A-3 LANDED; parity plan Wave 1 complete; bi-temporal-decision §2.3 annotated; ingestion Section AR.

**Next:** Wave 2 (A-20 → A-21, A-7). Before any bill-run calculation code: CI-003's GUC net (R-16) and the snapshot value contract. A-23 now carries the `''`-pin trap as a reason to pin the three helpers.

---

## 2026-08-28 (A-1 lands) — v5.4.2-03: bi-temporal transaction-time substrate on the seven reference tables

**What was done:** Resumed from the blocked A-1 handoff with Kyle's rulings back (`gas-billing-memory/application/kyle-decisions-2026-08-26-a1-bitemporal.md`, R-9…R-18). Folded them into the design doc §5, then drafted **v5.4.2-03** (`sql/v5.4.2-03-bitemporal-substrate.sql`, 1,909 lines): header/version split for `rate_schedules`/`wna_zones`/`rate_items` (content moved into `*_versions`, backfilled at `created_at` as flagged approximations; `current_rate` dropped; `rate_item_history` brackets migrated then retired read-only; `archive_rate_item_history()` a RAISE stub); in-place transaction-time pair on `rate_schedule_items`/`franchise_fee_rules`/`customer_tax_exemptions`/`wna_monthly_adjustments`; the three UNIQUEs that blocked same-date corrections → open-rows exclusion/partial constraints; one shared guard (closed rows immutable, asserted rows accept only the close, drafts free), a deferred entity-scoped "superseded needs an asserted successor" check, header identity guard + `assert_reference_version()` (D1-1); R-9 `service_type` versioned with full-span-only correction; R-11 lock at `approved`; R-12 lock at `active`, DEFAULT → `pending_verification`, verifier CHECK; R-13 `industrial` removed (self-verifying); R-14 tolerate drafts + all three riders (archive-reason enum, draft not assignable, not-current enums reconciled); R-15 the seven two-axis `*_as_of()` lookups + `should_charge_tax`/`get_partial_period_policy` re-issued, `get_effective_rate` neutralised, `get_correction_rate_date` COMMENT rewritten; R-17 basis code + `anomalies` review row; six CASCADEs stripped; ten tables into the CI-014 set. Live-tested on a seeded pre-patch container (166-check battery), strict-applied ×4 (idempotent), fresh rebuild with catalog parity + smoke set, mirrored (tu.sql 14,499 → 16,245).

**Review rounds:** two independent adversarial reviews (Fable `general-purpose`, Codex `codex-rescue`), fresh-load scratch DBs, two rounds each. Round 1 found real defects the battery had not: the lineage/successor check was entity-scoped on one table only (Codex CRITICAL, Fable H1 — an entity could silently lose its current assertion under a "superseded" label), transaction time was caller-supplied on both axes (both), `backfill` was a born-closed door, revocation beside an open active row kept a customer exempt, R-9 accepted a shifted bracket, R-17 was bypassable by retract-then-`initial`, drafts satisfied "superseded", re-apply broke after a post-patch row, headers were unreconciled with archive, version rows weren't tenant-bound, `should_charge_tax` leaked across tenants as SECURITY DEFINER. All fixed by mechanism (DECISION-LOG D-2026-08-28-02…-12); round 2: both "sound enough to mirror", residuals taken or recorded.

**Decisions:** fifteen (D-2026-08-28-01…-15) in `application/DECISION-LOG.md`; AC-14…AC-17 (+AC-8 amended) in `application/APPLICATION-CONTRACTS.md`. Headline calls: retraction is a closing event, not an insert enum value; lineage points backwards and the close comes first; transaction time is the database's; every valid-time change to an asserted row is insert-and-close; the draft is the header (born `draft`); `expired`/`superseded` leave the status enums; R-17's queue is an `anomalies` row; no `app.*` carve-out anywhere.

**Failed approaches (mechanism):** a text-matched Python wrapper nested DO blocks; a `SELECT 1` readiness probe hit Docker's temporary init server; `format('%:')`; psql `:var` inside `$$`; sticky `SET CONSTRAINTS ALL IMMEDIATE`; `RETURNING` in a subquery; rejecting same-transaction closes as erasure; uuid-vs-text in the dynamic successor query; dropping a UNIQUE before its dependent FK. All in DECISION-LOG.

**Results:** tu.sql 16,245 lines; 69 tables / 194 triggers (127 ENABLE ALWAYS) / 283 CHECKs / 302 FKs / 7 EXCLUDE / 68 policies. GBM: CI-001 → `structurally-enforced`, CI-002 → `structurally-enforced`, CI-011 → `partially-structurally-enforced`, CI-035 → `structurally-enforced`, CI-004/005 text updated (tokens unchanged), CI-003 revisit trigger corrected (R-16); Appendix A-1 LANDED, A-23 amended (three unpinned definers remain), parity plan A-1 struck; ingestion Section AQ; design doc §5 resolved.

**Next:** A-3 (invoice calculation snapshots, Option B) — leans on this layer; then Wave 2. Open for Ryan: the raw `version` bump (option-(a) seal), CI-003's revisit before any calculation code, R-18's v5.5 item.

---

## 2026-08-25 (A-1 decisions routed to Kyle) — no code; blocked on domain-expert rulings

**What was done:** Resumed from the 2026-08-20 A-1 design handoff; committed the pending session-wrap (`5115109`). Walked the five open decisions (`a1-bitemporal-design-review-2026-08-20.md` §5) against tu.sql facts — `wna_monthly_adjustments` states `pending→approved→applied→archived` with `approved_by/at`; `customer_tax_exemptions` states `pending_verification/active/expired/revoked/rejected` but **DEFAULT `'active'`** (no draft phase unless flipped); `rate_schedules.service_type` NOT NULL + 7-value CHECK, 35 references; only `app.*` GUC precedent is `app.void_operation`. Engineering recommendations: Q1 `service_type` versioned (identity row = `id, tenant_id, code, created_at, version`); Q2a WNA lock at `approved`; Q2b exemptions lock at `active` with DEFAULT → `pending_verification` (flagged as the only behavior change); Q3 tolerate orphan draft headers; Q4 full `as_of()` family in-patch (split -03/-04 permitted only within one session, no interim re-grade); Q5 CI-003 GUC coordinate net deferred to post-A-3. **Ryan ruled these are business-workflow questions for Kyle.** Wrote `gas-billing-memory/application/a1-bitemporal-kyle-brief-2026-08-25.md` (plain-language, self-contained, Q1–Q5 with recommendations and blank Ruling/Rationale table in the July WU5/WU6 format), ingestion Section AP, and a send-ready message for Kyle. HANDOFF.md set to BLOCKED on Kyle.

**Repo state:** tally-utility `ddb37d2` pushed; gas-billing-memory `d9f8a4f` pushed (`ryan`). tu.sql unchanged, 14,499 lines. No DDL drafted.

**Next:** Kyle rulings → fold into design doc §5 + DECISION-LOG → draft A-1 patch. Until then, A-23's six unpinned SECURITY DEFINER functions are unblocked work.

---

## 2026-08-20 (session 2, A-1 design review) — architecture reviewed adversarially; 5 open decisions, no DDL yet

**What was done (full session, design-only — no SQL written, tu.sql untouched):** Resumed from the A-4 handoff into A-1 (Phase 4 Wave 1, the transaction-time substrate — CI-001/002/005/011). Read `bi-temporal-decision.md` §1/§3/§6, the CI-001/002/005/011 entries and Appendix A-1, and D1-1 (the prior ruling that already closed CI-011 via optimistic concurrency, not a conflict-workflow). Scoped A-1 to the 7 tables named in CI-004 (`rate_schedules`, `rate_schedule_items`, `rate_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_zones`, `wna_monthly_adjustments`), traced every FK into them, and read the 4 consuming functions directly in tu.sql. Proposed, then rejected, a "current row + audit-log child" design (can't represent a future-dated correction without prematurely overwriting the live value). Proposed a header/version split for the 3 entity-FK'd tables + in-place transaction-time columns for the other 4, and requested independent review before drafting.

**Review round:** two independent adversarial reviews run in parallel against the live schema (Fable, `architect` subagent; Codex, `codex:codex-rescue` subagent), each instructed to actively try to break the plan rather than validate it. Both converged on the core architecture but found concrete defects: 3 UNIQUE constraints (not the 0 assumed) that block the exact same-date correction the design exists to support; a live function (`archive_rate_item_history()`) that hard-deletes from the table the patch is about to declare permanent; the `rate_items` versioning story covering roughly 30% of the retroactive-correction-sensitive columns, not the ~80% first claimed; a wrong FK-categorization test (caught independently by both reviewers, in the same table); an underspecified `change_type` enum with no value for an initial assertion and no home for a pure retraction's reason. One genuine disagreement between reviewers (where the CI-011 optimistic-concurrency version counter lives) was resolved in favor of Fable's fuller reasoning (header-level, not per-row — a single correction can touch multiple version rows, and the header-lock incidentally serializes concurrent writers on the same entity).

**Output:** `gas-billing-memory/application/a1-bitemporal-design-review-2026-08-20.md` — a full, self-contained design-review document: verified current-schema state with line numbers for all 7 tables and their consuming functions, the rejected alternative, the synthesized post-review design, both full reviews verbatim, and 5 open decisions. Written not committed this session — see HANDOFF.md Warnings. tally-utility's own HANDOFF.md rewritten to reflect this state.

**Open decisions (blocking DDL, listed in full in the design doc §5):** (1) does `rate_schedules.service_type` belong on the header or should it version too; (2) the lifecycle-vs-assertion timing model for `wna_monthly_adjustments` and `customer_tax_exemptions` (draft/pending states vs. `recorded_at` stamping); (3) orphaned draft-schedule headers — accept or gate on activation; (4) does the `as_of()` function family ship inside the A-1 patch or immediately behind it; (5) session-GUC-scoped temporal views for CI-003 — defer as a candidate or pull into scope now. Ryan is taking the design doc to a Fable xhigh-effort session to resolve these and produce the actual patch plan.

**Failed approaches / corrected claims (mechanism, not just "it was wrong"):** the FK-categorization test "does anything external FK to this table's id" was falsified by `wna_clamp_events.wna_monthly_adjustment_id` — corrected to entity-FK (must survive corrections) vs. provenance-FK (correctly pins a specific historical row). The "rate_item_history is 80% done" claim undercounted by ignoring `tier_config`/`calculation_type`/`active_months`/`is_taxable_default`/`annual_billing_anchor`/`regulatory_class`, all currently mutable-in-place with zero history — corrected to a fresh `rate_item_versions` table rather than widening `rate_item_history` (widening would require fabricating historical values for columns it never tracked). Treating `archive_rate_item_history()` and the FK cascades on these 7 tables as "flag now, fix later" was overturned by both reviewers — deferring would land a patch whose own function contradicts its stated invariant, the same "claimed cleanliness a patch didn't actually have" failure mode the v5.4.2-02 strict-apply rule already exists to prevent.

**Repo state:** tally-utility clean, no commits this session (design-only, no code touched). gas-billing-memory has one new untracked file (the design-review doc above) — not yet committed, per HANDOFF.md Warnings.

---

## 2026-08-20 (wrap, A-4 session) — session record: A-4 landed and hardened; decisions in DECISION-LOG

**What was done (full session):** resumed from the Phase 2 handoff; drafted, reviewed, mirrored and landed **v5.4.2-01** (A-4: CI-012/013/014 enforcement — generic no-hard-delete guard on 33 tables, column-scoped invoice immutability, append-only ledger/events, identity-freeze guards, REVOKEs, `void_invoice()` GUC leak closed); Ryan then requested two independent post-landing assessments (Fable, Codex — both "sound enough to build A-1 on", one MEDIUM each on the search_path claim and the direct-void gap) and the fix with the same loop → **v5.4.2-02** (`void_invoice()` schema-qualified + `search_path` pinned, direct-void gated from any status and on INSERT, all 80 guards `ENABLE ALWAYS`, DEPLOY-VERIFICATION corrected in place). Both repos pushed after each patch. Detailed per-patch entries are the two entries below and `sql/DEPLOY-VERIFICATION.md`.

**Review/assessment rounds this session:** four (two pre-landing reviews per patch) plus two assessments — six independent agent passes. Every HIGH/MEDIUM was fixed; the LOWs are documented in DECISION-LOG or the patch headers. The one consensus finding that overturned a drafting call: the `app.void_operation` leak was first filed as an application contract to avoid re-issuing `void_invoice()`; both reviewers rejected that and the function was re-issued (and then re-issued again in -02 to qualify it).

**Decisions:** twelve (D-2026-08-20-16 … -27) in `application/DECISION-LOG.md` with rationale. Headline calls: `pending` is issued; invoice immutability is column-scoped; only clean drafts are deletable; CI-013 is structural only for ledger/events/applications; the GUC carve-out is named caller-settable and gates `void` too; CI-014's set is enumerated (33) and partial; `payments.status` default left `posted`; **every patch must pass `SET search_path = ''; SET check_function_bodies = on;` standalone** — the Docker preamble had masked unqualified function bodies since v5.4.0.

**Failed approaches (mechanism):** bare `%` in `format()` and `text[] || 'literal'`; testing GUC-gated guards after `void_invoice()` in one transaction; fresh-loading through the Docker image as proof of search_path safety; `SET search_path = ''` on a definer function with unqualified helpers; writing "corrected in place" in a header before editing the file. All in DECISION-LOG § Failed approaches (both sections).

**Results:** tu.sql 13,241 → 14,499 lines (pure appends); 66 tables / 229 CHECKs / 147 triggers (80 ENABLE ALWAYS) / 275 FKs; fresh build zero errors; 89-check battery green on the fresh build; strict standalone apply clean for -02. GBM: CI-012 → structural, CI-013/014 → partial, Appendix A-4 LANDED, A-23 (+1a), Sections AN + AO; `ryan` 17 commits ahead of `origin/main`.

**Open for Ryan (untouched, listed by both assessors):** `pending` = issued; `due_date` frozen; clean drafts deletable / held never; `write_off`/`paid` non-terminal; `payments.status` default `posted`; whether to take the option-(a) SECURITY-DEFINER seal. Flagged for a factual-defect set: six unpinned SECURITY DEFINER functions; void⇔voided_at CHECK; issued-status ordering; `rate_schedules` duplicate policy columns.

**New durable artifacts this session:** `sql/v5.4.2-01-…`, `sql/v5.4.2-02-…`, AC-10..AC-13, DECISION-LOG D-16..27, memory note `strict-apply-before-mirror`.

**Next step:** Phase 4 Wave 1, **A-1** (transaction-time pair) — see HANDOFF.md Resume Instructions; run the strict-apply test from the first draft.

---

## 2026-08-20 (A-4 follow-up) — v5.4.2-02: void_invoice() hardened, direct-void gated, guards ENABLE ALWAYS

Ryan asked for two independent post-landing assessments of v5.4.2-01 (Fable, Codex) and then for the fix with the same review loop. **What the assessments found:** (1) -01's header and DEPLOY-VERIFICATION claimed `search_path = ''` cleanliness the re-issued `void_invoice()` did not have — eleven unqualified relation refs inherited from v5.4.1-01, masked by `00_preamble.sql`'s `check_function_bodies = off`; the patch file failed a standalone strict apply. (2) `void_invoice()` is SECURITY DEFINER with no `SET search_path` — Fable's reviewer later demonstrated a cross-tenant void via `evil.is_platform_admin()`. (3) A bare `UPDATE … status='void', voided_at=now()` voided a bill with no reversal/read release/charge disposition, then sealed it. (4) Only 9 of 77 guards were `ENABLE ALWAYS`. (5) Stale `void_invoice()` COMMENT. Both assessors: "sound enough to build A-1 on"; both listed the same judgment calls for Ryan (`pending` = issued, `due_date` frozen, drafts deletable, `write_off`/`paid` non-terminal, `payments` default `posted`, SECURITY-DEFINER seal) — all left untouched.

**v5.4.2-02** (`sql/v5.4.2-02-a4-followup.sql`): `void_invoice()` re-issued fully schema-qualified with `SET search_path = public, pg_temp` (`''` was tried and broke inside the unqualified `get_user_tenant_id()` helper) and a fresh COMMENT; `enforce_invoice_immutable()` gains one rule — writing `status='void'` requires the `app.void_operation` carve-out, from any prior status and on INSERT (the trigger now fires BEFORE INSERT too); all 80 immutability guards `ENABLE ALWAYS`, including the three from -06/-02. **New verification contract:** every patch must apply with `SET search_path = ''; SET check_function_bodies = on;` prepended — recorded per patch in DEPLOY-VERIFICATION, where the false -01 sentence is corrected in place. **Review round (Fable 1M/4L, Codex 1H/1M/1L):** Fable found the gate sat below the draft/held early-return and missed INSERT (held→void direct was the real hole — fixed); Codex found the header said DEPLOY-VERIFICATION was already corrected before it was (fixed by doing it) and that the pre-existing guards were still `'O'` (folded in). Fresh build zero errors; 89-check battery green; tu.sql 14,030 → 14,499. DECISION-LOG D-24..27 (plus six more unpinned SECURITY DEFINER functions flagged); AC-10/12 amended; GBM A-23 amended, CI-012 text updated, Section AO. **Next: A-1.**

---

## 2026-08-20 (A-4) — v5.4.2-01 landed: bill immutability, append-only ledger, no hard deletes

Phase 4 Wave 1 opens with A-4 (`sql/v5.4.2-01-immutability-and-append-only.sql`, 1,020 lines incl. the re-issued `void_invoice()`). CI-014: one generic `enforce_no_hard_delete()` attached as BEFORE DELETE + BEFORE TRUNCATE to 33 operational tables from a DO-block array (which also `REVOKE DELETE ... FROM tally_app`); cascades from a protected parent fail at the first protected child, which is the point. CI-012: `is_invoice_issued()` (= not draft/held; pending is issued), a **column-scoped** guard on `invoices` (what the customer saw is frozen; collections/delivery/void lifecycle stays writable; void terminal; no backward transitions; status=void requires `voided_at`), line items follow their parent (INSERT too), `invoice_events` append-only, draft invoices deletable only when nothing posted hangs off them. CI-013: `account_ledger` INSERT-only (+`REVOKE UPDATE`); `invoice_applications` write-once reversal; identity-freeze + terminal-state guards on `payments` (no return to pending), `adhoc_charges` (billed → pending only under the void carve-out), `customer_credits`. Nine guards `ENABLE ALWAYS`.

**Two concurrent independent reviews (Fable: 2 HIGH / 5 MEDIUM / 5 LOW; Codex: 2 MEDIUM).** Fixed: posted → pending → edit two-step on payments; draft delete stranding a billed charge (`fk_adhoc_invoice` is SET NULL); adhoc `description` and `billed_*` pointers editable while billed; primary keys missing from every frozen set; direct `status='void'` without `voided_at` then permanently sealed; `customer_credits.source_reference` unfrozen; CI-013/CI-014 over-claims softened. **Consensus finding that changed the design:** `app.void_operation` is a caller-settable session GUC *and* `void_invoice()` never reset its `SET LOCAL`, so Codex un-billed a charge on an *unrelated* invoice later in the same transaction. The first draft had filed that as an application contract to avoid re-issuing the 240-line SECURITY DEFINER body; both reviewers pushed back, so `void_invoice()` is re-issued with one `set_config('app.void_operation','false',true)` before RETURN (verified: `false` after the call; the cross-invoice bypass now rejected). Codex also showed `payments.status` DEFAULTs to `posted`, so the "pending intake window" exists only for callers who ask for it — rationale corrected, default left alone (AC-11).

**Mirror + fresh build:** pure append 13,241 → 14,030 lines, zero init errors, 83-check battery green on the fresh build; 70 → 147 triggers, no other catalog deltas (`sql/DEPLOY-VERIFICATION.md`). APPLICATION-CONTRACTS AC-10..AC-13; DECISION-LOG D-16..D-23. GBM: CI-012 → `structurally-enforced`, CI-013/CI-014 → `partially-structurally-enforced` (each with the precise boundary), Appendix A-4 LANDED + new A-23, parity plan Wave 1 A-4 struck, ingestion Section AN. **Next: A-1 (transaction-time pair).**

---

## 2026-08-20 (wrap) — session record: Phase 2 complete; decisions moved to a durable log

**What was done (full session):** v5.4.1-01 finished (item 2.6 + -06 carryover), second review round, mirror, fresh-build verification; v5.4.1-02 drafted, reviewed, fixed, mirrored, verified. Both repos pushed. Detailed per-patch entries are the two 2026-08-20 entries below and `sql/DEPLOY-VERIFICATION.md`.

**Decisions:** fifteen drafting decisions (D-2026-08-20-01 … -15) are recorded with their rationale in the new **`application/DECISION-LOG.md`** — the permanent home for what previously lived only in HANDOFF.md's Key Decisions table. Headline calls: 2.6 landed both halves of its either/or; half-open EXCLUDE range; the active-meter relocation gap documented (AC-7) not fixed — Kyle brief; CI-032 corrected to partial; the -02 helper has no live fallback and raises on NULL (standing rule for all future temporal helpers); the history bracket is transaction time (valid time is A-1's); backfill flagged as an approximation; two-reviewer + scratch-DB fresh-load before every mirror.

**Failed approaches (mechanism, not just "didn't work"):** `CREATE EXTENSION` without `WITH SCHEMA public` passed every live-container test and failed the fresh build because tu.sql runs under `search_path = ''` and psql sessions don't; a CI grade read from a stale scenario file instead of the register; mirror split at the wrong banner line; four fixture-column failures; the `COALESCE`-onto-live-column pattern in a temporal helper. All in DECISION-LOG.md § Failed approaches.

**Results:** tu.sql 13,241 lines; 66 tables / 229 CHECKs / 1 EXCLUDE / 70 triggers / 275 FKs; fresh build zero errors; five test batteries green on the fresh build. GBM: nine CI entries re-checked with every token unchanged, Appendix A-22, Sections AL + AM.

**New durable artifacts this session:** `application/APPLICATION-CONTRACTS.md` (AC-1..AC-9), `application/DECISION-LOG.md`, memory notes for fixture columns and the temporal-helper rule.

**Next step:** Phase 4 Wave 1, **A-4** (bill-immutability / append-only enforcement) — see HANDOFF.md Resume Instructions.

---

## 2026-08-20 (later) — v5.4.1-02 landed: tenant_configuration_history + time-aware get_partial_period_policy()

Phase 2 item 2.4, the patch the 3M brief called "the item that matters most." `tenant_configuration_history` is a key/value, JSONB-valued, append-only history of the thirteen `tenants` policy columns plus each top-level `settings.<key>`, written automatically by an AFTER INSERT OR UPDATE trigger on `tenants` — on INSERT every key is recorded, so an onboarding default becomes a recorded decision (W-tenant-onboarding item 5); on UPDATE only changed keys. Immutability/TRUNCATE/source-guard triggers, RLS + FORCE, backfill for existing tenants, identity `seq` as the same-transaction tiebreaker (found in testing: `now()` is fixed per transaction, so two changes to one key tied on both `effective_from` and `created_at`). `get_partial_period_policy()` now takes a **required** `p_as_of` and reads the tenant default from history; the one-arg time-blind form was dropped (no callers). The bracket is transaction time, not valid time — valid-time policy changes remain A-1's job, so CI-004 stays partial. Flagged, not changed: `rate_schedules` has two override columns (`partial_period_policy`, unchecked, the one read; `partial_period_policy_override`, CHECKed, read by nothing).

**Independent review round (Fable + Codex).** Consensus HIGH: the first draft's `COALESCE` onto the live `tenants` column meant `NULL p_as_of` — a realistic input, since `get_correction_rate_date()` documents returning NULL — and any pre-history coordinate silently resolved to *today's* value: the time-blind form back through the side door. Fixed: plpgsql, NULL raises, no live fallback, pre-history returns NULL like unknown-schedule. Fable also: direct inserts could impersonate the recorder and write any key/value (now CHECK-guarded + `pg_trigger_depth()` guard), the backfill stamps an observed-at-deploy value at `created_at` (kept, but stated as an approximation on every row and in the header), TRUNCATE bypass, CASCADE on the tenant FK (removed — an audit trail must outlive its tenant). Both reviewers fresh-loaded tu.sql + patch into throwaway databases — clean — so the -01 search-path class of failure was tested before the mirror this time.

**Mirror + fresh build**: pure append (12,997 → 13,241 lines), zero init errors, all five batteries re-run on the fresh build (see DEPLOY-VERIFICATION). APPLICATION-CONTRACTS gains AC-8 (never pass NULL `p_as_of`; treat a NULL result as a hard error; `settings.*` onboarding rows exist only if the app writes settings at INSERT). GBM: CI-004/006/093 re-checks (tokens unchanged), new Appendix A-22, parity plan Phase 2 **complete**, ingestion Section AM. **Phase 2 is done; next is Phase 4 Wave 1, A-4.**

---

## 2026-08-20 — v5.4.1-01 complete: 2.6 + carryover drafted, second review round, mirrored, fresh-build verified

Finished `v5.4.1-01`. **Item 2.6** landed both halves the plan offered as either/or: `meter_deployments_no_overlap_excl` (the schema's first EXCLUDE, `btree_gist`, half-open `[install_date, removal_date)` so `sync_meter_deployments()`'s same-day close+reopen still passes) plus `meter_readings.location_id`, a nullable FK snapshotted by `trg_populate_reading_location` on INSERT (deployment covering `reading_date`, else `meters.location_id`; never re-derived on UPDATE). **-06 carryover**: `pga_monthly_reconciliations` gains `low_positive`, `gas_cost_nonnegative`, `recovered_nonnegative` CHECKs (signed columns untouched). New `application/APPLICATION-CONTRACTS.md` (AC-1..AC-7) records what the schema now requires of future application code, starting with "set `start_date` on Pattern A reactivation or the EXCLUDE rejects it."

**Second independent review round (Fable + Codex) on 2.6 + carryover.** Consensus: a bare `UPDATE meters SET location_id` on an *active* meter never touches `meter_deployments` (pre-existing sync gap), so the new snapshot is single-valued but can be stale — not auto-fixed (relocation vs. typo-fix is a product ruling, Kyle brief) but now AC-7, the leading reason CI-027 stays `partially-structurally-enforced`, and the column COMMENT no longer says "unambiguous." Fable alone: the header's CI-032 claim was wrong (read off the stale scenario file; register says partial — 2.6a closes its temporal-guard half only); removal/final reads on a same-day pull-and-reinstall resolved to the *new* premise — trigger now prefers the deployment closed on `reading_date` for those purposes; plus documentation fixes (second sync-trigger rejection path, zero-day empty-range tolerance, cross-tenant silent-NULL under RLS, apply-as-owner note). Codex was wrong on CI-032 ("consistent"); verified against the register directly.

**Mirror + fresh build.** Appended as a pure append (12,279 → 12,997 lines; anchors 337/3600/3679 intact). First fresh rebuild **failed**: `CREATE EXTENSION btree_gist` needs `WITH SCHEMA public` under tu.sql's empty `search_path` — invisible all session on the iteratively-patched container. Fixed in patch + mirror; rebuild clean, zero errors; full battery re-run on the fresh build (see `sql/DEPLOY-VERIFICATION.md`). Counts: 224 CHECKs / 1 EXCLUDE / 66 triggers / 474 indexes / 273 FKs. GBM side updated in the same session (CI-017/018/027/032/118/122 re-checks, family-15 intro hedge, parity-plan Phase 2 status, ingestion Section AL).

---

## 2026-08-19 (night) — v5.4.1-01 drafted (items 2.1/2.2/2.3/2.5), independently reviewed, fixed

Phase 2 begins. Decided the patch split first (confirming the parity plan's own candidate): `v5.4.1-01` bundles items 2.1, 2.2, 2.3, 2.5, 2.6 plus the v5.4.0-06 review carryover; item 2.4 (`tenant_configuration_history` + a `get_partial_period_policy()` signature change) becomes its own patch, `v5.4.1-02`, since it's the one item that adds a table rather than tightening an existing one. Drafted four of the five `v5.4.1-01` items into `sql/v5.4.1-01-factual-defects-1.sql` (848 lines, **not yet mirrored into `tu.sql`** — items 2.6 and the -06 carryover remain, then the full mirror/rebuild/re-grade/CHANGELOG loop runs once, not per-item).

**2.1** — two new `service_orders` CHECKs closing the gap where `final_read`/`tamper_response`/`damage_repair` could insert with no customer/location/meter referent (3M item 7): `final_read` now requires all three; the two incident types require location; `customer_complaint`/`adjustment`/`other` stay deliberately unconstrained, now stated via `COMMENT ON CONSTRAINT` rather than left implicit. **2.2** — `import_jobs.idempotency_key` NOT NULL via a BEFORE INSERT trigger (a `GENERATED` column can't take an operator override; a plain `DEFAULT` can't see sibling columns) that derives `<filename>:<hash>:<preview|commit>` when no key is supplied, falling back to the row's own `id` when no file is present — fixes the preview/commit key collision as a side effect (CI-118, 3M items 2 and 8). **2.3** — cycle guards (reject, don't just log — unlike -05's depth-monitoring precedent, since depth is legitimate here and only a cycle is a defect) on three self-referencing lineage columns: `customers.landlord_customer_id` and `service_orders.parent_order_id` via ancestor-chain WHILE-walks (50-link defensive cap), `import_staging.depends_on_row_numbers` via a BFS over a visited-set since it isn't FK-backed and one row can depend on several row numbers at once. Also added `UNIQUE (import_job_id, row_number)`, load-bearing for the BFS lookup and not itself named in the plan — flagged in the header rather than landed silently. **2.5** — `account_ledger` gets `reverses_ledger_entry_id` (self-referencing FK) and `reversal_reason` (text), nullable and deliberately not paired by a CHECK, mirroring the representable-not-enforced character of the invoice/payment lineage columns it copies (CI-017/CI-018, 2026-08-13 re-grade finding). `void_invoice()` — the only place in the schema that posts a `void_reversal` row — rewritten in place to populate both, reproduced faithfully from tu.sql:1126 with exactly a lookup step + two INSERT columns + one return-payload key added.

**Two independent adversarial reviews** (one Fable-model agent, one Codex-rescue agent, same pattern as the -06 review) audited all four drafted items against the live container and the GBM source citations. Both confirmed the DDL does what its header claims and every citation checks out verbatim — and both independently caught the same real defect: item 2.2's header had re-graded CI-118 forward to unqualified `structurally-enforced`, but the `id`-fallback makes duplicate-detection conditional on the caller supplying filename+hash, which nothing enforces (both reviewers live-reproduced two file-less imports of the same logical file inserting cleanly with no collision). Reverted — CI-118 stays `partially-structurally-enforced`, with the header now explaining why via the CI-117 "when set" precedent it should have carried from the start. Fable alone also caught a genuine bug neither citation-checking nor the author's own live testing had surfaced: the 2.3c cycle guard fired only on `UPDATE OF depends_on_row_numbers`, but the dependency graph's edges key on `row_number` — not FK-protected, freely updatable — so an `UPDATE` relabeling a row's own `row_number` could complete a cycle the guard never re-checked. Fixed by widening the trigger to `UPDATE OF depends_on_row_numbers, row_number, import_job_id`; the exact bypass repro now correctly rejects. Also fixed: the BFS's 10,000-node visited-cap silently allowed rather than raising, contradicting the patch's own stated philosophy for the other two guards. Documented, not fixed: all three cycle guards race under concurrent transactions (plain MVCC, no locking) — flagged as a known limitation rather than closed with locking machinery a "low-controversy" Phase 2 item shouldn't carry. Re-verified post-fix: no regressions, full idempotent re-apply clean.

**GBM repo untouched this session** — every CI re-grade/re-check named in the patch header is still only true in SQL comments, not yet written into `canonical-invariants.md`; no ingestion log entry yet. That, plus items 2.6 and the -06 carryover, plus the full mirror/rebuild/test/re-grade loop, all remain before `v5.4.1-01` is done. **HANDOFF.md rewritten.**

---

## 2026-08-19 (evening) — Session wrap: Phase 1 complete; Phase 4 sequenced

Closing entry for the evening session. Two things happened: **v5.4.0-06 landed** (detail in the patch entry below) — the fifth and final Phase 1 migration set, making every 2026-07-10 Kyle ruling an enforced database property — and **Ryan sequenced Phase 4**, the first non-preliminary revision of the parity plan (recorded in gas-billing-memory `14f1728`, ingestion Section AK). The wave order: Phase 2's six factual-defect items first; Wave 1 foundations **A-4 → A-1 → A-3** (A-4 promoted to first — the Phase 1 patch chain made it cheap: the immutability-trigger idiom is proven three times over and the `tally_app` GRANT layer has existed since -01); Wave 2 Texas launch set **A-20 → A-21 with A-7 (PSF rider) promoted in** (PSF is on every Texas bill — launch-blocking, not reporting); Wave 3 A-2 as a cheap rider on `jurisdictions`, then A-9 → A-10, with **A-8 held pending a Kyle brief** (unruled date-effective shape — the D3-2 lesson); Wave 4 collections/comms A-14 → A-16+A-17 → A-13 → A-15 → A-18 → A-19, finance gate carried over for A-15's ledger-partition/GL parts and A-6's remainder. Verified state at wrap: **65 tables / 64 policies / 63 FORCE-RLS / 217 CHECKs**, tu.sql **12,279 lines**, both repos clean and pushed. No failed approaches this session — the -06 battery passed first run. **HANDOFF.md rewritten.** Next session: **Phase 2 (plan §2.1–2.6)**, likely as `v5.4.1-*` patches, flagging each item in a brief line per the plan's rule.

---

## 2026-08-19 (cont.) — Patch v5.4.0-06: the PGA set — Phase 1 complete

Fifth and final Phase 1 patch (item 14; Kyle ruling D3D-1). `sql/v5.4.0-06-pga.sql`: **`pga_monthly_reconciliations`** — one immutable row per tenant per month posted by the D3D-1 monitoring job (supplier gas cost, billed PGA revenue, variance, running signed deferred balance, thresholds in effect); the twelve rows of a PGA year ARE the annual true-up workpapers and survive mid-year config changes by construction (per-row threshold snapshots + no mutation). Drafting call: **immutability is trigger-enforced** (UPDATE and DELETE both raise) rather than convention like `wna_clamp_events` — D3D-1's workpaper language is stronger than T-4's clamp-and-log, and with no app layer, convention-only would grade `requires-application-discipline`. Two consistency CHECKs make each row self-verifying: variance arithmetic and threshold-band consistency against the row's own snapshotted thresholds (boundary `>=`; zero trailing revenue disables the band check). The row stores the *band*, not an alert — crossing detection and the re-alert interval stay app logic over the immutable sequence. **`pga_monitoring_settings`** — one row per tenant, 10.00/20.00 starter defaults as column defaults, optional `re_alert_interval_days`, mutable. Both tables RLS+FORCE+policy; grants via -01 default privileges. Pure-append mirror (12,138 → 12,279; anchors intact), redeployed clean, 16 constraint/trigger tests + 4 RLS smokes green (`DEPLOY-VERIFICATION.md`). Register: CI-036 → `partially-structurally-enforced (as of v5.4.0-06)`; CI-033 re-checked, token unchanged; A-6 status-updated (gas_purchases / per-class ledger / carrying cost / annual true-up workflow stay open). **Phase 1 is fully landed — next: the first non-preliminary parity-plan revision, sequencing Phase 4.**

---

## 2026-08-19 — Session wrap: five patches in one session; Phase 0 closed, Phase 1 four-fifths landed

Closing entry for the 2026-08-19 session (detail in the five patch entries below and their gas-billing-memory counterparts). Arc: Ryan ruled the role model (split roles: `tally_app` runtime + owner-as-migrator, FORCE RLS as belt-and-suspenders) → **v5.4.0-01** made the 59 policies bind someone for the first time and passed the first true end-to-end RLS test (CI-116 → `structurally-enforced`) → the ruled backlog then fell in sequence: **-02** meters & reads (D3-1/D3A-3/D3A-4), **-03** rating & WNA (D7-2/D5-2/T-4/T-3; first new tables of the chain, 59→61), **-04** the A-11 program-enrollment substrate executed verbatim with D8-2 riding along (single-slot disconnect-protection columns dropped; nine CI entries re-graded/re-checked), **-05** pipeline & events (the dry-run no-commit guarantee became a database property; D1-3 depth event; D3B-1/2 confirmation columns). Line-count discipline evolved to **pure-append mirrors** — tu.sql grew 11,351 → 12,138 lines with zero pre-existing line numbers shifted, every register citation intact. Current verified state: 63 tables / 62 policies / 61 FORCE-RLS / 207 CHECKs, deploys clean on postgres:16. Every patch runtime-tested positive and negative on the live container. GBM gained ingestion Sections AE–AI and five bookkeeping commits (branch `ryan`; `origin/main` now 11 behind, Ryan's call). **HANDOFF.md rewritten.** Next session: **v5.4.0-06, the PGA set (item 14, D3D-1)** — the last Phase 1 item — then the first non-preliminary parity-plan revision to sequence Phase 4.

---

## 2026-08-19 (cont.) — Patch v5.4.0-05: pipeline & events — the dry-run guarantee becomes a property

Fourth ruled-backlog patch (items 11–13; D3C-6/Part 4, D1-3, D3B-1/2). `sql/v5.4.0-05-pipeline-and-events.sql`: **dry-run isolation is now database-enforced** — guards on `invoices`, `account_ledger`, the read-lock transition, and `billing_runs` status; `dry_run` dropped from `run_type` (Part 4's split-brain closed); `is_dry_run` made immutable (drafting extension: a real run is a new run row). **Reversal-chain depth event** drafted as a DB trigger rather than the ruling's minimum app-layer option — never blocking, auto-emits `reversal_chain_depth_exceeded` with `{depth, severity: medium}` at link >3; depth 3 verified silent. **Item 13's app-vs-column split resolved**: columns landed (`meters.zone_/pressure_class_confirmed_at/by` pair-CHECKed; `meter_deployments.fp_mismatch_confirmed_at/by/reason` all-or-nothing), validation stays app logic. Ten-test suite green. Three workflow docs' catalog refs flipped to landed in GBM. **Remaining in Phase 1: PGA (item 14).**

---

## 2026-08-19 (cont.) — Patch v5.4.0-04: the A-11 program-enrollment substrate, with item 10

The largest ruled build lands: Appendix A-11's locked design (Q-13, 2026-05-26) plus its implementation decisions, followed to the letter, with backlog item 10 (D8-2) riding along per the plan's grouping. `sql/v5.4.0-04-programs-and-lifecycle.sql`: **`program_types`** (first platform-global reference table — 11 seeds, no RLS, read-only for `tally_app`); **`customer_program_enrollments`** (CI-046-style lifecycle, attestation columns, supersede lineage, jsonb payloads, **D8-2 `expiry_type` calendar|event** — bankruptcy holds are event-terminated rows with NULL end dates, never fake calendar dates); three guard triggers (customer_id immutable, supersede-chain validation, `do_not_disconnect` denormalization); the **clean drop of `customers.disconnect_protection_*`** (single-slot representation retired); **`compliance_statistics` rebuilt** via LEFT JOIN LATERAL with its surface preserved. Eleven-test behavioral suite all green, including RLS as `tally_app` and the read-only reference-table guard. Nine register entries re-graded/re-checked `(as of v5.4.0-04)`; A-11 marked LANDED. **Next: pipeline & events set (items 11, 12, 13).**

---

## 2026-08-19 (cont.) — Patch v5.4.0-03: the rating & WNA set

Second ruled-backlog patch (items 4–7; Kyle rulings D7-2, D5-2, T-4, T-3). `sql/v5.4.0-03-rating-and-wna.sql`: **`regulatory_class`** NOT NULL on both charge-definition sites (`rate_items` + `adhoc_charges` — the drafting call that keeps one-off charges inside Family 9's disconnect rule); the **`jurisdictions` table** (D5-2: WNA applicability is a jurisdiction property — opt-out is one row update, never a mass customer flag; WNA tariff-variant pointer targets `wna_zones`) with **`service_locations.jurisdiction_id`**, the premise's first jurisdiction FK; **WNA clamp config** on `wna_zones` (floor/ceiling/basis, CHECK-enforced) plus the append-only **`wna_clamp_events`** log (T-4 — PGW 2022; under D5-1 monthly settlement the clamp is the only guard); **`prorate_tier_breakpoints` default → true** (T-3 — existing-row review vacuous, no data exists anywhere). Schema grows for the first time in the patch chain: 59 → 61 tables, both new tables RLS+FORCE+policy (verified as `tally_app`), grants via v5.4.0-01's default privileges — that mechanism proven live. Pure-append mirror (11,533 → 11,702), redeployed clean, all constraints runtime-tested. CI-050/CI-108/CI-020 re-checked, tokens unchanged. **Next: programs & lifecycle (item 10) — lands with A-11, same substrate, per the plan.**

---

## 2026-08-19 (cont.) — Patch v5.4.0-02: the meters & reads set — Phase 1 begins

First ruled-backlog patch (items 1, 2, 8, 9; Kyle 2026-07-10 rulings D3-1, D3A-3, D3A-4). `sql/v5.4.0-02-meters-and-reads.sql`: **`meters.rollover_point`** (canonical rollover ceiling; NULL falls back to 10^`dial_count`), **`meters.meter_pressure_class`** (`residential_base`/`elevated`; retires the fragile rate-schedule-association inference), the **D3A-3 skip-reason enum** as a CHECK on the existing `read_cycle_meters.skip_reason` (with `other`-requires-`notes` enforced), and **tamper recording columns on `meters`** (`tamper_flag` with required-when-set `tamper_reported_at`/`tamper_signal_source`, plus `tamper_reason`). Drafting decisions documented in the header: tamper lives on the meter record; `tamper_confirmed` is deliberately not a column; CI-029's structural-CHECK candidate deliberately not drafted (open flag to Kyle); columns nullable because completeness enforcement is A-20's exception queue, not NOT NULL. Mirrored as a pure append (11,455 → 11,533 lines; anchors intact), redeployed clean, **all six new CHECKs runtime-tested** (invalid values rejected on the named constraint, valid rows inserted; 188 → 194 CHECKs). Register CI-023 re-checked `(as of v5.4.0-02)` — token unchanged, text updated. **Next: the rating & WNA set (items 4, 5, 6, 7).**

---

## 2026-08-19 — Patch v5.4.0-01: app role, GRANTs, FORCE RLS — the policies bind someone at last

Ryan's decision: split-role model (runtime role + owner-as-migrator), with FORCE as belt-and-suspenders. Shipped as `sql/v5.4.0-01-app-role-and-grants.sql`: non-owner role **`tally_app`** (NOLOGIN privilege bundle — production LOGIN users get membership), `USAGE`/full-DML/`EXECUTE` GRANTs plus default privileges for future objects, and `FORCE ROW LEVEL SECURITY` on all 58 RLS tables (`materialized_view_refresh_log`, ops-only, stays non-RLS by design). No BYPASSRLS role: cross-tenant tooling stays on the `is_platform_admin()` policy branch. Mirrored into tu.sql as a **pure append** (11,351 → 11,455 lines; anchors 337/3600/3679 and every other pre-existing line number unchanged). Redeployed clean, and the **first true end-to-end RLS test** ran, closing v5.4.0-00's owner-superuser caveat: as `tally_app` — unset context → zero rows; operator → own tenant only; cross-tenant INSERT → policy violation; same-tenant INSERT → succeeds; platform_admin → all tenants via the policy branch. CI-116 re-graded `structurally-enforced (as of v5.4.0-01)` in the register. Residual caveat recorded: superuser/BYPASSRLS roles bypass RLS regardless of FORCE (visible only on AWS, where the owner won't be superuser). `DEPLOY-VERIFICATION.md` updated. **Next: Phase 1, meters-and-reads migration set (backlog items 1, 2, 8, 9).**

---

## 2026-08-18 — Session wrap: the project pivots from corpus auditing to schema execution

Closing entry for the 2026-08-17→18 session (detail in the three entries below and their gas-billing-memory counterparts). Arc: independent review verified the corpus's factual layer and named the drift (internal audit loop, stalled stakeholder round-trip, unknown schema provenance) → three gates cleared (briefs delivered, grading frozen, both repos pushed with tally-utility gaining its first remote) → Ryan supplied the provenance (Kyle+Opus authored, never deployed; Ryan owns the schema; no database exists anywhere) → tu.sql v5.2.1 verified deployable, zero errors, freeze lifted → **v5.4.0-00 shipped**: Supabase substrate removed for the AWS PostgreSQL target, runtime-tested, line counts preserved. **HANDOFF.md fully rewritten for the new phase** — the corpus-era handoff with the full Failed Approaches list is preserved at commit `785884b`. Next session: the app-role/GRANTs patch (v5.4.0-01 — until it lands, the 59 RLS policies bind no one), then Phase 1's meters-and-reads migration set.

---

## 2026-08-18 (cont.) — Patch v5.4.0-00: Supabase substrate removed; target is PostgreSQL on AWS

Ryan's decision: AWS-hosted PostgreSQL, no Supabase. Only two functions carried the dependency — `get_user_tenant_id()` and `is_platform_admin()`, the wrappers all 59 RLS policies route through — so the swap to the `app.user_id` session GUC (fail-closed) converts the entire RLS layer without touching a policy. Shipped as `sql/v5.4.0-00-remove-supabase-substrate.sql` (first numbered patch of the new chain), mirrored into tu.sql with line counts preserved (11,351 lines; register anchors 337/3600/3679 verified unmoved), header rewritten (maintained-in-place canonical source, patch discipline, AWS target), preamble reworded. Redeployed clean and runtime-tested: no context → NULL/false (fail-closed); operator → own tenant, not admin; platform_admin → true. Caveat recorded: tests ran as the table owner, whom RLS never binds — the app role + GRANTs and the FORCE-RLS call are now the first item of Phase 2. `DEPLOY-VERIFICATION.md` updated with the v5.4.0-00 section.

---

## 2026-08-18 (cont.) — tu.sql v5.2.1 verified deployable; freeze lifted; `sql/DEPLOY-VERIFICATION.md` added

Provenance finalized by Ryan: the schema was authored by Kyle with Claude Opus and never deployed anywhere with data; the one test run's machine died; `application/database/schema.sql` was a tables-only export for LLM parsing (now formally a column-reference document). With no live database to chase, the baseline question reduced to deployability — and **tu.sql deployed clean on fresh postgres:16 via the repo's own `postgres/Dockerfile` harness, zero errors, all objects confirmed** (59 tables / 49 triggers / 59 policies / 23 functions / 188 CHECKs / 352 indexes / 252 FKs / 58 RLS tables / 0 FORCE-RLS / 6 views incl. matviews). Two corpus findings independently confirmed from the live catalog: all FKs single-column, and CI-116's missing `FORCE ROW LEVEL SECURITY`. The register's grading freeze is lifted (rule 4 rewritten in gas-billing-memory); parity plan Phase 0 marked substantially complete. **Next: Phase 1 — the ruled v5.4 backlog, five migration sets plus A-11.**

---

## 2026-08-18 — Cover note to Kyle; preliminary schema parity plan

Two artifacts, both in `gas-billing-memory` on the `ryan` branch: **`configurable-rules/kyle-cover-note-d3-2.md`** (a short note pointing Kyle at the retraction brief first, with the coda brief's routing flagged — Ryan delivers it out-of-band) and **`application/schema-parity-plan.md`** (preliminary, no DDL). The plan is provenance-gated: Phase 0 demands a current schema dump or the v5.3+ patch files before any migration is drafted, since v5.2.1 is three months stale and CI-019 already cites objects this repo cannot see. Phase 1 is the ruled work (13 live Part 5 backlog items in five migration sets, plus A-11's locked substrate); Phase 2 is six factual-defect hardening items; Phase 3 holds the judgment-gated items with the question each waits on; Phase 4 defers the Appendix A tail. Each landed patch regenerates the snapshot in this repo's `sql/` under numbered patch files and re-grades exactly the CI entries it names — which is how the 2026-08-17 grading freeze lifts.

---

## 2026-08-17 — Independent review, then the three gates cleared

**A fresh session reviewed the whole run against INVESTIGATION-BRIEF.md and spot-checked the load-bearing claims** — register grade counts (4/53/40/38, exact), the `read_type` fact (real; `meters` only), the `void_released` guard and COMMENT (as quoted), and the §4-refutation basis (`schema.sql` carries 59 PK / 587 NOT NULL and zero procedural objects — the refutation holds). **Verdict: the factual layer is sound and the post-brief investigation was done well; the drift is directional** — an internal audit loop while the stakeholder round-trip and schema provenance sat untouched. One handoff self-contradiction fixed (the 54/37 vs 53/38 register counts — chronological narration, now labelled).

**Three gates cleared the same session:**
1. **Delivery.** `gas-billing-memory`'s five pending commits — the re-grades and the D3-2 retraction brief — pushed to `origin/main` (fast-forwarded through the `ryan` working branch). The repo is the delivery channel; the retraction is flagged to read first; the coda brief's security/finance routing is in its own opening. An out-of-band ping to Kyle, if wanted, is Ryan's.
2. **Grading freeze.** Register warning-block rule 4: no enforcement re-grading until the patch chain or a current schema dump is in the repo; all 58 checked grades stamped as-of v5.2.1. Logged as ingestion Section AA.
3. **Push state.** This repo given its first remote and pushed — eight handoffs had existed on one machine only.

**Deliberately not done:** the two queued correction commits stay queued behind Kyle's round-trip (3G–3H hazard); the 77 untested `requires-application-discipline`/`unenforced-gap` entries stay untested — their grades claim *non*-enforcement, which the discovered failure mode (over-claiming enforcement) does not threaten.

---

## 2026-08-14 — Checked all 42 `partially-structurally-enforced` entries: 39 hold, 3 corrected

**CI-077 → `unenforced-gap`.** Its basis was "`deposits` table exists"; **it does not exist**, and the schema has **no credit-evaluation column of any kind** — the invariant's actual subject has zero substrate.

**CI-098 amended** — the UNIQUE on `import_jobs.idempotency_key` is not unconditional; the column is nullable. **CI-093 amended** — cited CI-099's half as structurally-enforced (stale), and carries a pre-existing internal contradiction (weakest-composing-link rule vs its own grade) now **flagged in-entry, not resolved unilaterally**.

**Not defects:** CI-060/062/063/082 and others cite tables that do not exist *while explicitly labelling them v5.4 forward-references or absences*. That is correct practice — the error is naming a missing object **as though it exists**.

**Parser failure, third this investigation:** the sweep missed CI-077 because substring matching suppressed `deposits` against the index `idx_payments_deposits`.

**Coverage: 58 of 135.** Untested: 40 `requires-application-discipline`, 37 `unenforced-gap`.

---

## 2026-08-13 — Re-graded all 16 `structurally-enforced` invariants: 12 down, 4 survive

Applied to the register with dated notes preserving each original grade. `structurally-enforced` **16 → 4** (CI-007, CI-051, CI-117, CI-119); `partially-structurally-enforced` **42 → 54**.

The four survivors share one shape: **a NOT NULL column inside a constraint, or the demonstrable absence of a column.** Nothing else in the register has survived inspection.

**Two previously-unknown missing mechanisms, both outside the original 21:** `account_ledger` has **no reversal lineage FK** (CI-017 claims one — a financial audit-trail gap, route to the finance owner); `meter_readings` has **no service-point column** and tu.sql has **zero EXCLUDE constraints**, so CI-027's "recorded" premise is reconstructed and unguarded against overlapping deployments.

**Self-correction:** my first pass marked CI-017/CI-027/CI-032 correct on a shallower check — confirming columns exist is not confirming an invariant is enforced, the exact failure mode under investigation. Also fixed a miscount ("six remain untested" — all 16 had been).

**Untested:** the **42** pre-existing `partially-structurally-enforced` entries.

---

## 2026-08-13 — The `schema.sql`-Source hypothesis is refuted (INVESTIGATION-BRIEF §4)

**Tested on all 21 entries plus a control group. It does not survive, and its premise was factually false.**

The brief characterised `application/database/schema.sql` as "tables, columns, and FK references only." It carries **59 PRIMARY KEY, 38 UNIQUE, 587 NOT NULL, 442 DEFAULT** — the full declarative layer short of CHECK. Most of the 21 entries' claims *are* derivable from it. §4 inferred "cannot support enforcement claims" from "lacks procedural objects."

**21 entries:** 10 correct, 7 defective, 4 overstated/unresolved. **Control group falsifies it** — of the 2 structurally-enforced entries not citing `schema.sql`, **CI-072 is defective**, naming a `service_orders` technician-assignment column that does not exist. The correlation was selection, not contamination.

**Three new defects:** CI-016, CI-099, CI-128. **CI-072 is a PHMSA gas-safety claim and needs routing to a safety owner.** Two of the register's three named impossibility proofs are not impossibility proofs.

**Surviving hypothesis:** the predictor is the **grade**, not the source — a column's existence read as enforcement without checking nullability or prevention. Re-grade population is **58 (16 + 42), not 21**.

**Result:** `gas-billing-memory/application/invariants/schema-source-hypothesis-test-2026-08-13.md`.

---

## 2026-08-13 — The schema is not final, and there are two of them

**I did not know this, and it invalidates two of yesterday's corrections.**

`sql/tu.sql` is **schema version v5.2.1** on a documented chain from v4.8. `application/database/schema.sql` (2026-05-14, 60 tables, 1,748 lines) is an **earlier, still-present** schema file that many register entries cite by name.

**Reverted:** (1) rewriting CI-025's Source from `schema.sql` to `tu.sql` on the invented premise of a rename — two different files, both extant; (2) dismissing CI-031's "lines 672–676 of schema.sql" as stale — those lines are **exactly** the billing-lock columns cited. I graded a correct, well-provenanced citation as defective.

**What survives:** the `read_type` finding, which was never a versioning artefact — the column is on `meters` in **both** schemas, and `schema.sql`'s `meter_readings` already had `read_method`/`reading_purpose`/`is_estimated`. The D3-2 retraction stands.

**The real consequence:** every enforcement grade and line-number citation in the corpus is a claim about a moving target, and none records the schema version it was made against. Entries that cite file *and* version are doing it right; I removed that provenance. New standing rule recorded in the handoff.

## 2026-08-13 — The D3-2 retraction brief (eleventh, and the first to retract a ruling)

`d3-2-retraction-and-read-lock-brief.md`. Eight briefs now open; this is the one to send first, being the only one that corrects something already acted on.

Different in kind from the other ten: it withdraws a decision rather than requesting one. Part A retracts D3-2 and v5.4 backlog item 3. Part B puts the verified `void_released` gap in its place — the same concern Kyle was reaching for, at the right columns and in the state that matters. Part C keeps the register-reliability statement unsoftened, with one sharpening: **CI-025's grade was defensible and survives; the evidence underneath it was false.** A wrong grade invites re-reading; a wrong fact stated in the grade's own field does not.

Two misattributions caught before commit — crediting the schema's own COMMENT to CI-031, and dropping CI-120 from the enforcement-status list. Both are the kind of error that costs a brief its standing, in a brief whose whole subject is a claim nobody checked.

## 2026-08-13 — The overcorrection, and a real gap where the fabricated one stood

Yesterday's fix **overshot**. It replaced "no constraint forbids UPDATE post-acceptance" with "once a read is locked, the trigger structurally forbids UPDATE to all three type columns" — ignoring the guard. Block 2 fires only while `validation_status = 'locked'` and is skipped during the void transition. **Three unprotected states**, and the third matters: after a void, `billing_period_locked` stays `true` while the status becomes `void_released`, **so the whitelist stops applying to exactly the reads a correction run consumes.** The void carve-out is also wholesale rather than scoped, gated on a caller-set session variable.

**So there is a real hardening item precisely where the fabricated one stood** — right instinct, wrong column set, wrong state. Offered to Kyle as a replacement for struck backlog item 3 rather than letting it vanish.

**The sequence is the lesson.** Wrong → subtler wrong → overcorrected → right, with confidence increasing at every step. The guard sat three lines above the field list I did read: I quoted the list and not the condition governing it. An overcorrection is as much a defect as the error it fixes, and a correction that *strengthens* a claim needs more scrutiny than one that weakens it, because it is the one that gets quoted.

**Independently verified, and the check strengthened it.** I had called `void_released` "the window in which a correction is computed." It is not a window — the guard tests `OLD.validation_status`, so the bypass holds for **every** update while the read rests there, no void flag and no privilege needed. **A harness lesson came with it:** four background validators with broad briefs delivered nothing across three rounds of requests; a fifth, given six closed questions and run synchronously, returned a complete correct report in one pass. Scope and synchronicity were the fix.

## 2026-08-13 — The fabricated column reached a Kyle ruling and the v5.4 backlog

**The most consequential find of the WU6 run, and yesterday's fix missed it.** `read_type` did not stop at the register. Full path: `gap-analysis-v5.2.1.md` line 61 → its CI-025 entry → `wu5-axes-review-brief.md`, which escalated it to Kyle as "a real fix candidate" → **Kyle's ruling D3-2 (2026-07-10)** → **v5.4 consolidated schema backlog, item 3: "`read_type` post-billing lock trigger."**

**A column that does not exist produced a stakeholder decision and a scheduled schema patch.** Kyle's intent — a read's type must not be mutable after billing — is correct and **already enforced**: `is_estimated`, `read_method` and `reading_purpose` are all in the locked-read trigger's field block. The ruling stands as policy; the patch is void. Item 3 struck with reasoning attached; the ruling itself left intact, because a record of what Kyle decided must remain one.

It also caused a **false confidence upgrade** — CI-025 was raised medium→high *because* D3-2 "resolved" the gap. `high` now rests on the corrected evidence instead.

**Yesterday's own correction was incomplete**, and its note misnumbered the affected lines and missed three, including the document's executive-summary statement of the claim. The lesson I wrote yesterday — sweep the corpus, not the files that surfaced the defect — was under-executed: I swept for the column *name* and never asked **what decisions the claim had already produced.** A propagated error's blast radius is in decisions, not only prose.

**Kyle needs to be told**: he ruled on a false premise and the ruling carries a work item.

## 2026-08-13 — Validation pass over the 2026-08-12 corrections

Four independent validators — register corrections, origin/propagation fixes, an independent re-derivation of the column sweep, and the summary layer separately.

**The biggest defect was mine, and caught before the validators reported.** The sweep claimed ten nonexistent `table.column` references. **Four are real**; six were places where **the corpus correctly states the column does not exist** or proposes it for Appendix A-23. The worst miss: `payments.account_id`'s seven references are **the corpus's own A-12 correction** — a finding it made and got right — which the sweep re-reported as a defect.

**The script found *mentions*; I read them as *assertions*.** Whether a mention is a claim, a denial or a proposal is in the surrounding sentence. This is the standing absence-claim lesson inverted — that one asserts a gap from a grep that found nothing, this asserted an error from a grep that found something. Both substitute a hit-count for a reading. The stated exclusion list was incomplete for the same reason.

**The wrong-table class survives** and is still the part worth keeping: three of the four real errors name a real column on the wrong table, invisible to a name grep.

Two further self-caught fixes: the "seven to eight" corpus split is **seven to seven** (the count was taken after my own edits had contaminated it), and B4's function-reference claim proved to be a **two-generation error** — corrected once already, to a subtler wrong claim that *strengthened* the conclusion, and self-verified rather than independently checked.

## 2026-08-12 — Session 3A carry-back closed: the three supersession columns

The second half of the carry-back, and it resolved into a **decision for Kyle** rather than a correction.

3M's B4 called this "two columns for one operation, one of them dead." **Neither is dead.** Only `replaces_reading_id` / `replaced_by_reading_id` form a **bidirectional pair** — which is precisely what CI-030's "queryable in both directions" clause requires. `replaces_read_id` has **no inverse column**, so a chain built on it is forward-only. Yet its own COMMENT, the `validation_status` COMMENT, and both trigger error messages all send implementers to it. **The documented path cannot satisfy the invariant, and the path that satisfies it is undocumented and unindexed.** CI-030 now carries the evidence table; picking the winner is a schema decision.

**Two corrections to my own 3M brief.** B4 said `replaces_read_id` is "referenced twice inside `enforce_reading_validation_workflow()`" — both hits are inside `RAISE EXCEPTION` message *text*; **no function reads any of the three.** And B4's "the corpus cites the live one four times and the others zero times, so it picked correctly" was **false when written** — the split is seven to eight.

**The lesson is about process, not schema.** Two of those `replaces_reading_id` citations are in coda files written *after* B4 flagged the hazard, by the author of the warning. A finding parked in a stakeholder brief does not protect the corpus in the interval before it is read. Land carry-backs in the register when found.

## 2026-08-12 — The `read_type` correction: four invariants fixed, and the origin found

Applied the 3A carry-back. **All four corrections make their entries stronger, which was not the expected outcome.**

The column doesn't exist because the schema **decomposed** the concept into three orthogonal `NOT NULL`, CHECK-constrained columns — `is_estimated` (+ `estimation_reason`), `read_method`, `reading_purpose`. CI-025 described one field with a six-value vocabulary; the schema has a better model and the entry never caught up. **CI-025 and CI-030 were also understating their own enforcement**: both claimed the columns are unprotected post-acceptance, when in fact the billing-period lock is the boundary — after it, the validation trigger names all three columns individually and raises. **CI-031's follow-up was wrong twice**, asking for a patch to add a nonexistent column to a whitelist that already covers the three real ones.

**The origin is `gap-analysis-v5.2.1.md`, and it is the most transferable lesson of the run.** That entry applied the *right method* — read the trigger's whitelist, test membership — and got a false positive, because a membership test cannot distinguish "absent from the list" from "absent from the schema." It graded the gap High and named a v5.4 patch. Corrected in place rather than deleted; the failure mode is worth keeping.

CI-025 keeps its now-inaccurate title deliberately — retitling would break `[[CI-read-type-discipline]]` corpus-wide.

## 2026-08-12 — Corpus-wide column sweep, prompted by `read_type`

If the register can assert a column that does not exist, the question is how many others do. So every `` `table.column` `` reference in the corpus was checked against `tu.sql`: **ten distinct nonexistent references, ~30 occurrences, four inside `canonical-invariants.md`.**

The finding worth carrying forward is the *second* class. Three of the ten name a **real column on the wrong table** — `invoices.total_amount` (it is on `billing_runs`), `tenants.partial_period_policy` (on `rate_schedules`; the tenant column is `default_partial_period_policy`), and `read_type` itself. **A grep for the column name resolves, so the check passes and only the table is wrong** — which makes this the class most likely to produce a confidently wrong finding, and the class no name-based verification catches. It is also the third arrival of the `partial_period_policy` lesson by a third route.

One fix applied (a residual 3M `read_type`); the rest recorded as a second correction pass, **deliberately unapplied** for the same reason as the 17 miscites. The checker is committed at `application/tools/colcheck.py` with its limitations in the docstring — it flagged `payments.check_date`, which exists, so every hit was re-verified by hand.

## 2026-08-11 — Validation pass over the sixteen coda files — ~40 defects, and the first register error to reach output

Five independent agents: four over the sixteen files in groups, one over the summary layer (the brief and Section W) per the standing lesson that a validated file is not a validated summary.

**No underlying finding was refuted.** Three recommendations were *inverted* by evidence, which is the pass earning its cost: `customer_contacts` exists, so the third-party-notification recommendation went from "build a party model" to "stop duplicating the one you have"; `idx_customers_id_number` exists — a partial composite lookup that **is** the fraud-match use the brief had asked Kyle about — so the identity recommendation went from truncate to encrypt-and-keep-the-index (`pgcrypto` is installed and unused); and A-11 already carries attestation columns as first-class.

**The worst defect was a fabricated column.** `meter_readings.read_type` does not exist — the real columns are `read_method`, `is_estimated` and `estimation_reason`, and `read_type` is on `meters`. It was the central column of `portal-usage-temperature-overlay` and appeared in four places. **I did not invent it: the register asserts it.** That makes it the first time a register error has propagated into corpus output instead of being caught at the boundary, and it changes the shape of the standing warning — every prior enforcement-status lesson was about a *grade* being wrong, which re-reading catches. A wrong *fact* does not announce itself.

**Scope corrected while writing this entry up (2026-08-12): four invariants assert it, not the two first reported** — CI-025 (twice), CI-030, CI-031 and CI-090. **CI-025 is titled "Read Type Discipline,"** so an invariant is named for a column that does not exist on the table it governs, and CI-031's follow-up note asks for `read_type` to be added to a trigger whitelist it can never be added to. A **residual instance outside the coda** also turned up: `import-error-handling-policy.md` from Session 3M, in a file the 3M pass had cleared — because the sweep covered the files that surfaced the defect rather than the corpus. Both corrected. **A defect inherited from a shared source is a corpus-wide grep, not a local one.**

**CI-116 came off the correctly-graded list.** Its read-isolation clause is graded `structurally-enforced` on a sentence that is true regardless of query *text* and false regardless of connection *role* — no table sets `FORCE ROW LEVEL SECURITY`, and RLS does not apply to a table's owner. Fourth enforcement-status error in five sessions. It had been cited as a reassuring counterexample in four consecutive briefs without being re-checked, which is its own lesson and is now in Failed Approaches.

Also corrected: 56+1 identical policies, not 57; twelve defaults at INSERT of thirteen columns; CI-050 → **CI-049** for the allocation-order cite; three consent decisions, not four; `service_locations` has no zone column; `payments.channel` already carries `'portal'`; eleven identity columns, not nine; and Section W's duplicated stale "Next:" paragraph, carried over from Section V and contradicting the section above it.

**Remaining:** seven briefs open, two of which need routing to a security and a finance owner; the cross-reference correction pass (17 miscites, deliberately unapplied); and the Session 3A carry-back, now two items — `meter_readings`' three supersession columns, **and CI-025/CI-090's nonexistent column**, which is corpus-register work rather than workflow work.

## 2026-08-11 — WU6 coda review brief (tenth and final)

`wu6-coda-review-brief.md` — eight items, five corpus patterns, Part C.

The structural difference from the previous nine: **this brief has more than one reader.** Items 1 and 2 are platform-security findings (RLS role enforcement; no customer-facing identity at all) and are both the most serious items and the least likely to be Kyle's call; item 3 is an accounting-architecture question. So the brief opens with a routing table rather than assuming a single audience — that seemed more useful than burying two security findings in a gas-billing brief.

It amends the 3M brief's B1 in place (two of the sixteen were deliberately deferred by A-11, not missed), and states plainly that the sixteen coda files have not yet had the independent validation pass the 3M files got — with Part A's counts, not its schema facts, flagged as the place to check me. It also names my own triage error from the coda session.

All 20 CI references and every cited database object verified.

**Remaining after this:** six briefs plus this one open with Kyle; the cross-reference correction pass (17 miscites, deliberately unapplied); the Session 3A carry-back for `meter_readings`' three supersession columns; and an independent validation pass over the sixteen coda files.

## 2026-08-11 — WU6 coda: the sixteen unproduced workflows

Sixteen workflows written; corpus 140. **Part 2's inventory is now fully covered — 80 named, 80 produced, zero remaining.** Logged as Section W.

The premise needed correcting mid-session, and the 3M brief's B1 with it: at least two of the sixteen were **deliberately deferred** by A-11's locked design, not missed. Writing them anyway is consistent with the corpus's own practice — 3J produced the budget-billing workflows for a program type on the same deferred list.

The real finding is why the rest were unproduced: **their substrate does not exist**, and the absences cluster rather than scatter — customer identity, consent capture, company books, role-based access. Thirteen sessions of billing work never reached the platform's non-billing edges.

Two are security findings. 57 of 59 RLS policies are identical and none reads `role`, so `viewer` is a full read-write account and self-promotion to `platform_admin` is one `UPDATE`. And there is no customer-facing identity at all, so a portal built on the current model would expose every customer the tenant's whole book — CI-116 isn't violated, it just guarantees tenant isolation and the portal needs customer isolation.

The third structural absence: no general ledger and no accounting period, on a schema where CI-110 names `account_ledger` as the accrual's home and `account_ledger.customer_id` is `NOT NULL`.

The pattern I'd most want carried forward is smaller and cheaper: **`customers` already contains the consent/verification triples the schema is missing elsewhere** — donation opt-in has flag+date+source, `id_verified` has flag+actor+timestamp — and the four decisions with real legal weight (E-SIGN consent, the ACH authorization, the §7.45 waiver) have none of them. Every fix is copying the pattern four columns away.

**My own triage error is recorded in Section W**: I reported "no identity-verification substrate" from truncated grep output. There are nine identity columns and it is one of the better-provisioned areas. Caught before it reached any file, but it is the same infer-an-absence-from-a-bad-grep failure already on the Failed Approaches list.

## 2026-08-11 — Validation pass over Session 3M, then the 3M review brief

Four independent validators across two rounds (the first summary-layer agent never delivered; a fresh one covered the brief as well). **Fifty defects total; none refuted a finding; two findings came out materially stronger; the brief was rewritten twice.**

**Round 1 — the seven source files (29 defects).** Two upgrades, both from a validator attacking the *evidence* rather than the conclusion. The tenant-config headline had rested on `void_rebill_threshold` being consumed by the cancel-rebill path — **nothing reads it**, and its COMMENT describes a routing decision, not a computation input. The real instance was one function away: `get_partial_period_policy(p_rate_schedule_id)` ships today, takes no date parameter, and reads the live tenant column, while `get_correction_rate_date()` sits in the same file bracketing the rate side. Separately, `awaiting_billing_action` *does* have a purpose-built aging index and the anomaly types already exist, so the corrected finding — "storage layer prepared, operational surface never built" — is truer and cheaper to fix than "nobody noticed."

**Round 2 — the brief and the summary layer (21 defects).** The brief had regressed in one place the source files got right: it invoked **CI-005** for the proration finding, and CI-005's enumeration ("rates, riders, factors, tax rates, zone assignments, customer-class assignments") does not cover a proration policy — the identical enumeration problem the same item describes for CI-004 four paragraphs later. It now rests on CI-006 and CI-093. The validator also found **`invoice_line_items.partial_period_policy_applied`**, a per-line snapshot of the resolved policy that genuinely narrows "no provenance" — conceded in the brief, with the residual stated: the snapshot defends an audit, not a replay. And **`ai_confidence < 0.85` is already declared "Tenant-configurable" in its COMMENT**, which makes it a different (and more tractable) defect than 0.70, not the "structural twin" the draft claimed.

**Two of my own process errors, same root cause.** Chaining `cd repo-A && … && git add -A && git commit` left the working directory wrong for the second command: once it committed an unrelated Obsidian clipping to the wrong repo under a misleading message (caught before push, reset), and once it silently no-op'd this CHANGELOG's 2026-08-11 entry — which is why this entry is being written after the fact, on the validator's finding. **Use `git -C <repo>` and absolute paths; never rely on cwd surviving a chain.**

Also corrected: 23 functions in `tu.sql`, not 22 — in an item whose own lesson list names the 2026-08-10 function-inventory error; `matched_by` is five routes plus `none`, not six; **seven** of the sixteen unproduced workflows are cited by produced files, not five, and 3M's own workflow added two of them; and B2's miscite breakdown now sums correctly (7+3+3+2+2=17), with `final-bill-generation.md`'s two reclassified as unresolved slugs rather than counted into the seventeen.

## 2026-08-10 — Session 3M: Domain 13 (Import & Admin), clusters 58–60 — WU6's rule domains complete

Seven files in `gas-billing-memory` (corpus 124): decision tables `import-error-handling-policy` (#58), `import-column-mapping` (#59), `service-order-type-routing` (#60); workflows `bulk-data-import-with-validation`, `import-dry-run-preview`, `service-order-creation-and-dispatch`, `tenant-configuration-change-rollout`. Logged as Section V. **Domains 1–13 done.** Cluster 58's real name is `import-error-handling-policy` — `import-validation-severity` appears only in forward-pointers.

**The session's argument is one sentence at three altitudes: a value that determines a bill is stored as a current value with no history and no provenance.** Tenant configuration at the policy level, the import path at the record level, the service order at the event level. Twelve sessions established that a rate gets history plus an archive, a meter gets lineage, a tariff gets a documented split, a read gets supersession — and the admin surface that populates and reconfigures all of them gets `UPDATE`. That is what happens when a domain is modelled as tooling rather than as data with billing relevance.

**Three headline findings.** The feature list grades three import error policies as required-and-supported against a two-value column, while both outcome counters and a tri-state sibling enum already exist — a **fourth** hypothesis register demonstrated wrong, and the first that is a feature list rather than an invariant register. **CI-118 is graded `structurally-enforced` on a UNIQUE over a nullable column**, inside the one family whose introduction claims duplicate imports are structurally impossible; three of that claim's four members hold and this one does not — third `Schema enforcement status` error after CI-077 and CI-120. And **thirteen tenant policy columns plus a seven-sub-object settings blob are current-value-only**, which CI-004's own statement forbids — the quieter failure here is that CI-004's enforcement note lists neither their presence nor their absence, so no amount of re-reading the entry would have surfaced it. `void_rebill_threshold` feeding the cancel-rebill path makes CI-005 and CI-006 unsatisfiable.

**Corpus integrity.** The cross-reference re-run returned 17 mismatches — the same total as 3L and a **different set**, which is the session's most transferable lesson: a reproduced number validated nothing until the composition was reconciled. Reconciling corrects a sub-count in Section U (subpoena-readiness is miscited seven times, not six; 3L's headline of 17 was right). All 252 FKs are single-column, which corrects 3L's "one place" framing about cross-tenant references — it is every place, and CI-116 is graded correctly and simply does not cover it. And Part 2 names 80 workflows against a header of 51, of which **16 will still have no file and no owning session** after 3M — recommend a coda session.

**0 cross-reference errors in the seven new files.** Script rebuilt with both prior corrections and validated against a known answer *before* use rather than after. Two of my own claims were caught in self-review and corrected before commit — one count wrong, one number invented ("thirty-nine clusters"; the measured figure is 28 of 60), the latter being exactly the fabricated-specificity failure the 2026-08-10 lesson names.

**Not done at the time of writing:** the independent-agent validation pass and a 3M review brief. **Both were completed 2026-08-11 — see the entry above, which supersedes several claims here.**

---

## 2026-08-10 — Session: Validation pass over 3I/3J/3K-collections, then the three outstanding review briefs

**Second half of the session: wrote the three briefs**, from the corrected findings rather than the drafts. `wu6-sessions-3i-3j-review-brief.md`, `wu6-domain-11-review-brief.md` (both 3K halves), `wu6-session-3l-review-brief.md` — 434 lines total in `gas-billing-memory`, committed as `95256d5`. **Five briefs are now open with Kyle and all twenty-two items are briefed.**

The Domain 11 brief is the one that gained most from being written as a pair: the two halves fail in opposite directions — the service side can *do* something unlawful, the deposits side can fail to *act* when unprompted — so fail-closed and fail-open are both correct, and the brief proposes one rule generating both (*the unevaluable case resolves against the party that controls the data*) rather than two conventions someone has to remember the direction of.

Three items are pitched differently than the drafts would have had them: the `provider_transaction_id` UNIQUE is CI-055 compliance rather than a suggestion, the tax divergence cannot be absorbed into v5.4, and the disconnect aggregation is six of nine substantive bars with two more degraded. Cross-reference check run before shipping — all 26 CI citations resolve.

---

## 2026-08-10 — Session: Validation pass over Sessions 3I, 3J and 3K-collections

Ran the 2026-08-09 validation technique over the three remaining unbriefed sessions — three independent agents, one per session, each re-verifying every claim in its section of `wiki-ingestion-pending.md` against `sql/tu.sql` and the cited documents. **Thirty defects across nineteen files in `gas-billing-memory`; all twelve Kyle open items survive on substance.** No fabricated database objects; one invariant miscite (CI-095 → CI-068).

**By session:** 3I seventeen defects (CI-051 scoped to Family 7, not the corpus — there are sixteen `structurally-enforced` invariants; `credit_aging_statistics` does branch on `deposit_refund`; `provider_transaction_id` does have a partial index; six denormalized totals not five; Reg E revocation is §1005.10(c) not (d)). 3J three (the `preferred_contact_method` correction had missed the Inputs table row; "nine inputs" is seven of thirteen). 3K-collections ten (the six-of-eleven aggregation was internally contradictory — nine substantive bars, six unevaluable, two degraded, one clean; `service_orders` has thirty-five columns not twenty-nine).

**Two findings got stronger, not weaker.** CI-055 already *requires* the deduplication the missing UNIQUE would provide, so that item is an unmet obligation rather than a suggestion. And A-11 rebuilds `compliance_statistics` for the protection columns only, so nothing on the v5.4 path closes 3J's tax divergence — the independent fix is necessary.

**Method note.** In both 3I and 3K-collections, several defects existed **only in the wiki-ingestion summary and not in the source files** — the compression dropped scope qualifiers the files stated carefully. The summary is what a reviewer reads, so it needs validating separately from the files it compresses. Separately: one validator's own count was wrong (it read two *degraded* bars as unevaluable), caught by recounting per bar — the check needs checking too.

---

## 2026-08-09 — Session: Work Unit 6 Session 3L (Domain 12 — Customer / Account Lifecycle)

Drafted clusters 56–57 and three workflows in `gas-billing-memory`. Five files: `billing-responsibility-resolution` (#56, first-match), `service-transition-charges` (#57, unique); `customer-move-in`, `customer-move-out`, `landlord-tenant-responsibility-transition`. WU6 output now **117 files**; **Domains 1–12 complete**, Domain 13 remaining.

**Shape decision made first, as the handoff instructed.** The inventory left Domain 12 open ("folded into the workflows that consume them; Session 3L **if rows warrant**"). Both clusters were written **standalone**, on consumption rather than row count — cluster 56 is read by five workflows plus every dunning and disconnect decision in Domain 11.

**Substrate verified first, and three verifications carried the session.** `service_locations.customer_id` is **`NOT NULL`** — so a premise is defined by its current occupant. The string **`move_out` appears zero times** in `sql/tu.sql`, and the word **"vacancy" appears exactly once — inside the documentation for `turn_on_minimum_vacancy_days`**, a defaulted setting whose input therefore does not exist. And `rate_schedules` carries **two** columns for the partial-period policy where `get_partial_period_policy()` reads only one.

**The session's argument.** Domains 11 and 12 fail the same way for opposite reasons. Domain 11's obligations are things the LDC must *do* unprompted; Domain 12's events **leave no trace at all** — a move-out with no date, an obligor change with no event, an occupancy with no tenure. Where Domain 11 could not notice a moment had arrived, Domain 12 cannot say a moment ever happened. Both reduce to the discipline CI-004 and CI-121 already state and nothing implements: **the relationship facts are date-effective data, stored as current values.**

**Five open items:** **a premise cannot exist without an occupant while CI-120 says it can** — graded `partially-structurally-enforced` on a true-but-not-load-bearing fact, leaving only two turnover implementations (repoint, which silently re-attributes history; or duplicate, which fragments the premise), **second confirmed error in the enforcement-status field**; **the move-out has no date anywhere, and closing the account removes it from the two views that would notice the deposit refund the closure just made mandatory** — obligation created and monitoring switched off by two steps of one workflow; **`partial_period_policy_override` is read by nothing**, so a tenant setting the column named *override* silently gets the tenant default, and the corpus's own gap analysis credits it as the mechanism; **a change of obligor is a bi-temporal event modelled as a boolean**, in a schema with rate history, deployment lineage, mid-period tariff splits and read supersession — and the switch produces no read, so any period split is an unmarked estimate outside the estimation governance; and **a move-in turn-on is filed as a reconnection** because no order type or charge type exists for it, polluting the dataset Domain 11's regulated rules and the deposit triggers both read — though `meter_readings.reading_purpose` does carry `turn_on`/`turn_off`, so the act is named in the reading vocabulary and the fix is a copy rather than a design.

**Corpus-integrity finding, kept separate from the domain items.** A mechanical check of all **402 `[[CI-…]]` wikilinks across the 112 WU6 files** against the 135 canonical entries found **17 wrong invariant numbers across 12 files** — including `final-bill-generation.md` transposing both its lifecycle citations, and an off-by-one family (CI-006-for-CI-005) alongside the CI-005-for-CI-004 one, which together look like a **renumbering after some rule files were written**. A separate 30 links use short-form alias slugs and **28 of those are fine** — the alias convention is used inside `canonical-invariants.md` itself, so they are not defects. **Deliberately not corrected** — six affected files are cited in briefs with Kyle, and a silent renumbering mid-review is the hazard the 3G–3H amendment raised. Recommended as **one reviewable commit of its own**.

**Method note.** The new technique is mechanical — extract every cross-reference and resolve it against the canonical entries. It found seventeen wrong numbers nine sessions of careful reading missed, because a wrong number beside a right name reads as correct — but only after **two corrections to the check itself**: the first regex required a bare `(CI-NNN)` and skipped `(CI-NNN — commentary)`, and alias-slug links could not be number-checked at all, which hid five of the seventeen. **Three hypothesis registers now:** Appendix A (wrong six times, silent once), `Schema enforcement status` (wrong twice), and the cross-reference layer (wrong seventeen times). CI-121 is graded correctly, which is worth recording — the corrections are only worth anything if the register is trusted where it is right.

Logged in `wiki-ingestion-pending.md` Section U and both CHANGELOGs.

---

## 2026-08-07 — Session (cont.): Work Unit 6 Session 3K-deposits (Domain 11 pt 2 — Write-Off, Deposits & Unclaimed Property)

Drafted clusters 51–55 and five workflows in `gas-billing-memory`. Ten files: `write-off-eligibility` (#51, priority), `customer-credit-scoring` (#52, unique, **`pending`**), `deposit-eligibility-and-waiver` (#53, priority, **regulated**), `deposit-refund-and-interest` (#54, unique), `deposit-alternatives-and-triggers` (#55, first-match); `agency-placement`, `write-off-authorization`, `escheatment-processing`, `deposit-refund-processing`, `deposit-interest-accrual-cycle`. WU6 output now **112 files**; **Domain 11 complete**, Domains 12–13 remaining.

**Substrate verified first, and two verifications carried the session.** There is **no `deposits` table** in `sql/tu.sql` — fifty-nine tables, none of them that one — and the string **`interest` appears exactly once** in the whole schema, as `customers.deposit_interest_earned`.

**The argument mirrors part 1 and inverts it.** Part 1 found a pipeline that could not verify the law permitted what it was about to *do*. Part 2 finds obligations to **act unprompted** — refund the deposit, waive it, remit the property, notice a trigger came due — with no mechanism to notice the moment arrived. Part 1's unevaluable case had to fail *closed* because the action harms; here it fails *open* because inaction harms. Unifying rule, worth adopting corpus-wide: **the unevaluable case resolves against the party that controls the data.**

**Five open items:** **CI-077 asserts a `deposits` table that does not exist** while CI-125/129/130/131 all correctly read `unenforced-gap` — the invariant corpus contradicts itself, and the entry claiming enforcement is the one governing the regulated 1/6 cap; **deposit interest is one mutable column** with no rate, no history, no accrual event, no ledger movement, in a schema shipping full bi-temporal rate machinery for gas — with the day-30/day-31 retroactivity cliff every natural paraphrase gets wrong, uniformly, across the whole book; **the refund monitoring is pointed at the wrong event** (`deposit_refund_overdue` detects an issued-and-unpaid credit; a trigger that never fired produces no credit, so no anomaly — blind to the statutory failure, vigilant about its sequel); **the grain pattern has crossed from awkward into unsafe**, since per-invoice write-off with no customer-level approval capture and no aggregate threshold lets a $1,000 limit clear a $4,000 relationship in eight compliant steps; and **Q-6's affirmative half has no substrate** — `family_violence` appears nowhere, and every failure in the deposit-waiver path runs toward charging a deposit that is not owed.

**Two procurement criteria, corpus total now seven** — a collection-agency agreement (recall acknowledgement, dispute intake, bankruptcy cease) and, contingently, credit-bureau furnishing, **recommended out of scope for launch**. At seven across four sessions the recommendation is to consolidate into one vendor-criteria list rather than keep appending.

**Method note.** Item 1 came from a new technique — **cross-entry consistency-testing**, reading CI-077 against its four siblings. Prior sessions tested the appendix against the schema; this one tested the corpus against itself. Both the appendix and the enforcement-status field are hypothesis registers.

Logged in `wiki-ingestion-pending.md` Section T and both CHANGELOGs.

---

## 2026-08-07 — Session (cont.): Work Unit 6 Session 3K-collections (Domain 11 pt 1 — Collections & Disconnect)

Drafted clusters 46–50 and six workflows in `gas-billing-memory`. Eleven files: `collections-bypass-evaluation` (#46, priority), `dunning-step-routing` (#47, first-match), `disconnect-eligibility` (#48, priority), `cold-weather-moratorium` (#49, unique), `reconnect-eligibility-and-fees` (#50, first-match); `bypass-conditions-evaluation`, `dunning-event-action`, `disconnect-order-creation-and-dispatch`, `disconnect-field-execution`, `reconnection-request-and-gas-relight`, `bankruptcy-stay-and-adequate-assurance`. WU6 output now **102 files**; Domains 1–10 complete, Domain 11 half-drafted.

**First session to take the inventory's split.** Ten clusters would have doubled any prior session. The seam runs between the service side (46–50, up to restoration) and the money-at-end-of-life side (51–55 plus write-off, agency placement, escheatment). `escheatment-processing` regrouped into 3K-deposits, since Session 3I showed its dormancy problem is really a deposits question.

**The session's argument is an aggregation, not a single finding.** Sessions 3G–3J each surfaced absences that read as feature deferrals in their own domain. Here they compose: **cluster 48 — the last gate before a household loses heat — can currently evaluate roughly one of its eleven bars**, and the one that works checks the platform's own state machine rather than the customer's circumstances.

**Four open items:** **no holiday calendar**, so both §7.45 working-day clocks are uncomputable while `mail_batch_skip_holidays` advertises the capability — the failure is systematically *early*, disconnecting two working days before the statute permits across every holiday week; **the EWE moratorium is self-executing and unlearnable** (no weather feed, no county-to-station mapping, no daily temp or forecast, `county` nullable; the existing `wna_*` data is monthly, zone-keyed, winter-only, and WNA-tenants-only — wrong on all four axes) against §7.460's civil-penalty table; **nothing makes an eligibility determination expire**, so a technician works Monday's authorization on Thursday — **and this one is not in Appendix A at all**; and **D9-1 cannot be implemented** for want of two photo-type enum values, a `service_order_id` FK, an approval record, a service-order event log, and a role model.

**Three procurement criteria surfaced** — weather feed, acknowledged cancellation in the field-service integration, bankruptcy scrub — bringing the corpus total to five with 3H's print-vendor assertion and 3I's lockbox postmark tier. Worth stating as a pattern: **regulatory obligations here repeatedly terminate at a vendor capability, so vendor selection is a compliance activity, not a purchasing one.**

**Method note.** Appendix-testing produced items 1, 2 and 4. Item 3 came from the opposite direction — asking what happens *between* two documented states. The appendix has now been wrong six times and **silent** once; silence is harder to find because there is no claim to test.

Logged in `wiki-ingestion-pending.md` Section S and both CHANGELOGs.

---

## 2026-08-07 — Session (cont.): Work Unit 6 Session 3J (Domain 10 — Programs & Assistance)

Drafted clusters 43–45 and six workflows in `gas-billing-memory`. Nine files: `budget-billing-eligibility-and-trueup` (#43, unique), `dpa-eligibility-and-breach` (#44, priority), `program-enrollment-eligibility` (#45, collect); `budget-billing-enrollment`, `budget-billing-trueup`, `budget-billing-exit`, `dpa-creation`, `dpa-payment-progress`, `dpa-breach-handling`. WU6 output now **91 files**; Domains 1–10 of 13 drafted.

**Substrate verified absent first.** `customer_program_enrollments` and `program_types` are **not in `sql/tu.sql`** — the v5.4 patch has not landed, so this domain is drafted against a locked design with the current single-column substrate's limits named per row.

**The organizing finding is a precedent rather than a gap.** A-11 says the enrollment lifecycle mirrors CI-046's tax-exemption pattern — and it does. But the scalar that pattern replaced was kept "for backward compat" and **has drifted in production**: `should_charge_tax()` reads only `customer_tax_exemptions`, `compliance_statistics` reads only `customers.is_tax_exempt`, nothing syncs them, and both directions are live today. That is exactly what v5.4 will reproduce for disconnect protection unless A-11's `do_not_disconnect` trigger lands — so the finding **validates** the locked design and prices the cost of skipping its least glamorous element.

**Four open items:** the drifted migration precedent; **`do_not_disconnect` maintained by no trigger today** while `compliance_statistics` short-circuits on it and `idx_customers_protection` indexes it — an active medical certificate with an unset flag reads as unprotected and is invisible to the fast path, which given DE-9's documented-deaths framing is the highest-consequence instance of this class in the corpus and exists *before* v5.4; **a premise→customer grain change** that budget billing and DPAs hit independently (one nullable `location_id` closes both); and **`elderly_disabled` likely miscategorized** as a disconnect protection by the same reasoning Kyle used to close Q-6.

**Correction to Session 3H — and this one was my own error, not the appendix's.** Both `delivery-method-routing.md` and the **open** 3G–3H brief asserted `customers.preferred_contact_method` has no CHECK constraint. It has a 5-value CHECK. Corrected in place, with the brief's note written to be read before the original claim. The correction **sharpens** 3H item 2: two properly-constrained enums with deliberately different value sets look like two columns answering different questions, on which reading the opposite defaults are not a contradiction at all.

**Method note.** Running total is **six material errors across four sessions**, in both directions — plus a new subcategory this session: an authoring error of mine, found by the same appendix-testing technique, already propagated into a live brief. The technique should be pointed at this corpus's own prior output, not only at Appendix A.

Logged in `wiki-ingestion-pending.md` Section R and both CHANGELOGs.

---

## 2026-08-07 — Session: Work Unit 6 Session 3I (Domain 9 — Payments)

Drafted clusters 39–42 and six workflows in `gas-billing-memory`. **Ten files — the largest single WU6 session so far.** Decision tables: `payment-posting-allocation` (#39, priority), `overpayment-and-credit-disposition` (#40, priority), `nsf-and-ach-return-handling` (#41, first-match), `autopay-eligibility-and-failure` (#42, first-match). Workflows: `lockbox-remittance-ingestion` [addenda], `payment-gateway-webhook-handling` [addenda], `ach-return-handling`, `autopay-enrollment-and-management`, `unapplied-cash-resolution` (CSR), `refund-processing`. WU6 output now stands at **82 files** across Sessions 3A–3I; Domains 1–9 of 13 are drafted.

**Domain 9 inverts Domain 8's shape** — substrate-rich and rule-poor. The reversal-lineage machinery is genuinely well built, `customer_credits` is a compliance-grade unclaimed-property substrate, and CI-051's no-PAN-storage discipline is the corpus's only `structurally-enforced` invariant. What is missing is narrower: the columns settled decisions need to read, and the functions that would keep five denormalized balance totals honest.

**New failure mode for the corpus: a *resolved* decision that turned out to be unexecutable.** Prior sessions found gaps under open questions. Kyle closed Q-5 with D7-1's tiered payment-class allocation, and the tier that overrides the posting order — agency/pledge, "restriction stored on the payment record" — has no field to store it in and no way to be told apart from an ordinary customer payment.

**Four open items:** D7-1's unexecutable tier (no payer-class or restriction columns; three enums all describe something else); `invoice_applications` being **per-invoice, not per-charge**, so CI-050's regulated-first floor has no expression even after D7-2's `regulatory_class` lands — contradicting CI-049's own schema-status line; **A-12 being two gaps under one name**, with `payments.unapplied_amount` plus a purpose-built partial index already solving the amount-mismatch case while the unidentified-*payer* case remains a total blocker (and `payments` lacking the balance CHECK `customer_credits` has, with **no payment-posting function anywhere in the schema**); and the escheatment dormancy clock **hardcoded to 1095 days for every `origin_type` in a shipped materialized view**, against the catalog's own Texas per-property-type finding — under-reporting deposits by roughly eighteen months.

**Design note:** Session 3H's E-SIGN delivery-consent substrate and this session's Reg E debit-authorization substrate have near-identical shapes and should be scoped as one consent table with a type discriminator, not two near-duplicates six weeks apart.

**Second procurement criterion in the corpus:** lockbox postmark capture is a priced vendor service tier. Without it, Kyle's 2026-06-12 Texas timeliness ruling is unimplementable for mailed payments — the same shape as Session 3H's print-vendor criterion.

**Narrows Session 3H item 2** rather than compounding it: cluster 42's "Check #4 fix #3" has its substance recorded in the catalog under the 2026-06-12 review in Kyle's voice, so mislabeling is likelier than an unrecorded ruling.

**Method note.** Five of ten files produced their sharpest finding by testing an Appendix-A or enforcement-status claim against `sql/tu.sql`; three were wrong, in both directions. At three sessions and five errors, the appendix is a hypothesis register, not an inventory — and the schema-hardening estimate derived from it will be wrong both ways until each entry is re-checked.

Logged in `wiki-ingestion-pending.md` Section Q and both CHANGELOGs.

---

## 2026-08-06 — Session (cont.): Work Unit 6 Session 3H (Domain 8 — Delivery & Communications)

Drafted clusters 36–38 and four workflows in `gas-billing-memory` (`60a4557`, pushed). Seven files: `delivery-method-routing` (#36, first-match), `communication-language-format` (#37, unique), `notice-and-alert-triggering` (#38, collect); `invoice-pdf-generation-and-retention`, `email-delivery-with-fallback` [addenda], `print-vendor-handoff` [addenda], `consolidated-invoice-assembly`. WU6 output now stands at 72 files across Sessions 3A–3H; Domains 1–8 of 13 are drafted.

**Domain 8 is the gap-densest domain in the corpus** — A-16 (outbound communication log), A-17 (notice-template versioning), and A-18 (bill-image archive) stacked, plus a fourth absence not in Appendix A at all. Per CI-095's own consequence, every notice the platform fires today is regulatorily not-sent.

**Four open items:** no E-SIGN consent substrate while `billing_delivery_method` defaults to `email` (the condition §101(c) prohibits); "Check #4 fix #4" cited by the inventory with **no source document anywhere in the KB**, alongside two adjacent `customers` columns defaulting to opposite channels; A-16's outcome enum being one field short of CI-135's content-to-envelope match assertion while A-17 overstates its own gap (`bill_messages` supplies most of the shape) and **`bill_messages` rows are mutable, a live CI-094 violation**; and no declaration of whether a collections step gates on `sent_at` or `delivery_confirmed_at` — the cheapest item, reaching three domains.

**Method note worth carrying:** two of the four came from testing an *Appendix A claim* against `sql/tu.sql` rather than from reading the schema cold. Combined with Session 3G's CI-134 finding, the appendix has now been materially wrong twice in two sessions. It should be treated as a hypothesis to test, not a settled inventory.

**Correction to Session 3G, made in place.** The claim that a bill dispute "has nowhere to live except `customers.billing_hold_reason`" was too strong — `customer_interactions` carries `reason='high_bill_complaint'` with an `invoice_id` FK and a full status lifecycle. The corrected ask (add disputed amount and protection linkage to existing substrate) is smaller than what was originally implied.

Logged in `wiki-ingestion-pending.md` Section O and both CHANGELOGs. Pushed and level with `origin/main`.

**Brief compiled the same session** (`c4a36cc`): `wu6-sessions-3g-3h-review-brief.md`, the fifth in the series, spanning both sessions' 14 files. Part A carries the four items above. **Part D is new to the brief format** and holds two things that aren't rulings — a proposed fourth option closing the *previous* brief's open consolidated-ledger question (children post; the parent is a presentation-and-payment construct, because the customer pays against the document carrying the invoice number), and the print-vendor procurement criterion. It opens with the methodological note rather than a question, and carries the Session 3G dispute correction in its narrowed form so Kyle meets the corrected version first.

**Two briefs are now outstanding simultaneously** — a first. They're independent, but eight Part A items across two documents is a lot to hand over at once; if Kyle wants a sequence, 3G–3H first, since its "Check #4" item resolves cheaply and changes the cost of the E-SIGN item beside it.

**Next:** Session 3I — Domain 9 (Payments), clusters 39–42.

---

## 2026-08-06 — Session (cont.): Work Unit 6 Session 3G (Domain 7 — Pre-Mail QA & Exceptions)

Drafted clusters 33–35 and four workflows in `gas-billing-memory` (`8e22bc6`, pushed). Seven files: `statistical-anomaly-detection` (#33, collect), `absolute-baseline-qa` (#34, collect), `exception-threshold-and-routing` (#35, first-match); `pre-mail-exception-review`, `canary-account-reconciliation`, and the two workflows deferred from 3F — `pre-mail-bill-correction` and `high-bill-dispute-intake-and-resolution`. WU6 output now stands at 65 files across Sessions 3A–3G; Domains 1–7 of 13 are drafted.

**What this session's schema reading produced** (third session running with no research agents — the substrate was already in `sql/tu.sql`):

- **CI-134's enforcement-status claim does not hold.** It reads "canary expected values are configured … not a missing-table gap," which is what classifies it `requires-application-discipline` rather than `unenforced-gap`. There is no canary table, no `is_canary`/`is_test_account` column, and no reserved settings key — the canary accounts cannot be identified, so their expected values cannot be stored. There is likewise no revenue-requirement or rate-case entity. Two of the invariant's three baselines are gaps, and **A-20 does not cover a canary registry**, so it would fall through the schema-hardening queue.
- **Nothing in `tenants.settings` is release-blocking.** The four cycle-level thresholds that exist are aggregates of the batch's own contents — skip rate, estimation rate, anomaly rate, amount swing — not comparisons against an external baseline, so a misconfiguration in place since the prior cycle passes all four. All four are named `warning`.
- **The pre-mail gate is nearly off on default settings.** `review_required_anomalies` defaults to a single read-level value, and the `anomaly_type` enum has no bill-amount values to add.
- **No bill-level dispute entity**, despite a complete read-level one. `disconnect_protection_type = 'pending_dispute'` exists with nothing to fire it.
- **Action #40 answered from the schema side:** HDD exists, but zone-keyed via WNA, winter-months-only, and absent for non-WNA tenants.

**Structural observation carried into 3H:** the per-bill gate is structurally enforced (`invoices.status = 'held'` with reason/timestamp/actor and a trigger), while the cycle-level gate CI-134 calls higher-leverage has no structure at all (`billing_runs.status` has no held value). Delivery is likely to have the same asymmetry, since CI-135 is a batch-level assertion about a vendor handoff.

Logged in `wiki-ingestion-pending.md` Section N and both CHANGELOGs. `gas-billing-memory` pushed and level with `origin/main`.

**Next:** Session 3H — Domain 8 (Delivery & Communications), clusters 36–38. First thing to check: `invoices.delivery_method` defaults to `'email'` while Check #4 fix #4 made `mail` the default — an apparent live contradiction.

---

## 2026-08-06 — Session (cont.): Work Unit 6 Session 3F (Domain 6 — Billing Run, Corrections & Backbilling)

**Status:** Same working session as 3E, continued. 14 files — six decision tables (clusters 27–32) and eight workflows — committed as `gas-billing-memory 5b10d7e`. WU6 now stands at Sessions 3A–3F done, 3G–3M remaining. No application code written.

### Done
- **Session 3F — Domain 6, clusters 27–32:** `backbilling-cap-enforcement` (#27, priority), `correction-and-void-eligibility` (#28, priority), `cancel-rebill-bitemporal` (#29, unique), `billing-run-read-gating` (#30, first-match), `invoice-consolidation` (#31, unique), `adjustment-authorization` (#32, priority).
- **Eight workflows:** `billing-run-normal-cycle`, `billing-run-offcycle`, `final-bill-generation`, `cancel-rebill-operator-correction`, `cancel-rebill-regulatory-retroactive`, `adjustment-with-approval-threshold`, `bulk-account-adjustment`, `backbilling-limit-compliance-review`.
- **Consolidated the Phase 0–9 billing pipeline**, which existed only as scattered `sql/tu.sql` column comments, into `billing-run-normal-cycle`: Phase 0 run initiation · 1 candidate selection · 2A estimation · 3 consumption · 4 rate items · 5 ad-hoc charges and correction rate dates · 6 invoice assembly · 7 operator review · 8 posting · 9 PDF and delivery. Agrees with CI-100 and is more specific.
- **Logged in `wiki-ingestion-pending.md` Section L** and the `gas-billing-memory` CHANGELOG.
- **Deferred deliberately:** `pre-mail-bill-correction` and `high-bill-dispute-intake-and-resolution`. Part 2 files both under pre-mail/correction, but pre-delivery correction is a different operation from void/rebill and belongs with Session 3G's pre-mail QA cluster set.

### This domain differs from every prior one: the code already exists
`void_invoice()` is a ~270-line function implementing most of cluster 28's mechanics — voidability validation, cross-tenant defense-in-depth, read release to `void_released`, ad-hoc charge disposition, `void_reversal` ledger posting, `invoice_events` logging. `get_correction_rate_date()` implements cluster 29's resolver. The tables mostly specify what those functions *don't* do, which is a different authoring job than Domains 1–5 and produced sharper findings.

### Five open items surfaced, in order of consequence
1. **DE-3's gas guard doesn't exist and the schema argues against it.** DE-3 requires gas correction runs to reject `correction_rate_mode='current'` via a hard guard, and marks it a proposed new invariant. It was never implemented, never added to `canonical-invariants.md`, and **both relevant column comments document `current` as existing precisely for the wrong-meter case** the prohibition would forbid. Governs cluster 29 and both cancel-rebill workflows identically.
2. **Backbilling is unenforced end to end.** No cap table (A-2), no cause column, no period check in `void_invoice()` — current behavior is unbounded backbilling for every cause, including ones §7.45 caps at three months. Underneath: the cause enum can't be derived from `invoices.void_reason_code`'s seven *operational* values, and **`rate_misapplication`'s 6-month rule is a collectability protection (disconnection prohibited), not a rebill window** — so the cap table holds two different kinds of limit in one enum.
3. **Consolidated invoices: nothing says whether parent or children post to `account_ledger`.** Both double-counts and breaks CI-019; parent-only hides per-location arrears from collections; children-only leaves the delivered artifact with no ledger presence.
4. **No aggregate authorization.** Ten thousand $1 adjustments each pass the per-charge threshold a single $10,000 adjustment would fail. No aggregate concept in the schema, and no bulk-operation entity to hold a reviewed population.
5. **Unapproved charges aren't excluded from billing pickup.** The documented Phase-5 predicate doesn't test `requires_approval` / `approved_at`, while the approval queue's partial index defines exactly those charges as outstanding — approval is currently advisory.

Two smaller findings: cluster 32's threshold must compare `abs(amount)`, since `amount` is signed and a naive `>=` leaves credits ungated — the direction that costs money; and `adhoc_charges.voided_from_invoice_id`'s comment documents the correction audit chain with its last hop pointing the wrong way.

### One coherence worth recording
`void_invoice()`'s auto-revert reason set (`wrong_read`, `wrong_rate`, `service_date_error`, `system_error`) has as its complement exactly the void-only-eligible set (`wrong_customer`, `duplicate`, plus `other`). Where a rebill is coming the charges ride it automatically; where no corrected bill may exist a human decides each one. It reads as two unrelated `UPDATE` branches until they're lined up — worth naming so nobody "simplifies" the duplication away.

### Method
Same as 3E and for the same reason: no research agents, reading `sql/tu.sql` directly against `canonical-invariants.md` Families 1, 2, 13, and 16 plus the catalog, DE-3, and action #9. All five open items came from that comparison. Two sessions in, this looks like the right default for domains whose substrate already exists in the schema — the prose docs and the schema disagree in specific, findable ways, and only reading both surfaces them.

### Next
Session 3G — Domain 7 (pre-mail QA and exceptions), clusters 33–35, carrying CI-134's mass-error gate and DE-10's tenant-tunable thresholds. `billing-run-normal-cycle`'s Exc 4 already names the seam it inherits.

---

## 2026-08-06 — Session: Commit the pending fold-in, then Work Unit 6 Session 3E (Domain 5 — Taxes & Fees)

**Status:** Two units of work. First, the prior session's Kyle-decisions fold-in was sitting uncommitted in `gas-billing-memory` (52 files edited, 1 renamed) — committed as `fe435cc`. Then Session 3E drafted: 4 decision tables + 1 workflow, committed as `fe07a10`. WU6 now stands at Sessions 3A–3E done, 3F–3M remaining. No application code written.

### Done
- **Committed the orphaned fold-in** (`gas-billing-memory fe435cc`). Kyle answered both consolidated review briefs on 2026-07-10 (`application/wu5-wu6-kyle-decisions-2026-07-10.md`); the prior session applied all 40+ resolutions across 52 files but never committed. Nothing was lost — but it had been sitting in the working tree for a day with no commit, which is exactly the state a `git stash`, a branch switch, or a wrong `git checkout` destroys silently.
- **Session 3E — Domain 5 (Taxes & Fees), clusters 23–26** (`gas-billing-memory fe07a10`): `tax-application-and-stacking` (#23, rule-order), `tax-exemption-eligibility` (#24, unique), `adhoc-charge-taxation` (#25, priority), `franchise-fee-application` (#26, first-match), plus the `tax-exemption-cert-submission-and-renewal` workflow.
- **Drafted a workflow the Part 3 queue doesn't list for this session.** The queue says "tax steps fold into billing-run" — correct for the *application* steps, but `tax-exemption-cert-submission-and-renewal` is a Part 2 customer-lifecycle workflow whose entire subject is cluster 24's substrate. Writing it in Session 3L would mean writing it cold, months after walking CI-046. Session 3L inherits it instead of producing it.
- **Logged in `wiki-ingestion-pending.md` Section K** and the `gas-billing-memory` CHANGELOG, per the standing rule that every canonical-data change on main gets a wiki-ingestion target.

### Key finding: this domain's central substrate doesn't exist
Unlike Domains 1–4, cluster 23's per-jurisdiction loop iterates over `tax_jurisdictions` — gap A-8, a table that isn't in the schema. Stated plainly in the table rather than written around: for Texas launch that loop has one or two iterations driven off `service_locations.inside_city_limits`/`franchise_city`, not the eight-jurisdiction stack `11-taxes-and-gl-accounting.md` describes. The implementable slice today is essentially cluster 26 alone.

### Four schema-shaped open items surfaced, deliberately not resolved
Same discipline as Sessions 3A–3D's four tensions — each is a conflict between two things that both look authoritative, so picking a side silently would encode a wrong assumption downstream.
1. **`rate_items.is_taxable_default` defaults to `false`.** CI-045's central named silent failure is a new charge type rolled out with no explicit tax-base classification defaulting by omission. The schema default *is* that failure, under-collecting, and it makes "explicitly false" indistinguishable from "never decided."
2. **`franchise_fee_rules.applies_to` vs. the per-item `is_taxable` chain** — two mechanisms for one concept, diverging whenever any item is non-taxable, and none of `applies_to`'s four enum values can express "gross revenue minus PSF," the one carve-out 16 TAC §8.201 mandates. Decides whether CI-038's exclusion is implementable today or blocked on schema work. The session's most consequential item.
3. **Two exemption substrates, one wired.** `should_charge_tax()` reads only `customer_tax_exemptions`, never the legacy `customers.is_tax_exempt` flag kept "for backward compat." The sharper consequence: the renewal-prompt machinery CI-046 asks for **already exists — on the substrate being retired** (`tax_exemption_expiry_date` + a 60-day `expiring_soon` view). CI-046's "renewal-prompt gap" is really a never-ported prompt.
4. **`franchise_city` lives on both `service_locations` and `rate_schedules`**, both indexed, no stated precedence. The tables assume premise-side authority (per CI-044) and say so, so the assumption is visible if it's wrong.

Two smaller defects got suggested resolutions but were left for Kyle too: the platform charge-type defaults list enumerates 16 of 17 `adhoc_charges.charge_type` values and omits `miscellaneous` — the one type with no semantics to default from — and the taxability settings key is spelled two different ways between the schema comment and the catalog.

### What the schema already got right
`should_charge_tax(customer_id, item_is_taxable, service_type, as_of_date)` implements CI-046's valid-for-the-period rule correctly today, with its own comment instructing callers to pass a historical date on corrections. Cluster 24 is therefore largely a specification of an existing function, not a proposal — which is why its priority scenario asserts that *callers* pass the period date rather than testing the function.

### Method note
No research agents this session, a deliberate break from Sessions 3A–3D. The grounding — Texas §182.025/§182.024, §8.201 PSF, §7.45, Tax Code Ch. 151 ad-hoc defaults, the 2026-06-12 residential-taxability review, D6-1/D6-2 — was already in the KB and in `sql/tu.sql`. Reading the schema directly against `canonical-invariants.md` Family 6 is what surfaced all four open items above; none of them are visible from the prose docs alone, because each is a disagreement *between* the schema and a doc. Authorship manual throughout, same as every prior session.

### Next
Session 3F — Domain 6 (billing run, corrections, backbilling), clusters 27–32. None of the six open items above blocks it.

---

## 2026-07-05 — Session: Work Unit 5 completion (Families 14–17) + Work Unit 6 Sessions 3A–3D (Configurable-Rules)

**Status:** WU5 (Method 1 per-invariant scenario docs) is now fully complete — all 17 canonical-invariant families represented across 15 docs. WU6 (Configurable-Rules Sessions 3+) is underway — Sessions 3A through 3D done (Domains 1–4 of 13). Two consolidated Kyle review briefs compiled and awaiting answers. No application code written.

### Done
- **Finished WU5:** drafted axes-of-variation docs for Families 14 (`read-exception-handling-and-estimation.md`), 15 (`tenant-isolation-and-structural-integrity.md`), and 16 (`account-lifecycle-mimo-and-final-bill.md` + `deposits-credits-and-operational-integrity.md`), then ran the **Family 17 fold-in pass**: CI-132 (regulatory posture) into the Family 13 doc, CI-133 (transport eligibility) into the Family 4 doc, CI-134 (batch absolute-baseline mass-error gate) into the Family 14 doc, CI-135 (print-mail PII-breach classification) into the Family 12 doc — closing the deferral every one of the prior 13 family docs had explicitly left open.
- **Compiled `wu5-axes-review-brief.md`** (`gas-billing-memory c042493`): a consolidated, plain-language Kyle-facing brief spanning all 17 families, built by having 5 parallel research agents extract "Next steps" judgment calls from the docs not already in working context, then synthesizing directly. Part A: new judgment calls by family. Part B: the 10 still-open Q-numbers from the WU4 brief, now mapped to the exact doc/axis each blocks. Part C: 2 doc-placement calls.
- **Started and progressed WU6** (Configurable-Rules Sessions 3+, one rule domain per session, per `cluster-and-workflow-inventory.md`'s Part 3 queue) — the first work on this track since the WU3 scoping session:
  - **Session 3A** (Domain 1: Reads, Validation & Estimation) — 6 decision tables (clusters 1–6) + 6 workflows (`gas-billing-memory b0f87fd`).
  - **Session 3B** (Domain 2: Gas Measurement & Consumption) — 4 decision tables (clusters 7–10) + 4 meter-lifecycle workflows (`d830ddd`).
  - **Session 3C** (Domain 3: Rating & Tariff Engine) — 9 decision tables (clusters 11–19, the queue's own largest single domain) + 4 workflows (`2f2bc23`).
  - **Session 3D** (Domain 4: PGA / WNA / Gas Cost Recovery) — 3 decision tables (clusters 20–22) + 3 workflows (`4c97fbf`).
  - Method: for each session, dispatched 3–4 parallel Explore-agent research tasks to ground the drafting (exact schema/catalog column names, named real-world failure incidents, statutory values) before personally authoring every table and workflow file — research was delegated, authorship never was, to keep voice and cross-referencing consistent across 39 files.
- **Compiled `wu6-decision-tables-review-brief.md`** (`1c58a37`): the same consolidated-brief treatment applied to all 39 WU6 files, synthesized directly from the session's own work (no new research needed). Leads with 4 genuine tensions between two sources that both look authoritative, rather than picking a side silently.
- **Found and corrected a stale cross-document status**: `canonical-invariants.md`'s status line and Flagged section still listed Q-3 (WNA deadband scoping) as open, but `de-review-answers.md` shows Kyle resolved it on 2026-06-12 — the invariants-doc update was the action item itself and it never happened. Fixed `canonical-invariants.md` (Q-3 entry, CI-041 upgraded medium→high confidence, top status line), `weather-normalization.md` (the WU5 Family 5 doc, which had inherited the stale status), and `wu5-axes-review-brief.md` (which had incorrectly asked Kyle to re-answer something he'd already resolved three weeks earlier).

### Decisions (and the "why NOT")
- **Family 17's 4 residual invariants folded in one batched pass**, only after all 16 topic families existed. NOT done incrementally as each home doc was drafted, because every fold-in cross-references invariants living in its own home doc — batching avoided rework against still-changing predecessors.
- **The stale Q-3 status was fixed forward**, not left as a note for Kyle to sort out. NOT leaving it, because it was actively producing wrong output — the WU5 brief was asking Kyle to re-answer a question already closed three weeks prior. It surfaced by accident (mid-research for Session 3D's WNA table), which both CHANGELOGs flag as a process gap worth a lighter-weight periodic reconciliation check.
- **WU6's 4 genuine tensions (PGA correction path — cancel-rebill vs. deferred-account; `pga-monthly-trueup`'s possibly-wrong name; the `prorate_tier_breakpoints` schema default contradicting CI-108's own stated invariant default; whether the WNA adjustment needs a floor/ceiling guard) were surfaced explicitly, not resolved unilaterally.** NOT picking a side, because each pits an invariant statement against a named failure-mode description (or a schema default against its governing invariant) with textual support on both sides — a wrong unilateral call would propagate into every downstream scenario derived from these 39 files.
- **Research delegated to parallel Explore agents; authorship was not.** NOT having agents draft the tables/workflows directly, to keep the voice, rigor, and cross-referencing density consistent with the 15 WU5 docs already establishing that pattern.

### Errors caught & resolved (process note, not a code bug)
- **Accidental Agent spawns while waiting on background research.** Used `Agent({prompt: "placeholder"})` several times intending only to trigger a wait-and-resume, which instead spawned 6 real agents that took the literal placeholder text as their assignment and began investigating on their own. Caught immediately; sent stand-down messages to all 6 via `SendMessage`. No output from any of them was used. Lesson recorded in `HANDOFF.md`: end the turn with a text-only update instead — background-task notifications arrive automatically on the next turn without needing a tool call to "wait."

### Open questions for Kyle
- **WU5** (`wu5-axes-review-brief.md`): 9 remaining Q-numbers (Q-1, Q-4–Q-10, Q-12), each now mapped to the specific doc/axis it blocks — headline items are Q-10 (consecutive-estimate counter shape, the single most load-bearing open item across both work units) and Q-6 (Texas disconnect bypass-set completeness, incl. family-violence).
- **WU6** (`wu6-decision-tables-review-brief.md`): the 4 Part-A tensions above are the priority; Parts B–E cover per-session schema gaps (no `meter_skip_reason`/tamper-flag/pressure-class columns exist yet) and scope questions (is sewer billing or government/wholesale rating actually in v1 scenario scope?).

### Next step
Kyle answers both briefs → fold answers in, starting with WU6's 4 tensions since they block the most downstream work → **Session 3E (Domain 5: Taxes & Fees, clusters 23–26)**, which consumes Session 3C's settled rider stack and Session 3D's PGA output as its own inputs per the canonical billing-pipeline order (CI-100). Sessions 3F–3M remain after that.

### Repo state
No commits in `tally-utility` this session; uncommitted here: `HANDOFF.md` (full rewrite), `CHANGELOG.md` (this entry), `TECH-STACK-DISCUSSION.md` (pre-existing, unrelated parallel thread, untouched this session). In `gas-billing-memory`: 15 commits this session (WU5 completion: `0cb783d`, `78035fb`, `23a4ee0`, `0c71016`, `0a4eb05`, `02f1593`, `9070bdb`, `e5a3370`, `c042493`, `3de7242`; WU6 + correction: `b0f87fd`, `84022ae`, `d830ddd`, `594a86f`, `2f2bc23`, `61fa175`, `e3d9536`, `6d5fca6`, `4c97fbf`, `a1faea2`, `1c58a37`, `42f36c9`); HEAD = `42f36c9`; 42 commits ahead of `origin/main`, not pushed; only `Clippings/` untracked.

---

## 2026-06-30 — Session: Work Unit 4 — test fixture catalog (Session 1 draft) + DE-8..11 reconciliation

**Status:** WU4 Session-1 draft complete and committed in `gas-billing-memory`; awaiting Kyle's answers on a combined review brief before Work Unit 5 (per-invariant scenarios). No application code written.

### Done
- **Resumed the WU3 handoff and checked drift:** Kyle had already resolved DE-8..11 (`gas-billing-memory bea5e17`, 2026-06-19) since the handoff was written — the WU3 gate had cleared, changing "Next" from "nudge Kyle" to "proceed to WU4."
- **Reconciliation pass** (`gas-billing-memory f523b06`): the `bea5e17` commit captured DE-9's §7.45 medical semantics only in the inventory's audit sections (Part 4/5), not the Part-1 cluster rows. Threaded action #36 inline into clusters **45** (`program-enrollment-eligibility`) and **46** (`collections-bypass-evaluation`); bumped the stale `updated:` date; backfilled `wiki-ingestion-pending.md` **Section C (C1–C5)** — the WU2-review → WU3 → DE-8..11 history that had gone unlogged.
- **Prerequisite check for WU4:** config catalog DE-reviewed ✅; canonical invariants schema-audited ✅ (flagged-question review is a *soft* gate — open Qs land on post-midpoint entities); schema confirmed at `tally-utility/sql/tu.sql` (the strategy's `application/database/schema.sql` path is stale).
- **Produced the fixture catalog** `gas-billing-memory/application/test-fixtures/` (`c554c69`) — **11 files, 87 fixtures, Texas-only:** jurisdictions (FIX-JUR-001..003, TX-RRC + environs/special-rate markers), customer-classes (FIX-CLASS-001..006, 7-value DE-6 enum), programs (FIX-PGM-001..011, v5.4 `program_types` enum, 6 v1 + 5 seeded), cities (FIX-CITY-001..009, real Texas cities across population/governance/tax/region), tenants (FIX-T-001..006 — municipal ×3, IOU, cooperative ×2), franchise-agreements (FIX-FA-001..007), rate-schedules (FIX-RS-001..014), customers (FIX-C-001..012), service-locations (FIX-SL-001..012), meters (FIX-M-001..008), + an `accounts.md` structural note. Config values pulled from the Layer-1 config-catalog + `tu.sql` (not invented).
- **Method:** ran **4 parallel grounding subagents** (Texas regulatory params, LDC sizing realism, city tax/franchise, programs/collections) while reading the config-catalog + schema directly; synthesized the fixtures in one context to avoid drift.
- **Cross-reference verification walk — clean:** automated sweep confirmed no dangling `FIX-` references and no orphans (caught + fixed one typo, FIX-CLASS-007 → FIX-CLASS-006).
- **Richer franchise coverage** (per Ryan's steer): added **Hill Country Gas Cooperative** (a 2nd, contiguous multi-city operator) + 3 Hill Country cities + 3 franchise agreements — bringing fee-paying operators to two and agreements to 7, spanning rates 1.0–2.0%, four escalation types, and indefinite/superseded/expiring terms.
- **Combined Kyle review brief** (`8b46ea2`, `session-1-review-brief.md`): plain-language fixture questions A1–A8 plus the still-open canonical-invariant flagged questions (Q-1,3,4,5,6,7,8,9,10,12) that gate Work Unit 5. Logged everything as **wiki-ingestion Section D (D1–D14)**.

### Decisions (and the "why NOT")
- **DE-FX-1: proceed assuming Tax Code §182.025 caps the gas franchise fee at 2%** (all `fee_percentage` ≤ 2%). NOT guessing 3–5% (real-world/industry practice) because the DE-reviewed config catalog asserts the 2% ceiling; the conflict is flagged for Kyle (A1) and every rate is tagged `# DE-FX-1` so a reversal is a one-file sweep. Cheap now because nothing downstream consumes the rates until scenario-writing.
- **Grounded to the schema/catalog enums, not the fixture strategy's lists.** 7-value customer-class enum (DE-6) over the strategy's 5 — **transport is a service-type, not a class**; v5.4 `program_types` (11) over the strategy's 9-item program list. Schema + DE-reviewed catalog are authoritative over the older strategy prose.
- **Five entity types modeled as reference fixtures (no backing schema table).** jurisdictions, customer-classes, programs, cities, tax_jurisdictions have no table in `tu.sql` (invariants gaps A-8/A-14; program substrate is v5.4-pending) — so they're enumeration fixtures grounded in regulatory/catalog material, NOT the "fill every schema column" model the strategy assumed.
- **No account fixtures — a structural note instead (DE-FX-9).** There is no `accounts` table; account = `customers.customer_number` + `service_locations`, and balance-state ("in collections", "written off") is a *ledger* condition (per-scenario transaction seed), not fixture data. NOT inventing an accounts table.
- **Only the IOU + the Hill Country co-op pay franchise fees.** A municipal utility serving its own city pays none (it *is* the city); the environs-only co-op has no city. Realistic, and thinner than the strategy's "~12 agreements" guess — resolved by adding a 2nd multi-city operator rather than fabricating franchise fees for the munis.

### Errors caught & resolved (research contamination)
- The parallel grounding subagents (fresh LLM research) re-introduced two errors already corrected in project canon: framing **deposit interest as a "PUCT rate"** (it is statutory, TUC §183.002 — gas is RRC/municipal, never PUC) and citing a **"12-month" backbilling cap** (that is the PUC *water* rule §24.165; gas is per-cause — non-registering 3mo / rate-misapplication 6mo / meter-error 6mo-or-since-last-test / tampering uncapped). Both caught against the config-catalog/invariants and corrected in `jurisdictions.md` before writing. Lesson recorded in HANDOFF: don't trust fresh LLM research on Texas gas regulation over the DE-reviewed catalog.

### Open questions for Kyle (the gate — in `session-1-review-brief.md`)
- **A1 (headline)** — §182.025: is the 2% a franchise-fee cap, or a distinct street-use charge that lets the franchise fee exceed 2%?
- **A2–A8** — special-rate-area reality; customer-class enum confirmation; medical-hold duration (20 days vs. unstandardized); PIPP scope; city tax-rate representativeness; franchise coverage depth; balance-state as ledger seed.
- **Part B (gates WU5)** — invariant Qs: WNA-deadband placement (Q-3), bypass-set completeness + family-violence (Q-6), estimate-counter shape (Q-10), adjacent-domain launch scope incl. submetering (Q-12), plus payment-earmarking (Q-5), bilingual county scope (Q-8), concurrent bi-temporal edits (Q-1), CIS scope boundaries (Q-4/Q-9), AMP forgiveness (Q-7).

### Next step
Kyle answers the combined review brief → fold answers into the catalog (sweep the tagged franchise rates if A1 flips) → **Work Unit 5 (Method 1 per-invariant scenario docs)**, referencing these fixtures by ID. Per the kickoff's review cadence, WU5 drafting *may* start in parallel on invariants whose framing is already locked.

### Repo state
No commits in `tally-utility` this session; uncommitted here: `HANDOFF.md` (full rewrite for WU4), `CHANGELOG.md` (this entry), `TECH-STACK-DISCUSSION.md` (pre-existing, parallel thread). In `gas-billing-memory`: three commits this session — `f523b06` (reconciliation), `c554c69` (fixture catalog), `8b46ea2` (review brief); HEAD = `8b46ea2`; only `Clippings/` untracked.

---

## 2026-06-18 — Session: Work Unit 3 — cluster & workflow inventory (Layer 2/3 scoping)

**Status:** WU3 draft complete; gated on domain-expert answers (DE-8..11) before the per-domain build sessions. No application code written. Deliverables committed in `gas-billing-memory` `fe6b464`.

### Done
- **Executed Work Unit 3 = Session 2** (Layer 2/3 scoping) of the configurable-rules strategy, the step after Kyle's WU2 config-catalog approval (`de-review-answers.md`, DE-1..7 + 32 action items, 2026-06-12).
- **Ran five systematic coverage walks** (the Session-2 completeness-gate dimensions) against the source corpus: pipeline-stage (19 feature-list stages), schema-column (213 cols + 56 JSONB sub-keys), failure-mode (~175 failures across 9 billing-failure stages + cross-cutting), persona (5 roles), and catalog cluster-seeds (125 catalog entries — override chains, regulated entries, intended-config + gap-list, classification inputs).
- **Produced `gas-billing-memory/application/configurable-rules/cluster-and-workflow-inventory.md`** — the canonical work queue replacing the strategy's provisional starters: **42 decision-table clusters** in 13 rule domains, **51 workflows** by area (integration ones tagged `[split-with-addenda]`), a **Sessions 3+ work queue** (3A reads → 3M import/admin), and an **inline completeness audit** of all 6 dimensions (each marked covered / folded / out-of-scope with rationale). Net vs. the ~25-cluster starter: kept 22, merged/renamed 3 groups, added 17.
- **Threaded Kyle's 32 action items** into the clusters they touch (per-cause §7.45 backbilling, working-day dunning clocks, per-service late-fee scoping, `agency_pledge` protection type, postmark timeliness, effective-dated deposit-interest table, per-type escheatment dormancy, gas `correction_rate_mode` historical guard, DE-4/5/7 schema consolidations).
- **Wrote `cluster-workflow-review-brief.md`** — a plain-language brief so Kyle can answer the four open questions without opening the dense inventory (same pattern as `catalog-review-brief.md`).

### Decisions (and the "why NOT")
- **WU3 deliverable is tables/stubs, not full specs.** Session 2 is a *scoping* session by strategy design — it enumerates what to build and proves coverage; the actual DMN decision tables and Cockburn workflow specs are Sessions 3+. NOT writing specs now — the strategy's stated dominant failure mode is jumping feature→scenario without first naming the rule and confirming nothing's missing.
- **Stages 16 (reporting) and 19 (implementation) get NO rule cluster, by design.** Reporting = outputs/queries not configurable decisions; implementation = professional-services/cutover not product runtime. Documented as out-of-scope — the gate requires an explicit reason, not silence.
- **`absolute-baseline-qa` elevated to a mandatory cluster.** The "whole batch wrong by the same amount" blind spot (Hydro One, PGW 2022, Central Hudson) had no home in the starter and is the single highest-value missing control.
- **Medical-hold handling = data-migration/UAT concern, not a runtime configurable rule.** It's a drop-on-cutover data risk, not a decision; flagged as DE-9 for Kyle to confirm.
- **Separate plain-language brief for Kyle** rather than sending the inventory — he needs only 4 bounded judgment calls; the inventory is an engineering checklist.

### Scoping corrections applied (not failures)
- The failure-mode walk over-indexed on **multi-state** regulation (MN/IL/OH/NY caps, cold-weather windows) and treated CIS-go-live / parallel-run / DB-lock dashboards as decision clusters. Both corrected in synthesis: launch is **Texas-only** (§7.45/§7.460; multi-state is a deferred Layer-4 parametric axis), and implementation/ops governance is out-of-scope for the configurable-rules corpus. Recorded inline so it isn't re-litigated.

### Open questions for Kyle (the gate — DE-8..11)
- **DE-8** — four edge-case tasks in for v1 or deferred: vacation/seasonal hold, account split, customer credit transfer.
- **DE-9** — confirm medical-hold migration is handled as a data-conversion/go-live checklist item, not a live engine rule.
- **DE-10** — are the `absolute-baseline-qa` thresholds (cycle revenue ±2%, class-avg-vs-prior-year ±5%, canary ±3%) right for Texas gas, or tenant-tunable?
- **DE-11** — confirm AI features + portal *build* deferred (nice-to-have), with the usage+temperature graph kept for v1.

### Next step
Kyle answers DE-8..11 → fold answers into the inventory → **Work Unit 4 (fixture catalog)** → **Sessions 3+** produce the actual decision tables + workflow specs, one rule domain per session per the Part 3 queue.

### Repo state
No commits in `tally-utility` this session; uncommitted here: `HANDOFF.md` (full rewrite for WU3), `CHANGELOG.md` (this entry), `TECH-STACK-DISCUSSION.md` (pre-existing, parallel thread). In `gas-billing-memory`: WU3 files committed `fe6b464` ("Adds workflow intermediate step"); only `Clippings/` untracked.

---

## 2026-06-07 — Session: Tech-stack decisions — locked 5 of 6 axes

**Status:** Tech-stack discussion (parallel thread). Five axes locked, one deferred. No application code written. All decisions recorded with full rationale in `TECH-STACK-DISCUSSION.md` decisions log; this entry is the summary.

### Decisions locked (each with the "why" in the decisions log)
- **A. Tariff / rate engine = data-driven config + a typed, decimal-only calc core.** Engineers build a rich, composable charge-type library once (`FIXED`, `TIERED_VOLUME`, `PASSTHROUGH_RATE`, `PCT_OF_BASE`, `WNA_ADJUSTMENT`, demand/ratchet, min/max riders); billing staff operate it via forms as date-effective data writes; **all arithmetic runs in one linted core, never in tenant input.** Tiny pure decimal-only DSL held *in reserve* for the rate-math half only, if the vertical slice proves the vocabulary too rigid. DMN decision tables handle rule *selection*; charge-type library handles rate *math*.
- **B. Language = C#/.NET for engine + API; TypeScript/React for portal.** Strict .NET (nullable refs on, analyzers + warnings-as-errors), pure I/O-free calc core, typed frontend client generated from .NET's OpenAPI output. **Vertical slice doubles as Ryan's C# ramp** (he has TS experience, no prior C#).
- **C. Data access = raw SQL + Dapper over Npgsql. No heavy ORM.** Consequence of B + bi-temporal architecture; must work *with* range types, RLS, four-column bi-temporal predicates, linked snapshot tables.
- **High-level architecture = modular monolith + pure calc core.** One deployable, one transactional Postgres, strong in-code module boundaries; worker-extraction seams (batch-billing, EDI gateway, doc generation) pre-drawn but not cut. Microservices off the table until a real independent-scaling/many-teams axis appears.
- **D. Tax = build in-house for Texas-only launch; clean Tax-module seam for a hybrid commercial engine at multi-state.**

### Why NOT the alternatives
- **NOT a DSL or embedded scripting for tariffs (A).** Scripting fails determinism/auditability and **can't enforce float-leakage discipline inside tenant code** (kills exact-decimal constraint); a DSL re-imposes language-authoring on routine rate changes (breaks the "staff change rates, no consultant" positioning) and adds parser/type-checker/versioning burden for expressiveness the bounded gas-tariff domain rarely needs.
- **NOT all-TypeScript (B).** No native decimal → money math runs through an allocating userland lib (`decimal.js`) that LLMs can silently bypass with raw `number` arithmetic (no compile error). C#'s native base-10 `decimal` makes the worst LLM error in this domain *uncompilable*; the compiler is the load-bearing safety net when LLMs write most of the code. All-TS pays a permanent decimal-discipline tax to avoid a one-time, front-loadable C# ramp.
- **NOT microservices (architecture).** DB-per-service shatters atomic bills + bi-temporal consistency into sagas/eventual-consistency against requirements that demand strong consistency; small team pays the ops tax with no org-scaling benefit; load is batch + horizontally scalable across independent tenant runs.
- **NOT buying a tax engine at launch (D).** Franchise fees + regulatory assessments aren't modeled by commercial engines (built in-house regardless → never a clean buy); the engines' crown jewel (situsing) is nearly free for a defined-territory utility; per-transaction pricing × every line × meter × tenant × month threatens platform unit economics; bi-temporal as-of-historical reproducibility fights the "today's answer" API model. Texas tax is ~90% the data-driven charge-type + bi-temporal-rate machinery already being built. Revisit buy (hybrid) at multi-state.

### Deferred
- **E. Testing approach — deferred to when scenarios exist (Layer 4) and the build is closer to testing.** Carry-forward open questions documented in `TECH-STACK-DISCUSSION.md` axis E: scenario→test mechanics + fixture shape; property-based (invariants) vs. example-based (named fixtures); golden-master/snapshot for cancel-rebill reproducibility; clock-injection mechanism. Tooling now constrained by B: CsCheck/FsCheck (property) + xUnit (example/golden-master).

### Process note
- Ryan prefers tradeoffs worked as prose discussion, not `AskUserQuestion` menus (saved to project memory). Entertained and explicitly rejected DSL/scripting (A) and all-TS (B) before locking.

### Next step
Tech-stack thread is paused with E as the only open axis; resume it alongside scenario work. Main project track continues independently at Work Unit 2 (configuration catalog). No tech-stack work blocks Phase 2.

### Repo state
No commits this session. Edits to `TECH-STACK-DISCUSSION.md` (decisions log filled: A/B/C/architecture/D; status header updated; E marked deferred) and `CHANGELOG.md` (this entry). New project memory: `prefers-discussion-over-canned-options.md`.

---

## 2026-06-07 — Session: Orient on domain-expert audit; plan Phase 2; create tech-stack pickup doc

**Status:** Planning/discovery session — no application code written.

### Done
- **Mapped the real project state.** Authoritative knowledge + planning now lives in `/Users/ryanscomputer/code/gas-billing-memory/` (not this repo; the old `LLM-wiki/projects/TallyUtility/` path is gone — wiki moved to `LLM-wiki/wiki/projects/tally-utility/`).
- **Characterized the domain-expert audit.** Author: **Kyle Shaffer** (`kyle.shaffer@centric-us.com`), single commit `dcc4f67` (2026-05-29). New artifact `application/invariants/gap-analysis-v5.2.1.md` (1,347 lines) audits all 17 invariant families against the v5.2.1 schema; produced **40 "doc drift" findings** (predominantly the invariants doc *underselling* what the schema already enforces; plus a few real gaps and wrong table names — e.g., `work_orders`→`service_orders`, `service_agreements` doesn't exist).
- **Logged question resolutions.** Kyle resolved **3 of the flagged questions**: Q-2 (`account_ledger.running_balance` → stamp-at-insert via `compute_ledger_running_balance` trigger; CI-019 upgraded), Q-11 (tenant read-isolation → Postgres RLS; CI-116 upgraded to `structurally-enforced`), Q-13 (new — multi-program enrollment → `customer_program_enrollments` + `program_types`, drop single-column `disconnect_protection_*`). **10 remain open:** Q-1, Q-3, Q-4, Q-5, Q-6, Q-7, Q-8, Q-9, Q-10, Q-12.
- **Created `TECH-STACK-DISCUSSION.md`** (repo root) — a self-contained pickup doc for the parallel tech-stack thread: methodology frame, domain constraints (decimal money, determinism, Postgres-native, testability, auditability), five decision axes (tariff engine flagged resolve-first), open questions, empty decisions log.
- **Rewrote `HANDOFF.md`** to reflect actual current state (was a stale 2026-05-14 bi-temporality "Session A" handoff pointing at a decision already made and a dead KB path).

### Decisions (and the "why NOT")
- **Specification-first / waterfall on the regulated "what."** Requirements are externally fixed by regulation, so spec fully before building. NOT agile — agile's "discover requirements via iteration" bet is wrong for regulated billing.
- **Iterate the architectural "how"** (tariff engine, snapshot shape, stack) — regulation doesn't determine these; keep them empirical until a slice proves them.
- **Vertical slice proves the format before mass production.** Run the gas-pipeline spine end-to-end first (read→consumption→BTU/pressure→PGA→WNA→rate→immutable bill+snapshot) to validate scenarios→fixtures→tests→engine compose, then fan out. Avoids re-formatting ~350 features of specs.
- **Fixtures derive from scenarios, never from the engine** — engine-derived fixtures are circular and can't catch bugs. Slice teaches fixture *shape*; content comes from the spec.
- **Defer most drift reconciliation.** Config catalog reads schema + feature list directly (invariants only a soft prerequisite), so the ~37 annotation-level drift items ride with schema hardening; only the 3 domain-level findings (CI-064, CI-037, Q-13 model) fold in before Phase 2.
- **Next step is Work Unit 2 (config catalog), not scenarios directly** — per `execution-kickoff.md` the four-layer pipeline puts scenarios last (Layer 4), after catalog → decision tables → workflows → fixtures.

### Wrong assumption corrected (don't repeat)
- Claimed Kyle audited a separate **"de-Supabased v5.2.1 schema dump"** that needed locating, and made it a Phase-2 blocker. **Wrong:** misread two layers of the same file as two files. `tu.sql` *defines* the wrappers `get_user_tenant_id()` (line ~535) and `is_platform_admin()` (line ~570); their bodies call `auth.uid()`. RLS policies call the wrappers, not `auth.uid()` directly. **`tu.sql` v5.2.1 is the single canonical schema.** De-Supabasing = swap `auth.uid()` in those two function bodies (deferred to schema hardening). Also: the v5.3/v5.4 patches referenced in docs **do not exist as SQL** anywhere.

### Next step
Fold the 3 domain findings into `canonical-invariants.md`, then open Work Unit 2 — create `gas-billing-memory/application/configurable-rules/configuration-catalog.md` and run the Layer 1 inventory against `tu.sql`. Tech-stack discussion proceeds in parallel via `TECH-STACK-DISCUSSION.md`.

### Repo state
No commits this session. Uncommitted in `tally-utility`: `HANDOFF.md` (rewritten), `sql/tu.sql` (`auth.users` FK removed in prior edit), untracked `CONTEXT.md`, `TECH-STACK-DISCUSSION.md`, `application/`, `.idea/`. `gas-billing-memory` clean (HEAD `dcc4f67`).
