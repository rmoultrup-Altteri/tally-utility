# TECH STACK DISCUSSION — TallyUtility Billing Engine

**Purpose:** A pickup document so Ryan + Claude can resume the tech-stack decision in a fresh session without re-deriving context. This is a *discussion scaffold*, not a decision record — decisions get logged at the bottom as they're made.

**Status:** Open / not started. Runs in **parallel** with Phase 2 (configuration catalog) — it does not block that work.

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

Schema today: `tally-utility/sql/tu.sql` is v5.2.1 — the single canonical schema, and the one Kyle's audit maps to (there is no separate "dump"). It still carries Supabase plumbing, but it's tiny and contained: `auth.uid()` is called only inside the bodies of two wrapper functions, `get_user_tenant_id()` (line ~535) and `is_platform_admin()` (line ~570). RLS policies call the wrappers, not `auth.uid()` directly. De-Supabasing = swap those two function bodies for a standalone mechanism (e.g. `current_setting('app.current_user_id')::uuid`) + the already-removed `auth.users` FK + a `users.id` default. A small schema-hardening item; does **not** block the config catalog.

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

### E. Testing approach
- How a scenario doc becomes an executable test (the scenario→test contract). Property-based vs. example-based for the calc core. This is the contract the vertical slice must prove.

---

## Open questions for Ryan (starting set)

1. Is the **language/runtime** open, or constrained (your background, team, hosting)?
2. Instinct on the **tariff engine** — data-driven config, small DSL, or embedded scripts?
3. Hosting / deployment target assumptions (affects runtime + ops choices)?
4. Tax engine — any prior lean toward build vs. Avalara/Vertex?

---

## Decisions log

*(empty — fill in as decisions lock, with the why)*

| Date | Decision | Resolution | Why |
|------|----------|------------|-----|
| | | | |
