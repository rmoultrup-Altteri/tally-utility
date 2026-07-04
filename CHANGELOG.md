# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

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
