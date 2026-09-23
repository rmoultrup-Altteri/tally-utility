# TECH STACK DISCUSSION — TallyUtility Billing Engine

**Purpose:** A pickup document so Ryan + Claude can resume the tech-stack decision in a fresh session without re-deriving context. This is a *discussion scaffold*, not a decision record — decisions get logged at the bottom as they're made.

**Status:** In progress. Locked (2026-06-07): **A** tariff engine (data-driven config + typed calc core), **B** language (.NET engine/API + TS/React portal), **C** data access (raw SQL + Dapper/Npgsql), **high-level architecture** (modular monolith + pure calc core), **D** tax (build in-house for Texas launch; hybrid seam for multi-state). **Deferred:** **E** testing approach — intentionally postponed until the scenarios exist (Layer 4) and the build is closer to actually testing, since E is the scenario→test contract and is best resolved against real scenarios. Runs in **parallel** with Phase 2 (configuration catalog) — it does not block that work.

---

## How to use this doc

1. New session opens this file first.
2. Read the "Where the real state lives" pointers if you need deeper context.
3. Work the **Decision axes** top to bottom. The tariff-engine axis is the most coupled — resolve it early.
4. Record outcomes in the **Decisions log** at the bottom. Each locked decision should name the *why*, because this is regulated software and choices need to be defensible later.

---

## One-line project context

TallyUtility is a modern, multi-tenant SaaS CIS / meter-to-cash billing platform for **natural gas LDCs** (500–150,000 meters). Gas-only at launch; schema also supports water/electric/sewer. No application code exists yet — this stack decision precedes the first line of engine code.

## Where the real state lives

The active knowledge base + planning artifacts are **not** in this repo. They're in:

```
/Users/ryanscomputer/code/gas-billing-memory/
```

Key files:
- `CONTEXT.md` — project orientation, current phase, locked + pending decisions
- `application/execution-kickoff.md` — the 12-work-unit sequence; Work Unit 2 (config catalog) is next
- `application/canonical-invariants.md` — 135 invariants (CI-001–CI-135), the regulated "what" the engine must satisfy
- `application/invariants/gap-analysis-v5.2.1.md` — Kyle Shaffer's (domain expert) schema audit
- `application/bi-temporal-decision.md` — bi-temporal architecture decision (Postgres + linked snapshot table)
- `application/configurable-rules-scenario-strategy.md` — the four-layer rules→scenarios methodology

*(Superseded 2026-08-18: v5.4.0-00 removed the Supabase layer — RLS now reads the `app.user_id` session setting; tu.sql is patched through v5.4.2-11. See CONTEXT.md. The paragraph below is the 2026-07-08 state.)* Schema then: `tally-utility/sql/tu.sql` was v5.2.1 — the single canonical schema, and the one Kyle's audit maps to (there is no separate "dump"). It still carries Supabase plumbing, but it's tiny and contained: `auth.uid()` is called only inside the bodies of two wrapper functions, `get_user_tenant_id()` (line ~535) and `is_platform_admin()` (line ~570). RLS policies call the wrappers, not `auth.uid()` directly. De-Supabasing = swap those two function bodies for a standalone mechanism (e.g. `current_setting('app.current_user_id')::uuid`) + the already-removed `auth.users` FK + a `users.id` default. A small schema-hardening item; does **not** block the config catalog.

---

## Working methodology agreed (the frame this decision sits in)

The stack must serve this build model:

- **Specification-first (deliberate waterfall on the regulated "what").** Requirements are externally fixed by regulation (backbilling caps, WNA deadband, disconnect protections, PGA pass-through, subpoena-ready audit). They're knowable up front, so we spec them fully (invariants → configurable rules → scenarios) before building.
- **Incremental construction against the spec.** Build in small slices, checking after each.
- **Iterate on the architectural "how."** Regulation fixes *what* the system must do, not *how* the engine is architected. Those choices (tariff engine, snapshot shape, stack) stay empirical until a vertical slice proves them.
- **Prove the format on one vertical slice before mass-producing.** Take the gas pipeline spine (read → consumption → BTU/pressure correction → PGA → WNA → rate application → immutable bill + snapshot) end-to-end first, to validate that scenarios → fixtures → tests → engine actually compose. Then fan out.
- **Fixtures derive from scenarios (the spec), never from the engine.** The slice teaches the fixture *format/shape*; the fixture *content* comes from the scenario. Tests are an independent check on the build, not an echo of it.

---

## Domain constraints on the stack (non-negotiable)

These come from the domain, not from taste:

1. **Exact decimal money math.** No binary floats anywhere near currency. Stack needs first-class arbitrary-precision decimals (or a rigorously enforced decimal library) and a culture/lint that prevents float leakage.
2. **Determinism + reproducibility.** Cancel-rebill must reproduce a historical bill *exactly* from snapshotted inputs (the original period's rates, BTU factors, WNA inputs, tax rates). Favors a strongly-typed language with an easily-isolated, side-effect-free billing-calculation core.
3. **Postgres-native, bi-temporal-friendly data access.** Heavy date-range predicates; RLS already chosen for tenant isolation; bi-temporal reference data. The data layer must work *with* raw SQL / range types — not an ORM that hides or fights them.
4. **Testability as a first-class requirement.** The whole spec-first approach assumes a scenario becomes an executable test cheaply. The stack's test ergonomics directly determine whether the plan is affordable.
5. **Auditability / traceability.** Requirement → scenario → test → code traceability needs to be legible (potentially to regulators / in a subpoena). Favors explicit, readable code over heavy magic/metaprogramming.

---

## Decision axes (work these in the new session)

### A. Tariff / rate engine architecture — *resolve first; most coupled*
How are rates, riders, factors, and rules expressed and evaluated?
- **Data-driven rules** (config rows + a fixed evaluator) — simplest to reason about, easiest to make "billing staff can change rates themselves"; risk of expressiveness ceiling.
- **Small DSL** — more expressive; needs a parser/evaluator and host-language ergonomics for expression eval; harder for non-technical staff.
- **Embedded scripting** — most flexible; worst for auditability, determinism, and "no vendor consultant required" positioning.
- Open: this choice strongly shapes axis B (a DSL/scripting path wants a host language with good interpreter ergonomics; a data-driven path just wants clean data structures + a well-tested evaluator).

### B. Language / runtime
- Candidates to weigh against constraints 1–5 (decimal money, determinism, Postgres, testability, auditability). No default assumed — depends on Ryan's preferences/constraints (background, team, hosting) and axis A.
- Decide: is this genuinely open, or constrained by existing skills/team/hosting?

### C. Data-access strategy
- Raw SQL + thin mapper vs. query builder vs. ORM. Constraint 3 pushes away from heavy ORMs. Must support range predicates, RLS, and the linked snapshot tables cleanly.

### D. Tax engine — build vs. buy
- Avalara / Vertex vs. in-house. Pending decision in `gas-billing-memory/CONTEXT.md`. Affects the tax-related invariants, scenarios, fixtures. Lower urgency but shouldn't surprise the build.

### E. Testing approach — *DEFERRED (2026-06-07)*
- How a scenario doc becomes an executable test (the scenario→test contract). Property-based vs. example-based for the calc core. This is the contract the vertical slice must prove.
- **Deferred by decision on 2026-06-07:** resolve when the scenarios exist (Layer 4) and the build is closer to testing — the contract is best designed against real scenarios, not in the abstract. Open questions to carry into that session: (1) scenario→test mechanics + fixture shape; (2) property-based (for invariants: PGA pass-through, decimal rounding, idempotent ledger posting) vs. example-based (named-fixture specific bills); (3) golden-master/snapshot tests for cancel-rebill reproducibility; (4) clock-injection mechanism (constructor-injected clock vs. global) — the strategy docs punted this to "when the stack is chosen"; the stack is now chosen (.NET), so settle it here. Now that B is locked: property-based via CsCheck/FsCheck, example/golden-master via xUnit.

---

## Open questions for Ryan (starting set)

1. Is the **language/runtime** open, or constrained (your background, team, hosting)?
2. Instinct on the **tariff engine** — data-driven config, small DSL, or embedded scripts?
3. Hosting / deployment target assumptions (affects runtime + ops choices)?
4. Tax engine — any prior lean toward build vs. Avalara/Vertex?

---

## Decisions log

| Date | Decision | Resolution | Why |
|------|----------|------------|-----|
| 2026-06-07 | **B. Language / runtime** | **C# / .NET for the billing engine + API; TypeScript / React for the portal/frontend.** Backend: strict-mode .NET (nullable reference types on, analyzers + warnings-as-errors from day one). The billing calculation core is a pure, I/O-free library. Frontend talks to the API over a typed client generated from .NET's first-class OpenAPI output (contract kept in sync by codegen, not discipline). The **vertical slice doubles as Ryan's C# ramp** — he has no prior C# experience, so the zero-stakes gas-pipeline spine is where he becomes a fluent C# *reader/reviewer* before any customer code exists. | (1) **Native base-10 `decimal`** makes constraint #1 (exact money math) a *language default*, not a discipline — to get a float you must explicitly write `double`. Every other serious candidate (`BigDecimal`, `decimal.js`, Go/Python libs) makes decimal a type you must remember to reach for, with `0.45` a float until wrapped. (2) Most code will be LLM-written, so the load-bearing safety net is the **compiler + strong static types**, which run on every change for free and make the worst LLM error in this domain — silent float money math — *uncompilable*. TS's erasable types (`any`/`as`/`@ts-ignore`) have holes LLMs slip through exactly when stuck. (3) First-party coherence (ASP.NET Core, built-in DI/config/testing) gives the LLM one stable canon vs. TS-backend's fragmented, churn-heavy ecosystem → more consistent generated code. (4) Performance: not a feasibility factor (billing is batch, I/O-bound, horizontally scalable across independent tenant runs), but C#'s native-decimal value type + multicore in-process parallelism is more compute-efficient *specifically for decimal-heavy billing*, showing up as lower infra opex + month-end headroom at 5-yr scale. (5) The no-C#-experience risk is real but **bounded and structurally covered**: in the spec-first methodology, correctness is guaranteed by scenario-derived *tests* (Ryan's strongest, language-agnostic skill), not by line-by-line review; TS→C# is a short hop for an experienced engineer; and the portal stays in TS where his fluency is highest. All-TS with hardened decimal discipline was weighed and declined — it pays an ongoing discipline-tax forever to avoid a one-time, front-loadable ramp, and is weakest on the regulated-correctness axis that defines the product. |
| 2026-06-07 | **C. Data-access strategy** | **Raw SQL + thin mapper (Dapper) over Npgsql. No heavy ORM (EF Core not used for the engine).** | Resolved as a consequence of B + the locked bi-temporal architecture. Constraint #3 demands a data layer that works *with* raw SQL, range types, RLS, four-column bi-temporal predicates, and linked snapshot tables — not an ORM that hides or fights them. Dapper maps result rows to typed records without owning the SQL; Npgsql is a first-class Postgres driver with strong type mapping (ranges, arrays, `numeric`→`decimal`). Set-based / bulk-`COPY` writes and batched bi-temporal reads (the real billing-run performance levers) stay fully in our control. |
| 2026-06-07 | **D. Tax engine — build vs. buy** | **Build in-house for the Texas-only gas launch. Design a clean Tax-module seam so a commercial engine can slot in later as a *hybrid* at multi-state expansion** (bought statutory sales/use tax in new states; in-house franchise fees + regulatory assessments everywhere). | (1) Two of the largest "tax" line items — **franchise fees** (% of gross receipts, negotiated per city in 5-yr agreements) and **regulatory assessments** (Pipeline Safety Fee, PUC/RRC) — are not statutory tax and are **not modeled by commercial engines**, so they're built in-house regardless; it's never a clean buy. (2) A commercial engine's crown jewel is **situsing** (geocoding addresses to jurisdictions), which is **nearly free for a defined-territory utility** — service locations sit in known cities/environs, a bounded mapping, not nationwide geocoding. (3) Single-state Texas tax is a bounded, documented spec (`knowledge/31-texas-regulatory-compliance.md`) and is ~90% the **data-driven charge-type + bi-temporal rate-table machinery already being built** for axis A (e.g. `PCT_OF_BASE` already covers franchise fees / gross-receipts tax; Gas Utility Tax is a small population-bracket variant). (4) **Bi-temporal reproducibility** (reproduce exact tax on a 3-yr-old bill as-of the original period) fights the "today's answer" commercial API model. (5) **Platform unit economics**: a per-transaction/per-document engine × every taxable line × every meter × every tenant × monthly becomes a COGS line that scales with revenue and caps gross margin. (6) In-house rate maintenance for one state + a bounded set of tenant cities is small and **aligns with product DNA** — tax/franchise rates become config rows billing staff maintain through the same UI as tariff rates. Revisit buy at multi-state, when multi-jurisdiction rate maintenance finally earns its keep. |
| 2026-06-07 | **High-level architecture** | **Modular monolith with a pure, I/O-free billing calc core.** One deployable, one transactional Postgres. Strong in-code module boundaries (Metering, Tariff/Rating, Billing, Ledger/AR, Collections, Tax, Customer/CIS, Portal-API) — each owns its tables, reached through interfaces, never by reaching into another module's tables. Seams **pre-drawn but not cut** for later extraction of worker processes (batch-billing engine, integrations/EDI gateway, document/PDF generation) sharing the same DB. True per-entity microservices off the table until a real independent-scaling or many-teams axis appears. | Atomic bills + bi-temporal consistency + append-only ledger + RLS all want a *single transactional Postgres* as the source of truth (a bill touches rates, factors, ledger, snapshots atomically); microservices' DB-per-service orthodoxy would shatter that into sagas/eventual-consistency against requirements that demand strong consistency. Determinism + "reproduce a 3-yr-old bill exactly" and subpoena-ready audit are far easier from one transaction/audit boundary. Load is batch-heavy and horizontally scalable across independent tenant runs, not high-QPS — no independent-scaling need microservices solve. Small greenfield team pays microservices' full ops/cognitive tax with none of the org-scaling benefit. Modular (not big-ball-of-mud) keeps testability, AI-navigability, and the option to extract workers later. |
| 2026-06-07 | **A. Tariff / rate engine architecture** | **Data-driven config + a typed, decimal-only calc core.** Engineers build a rich, composable charge-type library once (`FIXED`, `TIERED_VOLUME`, `PASSTHROUGH_RATE`, `PCT_OF_BASE`, `WNA_ADJUSTMENT`, demand/ratchet, min/max riders, …); billing staff operate it through forms as date-effective data writes; **all arithmetic runs in one linted calc core, never in tenant input.** A tiny pure decimal-only DSL is held *in reserve* for the rate-math half only, to be called up only if the vertical slice proves the charge-type vocabulary too rigid. Decision tables (DMN, per the configurable-rules strategy) handle rule *selection*; the charge-type library handles rate *math*. | (1) Separates the two operations that matter: engineers build the *verbs* once, staff supply the *nouns* forever — that separation **is** the "no consultant required" positioning, and only the data-driven model preserves it (DSL/scripting force authoring in a language for anything past a bare value). (2) **Precision is enforceable only in data-driven**: the sole code doing money arithmetic is our compiled/typed/linted core; staff supply decimal operands, never operations — you cannot impose a float-leakage lint culture inside tenant-authored scripts (constraint #1). (3) Determinism + auditability are maximal where regulators look: the tariff is *data* you can diff and snapshot bi-temporally, not a program. (4) Gas tariffs in the 500–150K band are a largely bounded, enumerable set of charge shapes, so the vocabulary can be built rich enough that the new-shape code path is genuinely rare; that rare path ships in days, not a 6-week PS engagement. DSL and scripting were entertained and rejected — scripting fails determinism/auditability/precision-enforcement outright; a DSL re-imposes language-authoring on routine work and adds a parser/type-checker/versioning burden for expressiveness the bounded domain rarely needs. |
