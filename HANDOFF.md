# Handoff: Phase 2 Kickoff — Reconcile Audit & Start Configuration Catalog

**Generated**: 2026-06-07
**Branch**: main
**Status**: Ready to resume (planning session — no code written)

## Goal

Move TallyUtility from "invariants complete + domain-expert audited" into **Phase 2 = Work Unit 2 (the configuration catalog)**, the first step of the configurable-rules → scenarios pipeline. A parallel tech-stack discussion runs alongside it in a separate session.

## Orientation (read first)

The authoritative project state is **NOT in this repo**. It lives in:

```
/Users/ryanscomputer/code/gas-billing-memory/
```
- `CONTEXT.md` — current phase, locked + pending decisions
- `application/execution-kickoff.md` — the 12-work-unit sequence (Work Unit 1 done; Work Unit 2 is next)
- `application/canonical-invariants.md` — 135 invariants (CI-001–CI-135)
- `application/invariants/gap-analysis-v5.2.1.md` — Kyle Shaffer's schema audit
- `application/configurable-rules-scenario-strategy.md` — the four-layer rules→scenarios methodology
- `application/bi-temporal-decision.md` — bi-temporal decision (Postgres + linked snapshot table)

The wiki also moved: now at `/Users/ryanscomputer/code/LLM-wiki/wiki/projects/tally-utility/` (the old `LLM-wiki/projects/TallyUtility/` path is gone).

## Completed (this session)

- [x] Reviewed `gas-billing-memory` state. Domain expert is **Kyle Shaffer** (`kyle.shaffer@centric-us.com`); his entire contribution is one commit, `dcc4f67` (2026-05-29), "Audit close-out v5.2.1."
- [x] Characterized Kyle's audit: `gap-analysis-v5.2.1.md` (1,347 lines) audits all 17 invariant families vs. the v5.2.1 schema; surfaced **40 "doc drift" findings** (mostly the doc *underselling* what the schema enforces; a few real gaps + wrong table names).
- [x] Confirmed Kyle resolved **3 flagged questions** — Q-2 (ledger running_balance → stamp-at-insert), Q-11 (tenant read-isolation → RLS), Q-13 (NEW: multi-program enrollment → `customer_program_enrollments` + `program_types`). **10 still open**: Q-1, Q-3, Q-4, Q-5, Q-6, Q-7, Q-8, Q-9, Q-10, Q-12.
- [x] Agreed the build methodology (see Key Decisions).
- [x] Created `TECH-STACK-DISCUSSION.md` (repo root) — pickup doc for the parallel tech-stack thread.
- [x] Corrected a false premise about the schema (see Failed Approaches).

## Not Yet Done

- [ ] **Fold the 3 domain-level findings into the canonical invariants** — CI-064 (multi-program composition is *required*; single-column model can't represent it), CI-037 (transport-vs-sales is convention not structure), and confirm the Q-13 `customer_program_enrollments` model is reflected. (In `gas-billing-memory/application/canonical-invariants.md`.)
- [ ] **Open Work Unit 2 — configuration catalog.** Create `gas-billing-memory/application/configurable-rules/configuration-catalog.md` and run the Layer 1 inventory per `configurable-rules-scenario-strategy.md`. (Expect 2–3 conversations with a `session-1-recon` checkpoint.)
- [ ] **Tech-stack discussion** (separate session) — work the axes in `TECH-STACK-DISCUSSION.md`; resolve the tariff-engine architecture axis first.
- [ ] **(Deferred to schema-hardening)** De-Supabase: swap `auth.uid()` in two function bodies; ~37 annotation-level drift fixes from Kyle's audit; close schema gaps A-1–A-21; write the referenced-but-nonexistent v5.3/v5.4 patches.

## Failed Approaches (Don't Repeat These)

- **"Locate the de-Supabased v5.2.1 schema dump Kyle audited."** I asserted Kyle audited a separate, cleaned schema (because his audit quotes RLS wrappers `get_user_tenant_id()` / `is_platform_admin()` while `tu.sql` shows raw `auth.uid()`) and made "find that dump" a blocker for Phase 2. → **Mechanism of error:** misread two layers of the *same* file as two different files. `tu.sql` *defines* those wrapper functions (lines ~535 and ~570) and their bodies call `auth.uid()`. RLS policies call the wrappers, not `auth.uid()` directly. → **Reality:** `tu.sql` v5.2.1 IS the single canonical schema Kyle audited. There is no second dump. The config catalog builds directly against `tu.sql`.
- **Note on phantom artifacts generally:** the docs reference a **v5.3** patch (CI-019 hardening) as if applied and a **v5.4** patch (enrollment redesign) as pending — *neither exists as SQL anywhere on disk*. Treat doc references to schema patches as aspirational until you find the `.sql`.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Specification-first (waterfall on the regulated "what") | Requirements are externally fixed by regulation (backbilling caps, WNA deadband, disconnect protections, PGA, subpoena-ready audit). Knowable up front → spec fully before building. Agile's "discover requirements by iterating" bet is wrong here. |
| Iterate on the architectural "how" | Regulation fixes *what*, not *how* (tariff engine, snapshot shape, stack). Those stay empirical until a slice proves them. |
| Vertical slice proves the format before mass production | Run the gas-pipeline spine (read→consumption→BTU/pressure→PGA→WNA→rate→immutable bill+snapshot) end-to-end first to validate scenarios→fixtures→tests→engine compose. Then fan out. Avoids re-formatting 350 features of specs. |
| Fixtures derive from scenarios, never from the engine | Fixtures derived from code are circular (a bug baked into both sides can't be caught). Content comes from the scenario/spec; the slice only teaches the fixture *format/shape*. |
| Most drift reconciliation deferred | The config catalog reads schema + feature list directly (invariants only a *soft* prerequisite), so the ~37 annotation-level drift items are low-risk for Work Unit 2 and ride with schema hardening. Only the 3 domain-level findings fold in now. |
| Next step is Work Unit 2, not scenarios directly | Per `execution-kickoff.md`: config catalog (Layer 1) → decision tables (L2) → workflows (L3) → fixture catalog → scenarios (L4). Scenarios are the *last* layer, not simultaneous with rules. |

## Current State

**Working**: All planning artifacts in `gas-billing-memory` are intact and committed (last commit `dcc4f67`, Kyle's audit). `tu.sql` v5.2.1 is the canonical schema.
**Broken**: Nothing functional (no app code exists yet).
**Uncommitted changes (this repo)**: `HANDOFF.md` (this rewrite), `sql/tu.sql` (the `auth.users` FK already removed in a prior uncommitted edit), and untracked `CONTEXT.md`, `TECH-STACK-DISCUSSION.md`, `application/`, `.idea/`. `gas-billing-memory` has no uncommitted changes.

## Code Context

De-Supabasing surface (deferred, but this is the whole of it) — `sql/tu.sql`:
```sql
-- line ~535
CREATE FUNCTION public.get_user_tenant_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$ SELECT tenant_id FROM users WHERE id = auth.uid() $$;

-- line ~570
CREATE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$ SELECT EXISTS(SELECT 1 FROM users WHERE id = auth.uid() AND role = 'platform_admin') $$;
```
Swap `auth.uid()` → e.g. `current_setting('app.current_user_id')::uuid`. Plus restore a `users.id` default (Supabase managed it externally) and the `auth.users` FK is already removed.

Pending decisions still open in `gas-billing-memory/CONTEXT.md`: GTM sub-band, tax engine (build vs Avalara/Vertex), **tariff engine approach (data-driven / DSL / scripting)** — the last is the one most coupled to the tech stack.

## Resume Instructions

1. Read `gas-billing-memory/CONTEXT.md` and `application/execution-kickoff.md`.
   - Expected: confirms Work Unit 1 done, Work Unit 2 (config catalog) next.
2. Fold the 3 domain findings into `gas-billing-memory/application/canonical-invariants.md` (CI-064, CI-037, Q-13 model).
   - Expected: invariant statements reflect multi-program composition + transport/sales convention + enrollment model.
3. Create `gas-billing-memory/application/configurable-rules/configuration-catalog.md` and start Layer 1 of `configurable-rules-scenario-strategy.md`, building against `tu.sql`.
   - Expected: a configuration-surface inventory; will split across 2–3 sessions with a `session-1-recon` checkpoint.
4. In a separate session, open `TECH-STACK-DISCUSSION.md` and work the axes (tariff engine first).

## Warnings

- **Don't go hunting for a "de-Supabased schema dump" — it doesn't exist.** `tu.sql` is the one schema. (See Failed Approaches.)
- **Don't treat v5.3/v5.4 as applied** — they're described in docs but have no SQL.
- **RLS is load-bearing, not Supabase cruft to delete** — per Q-11 it's the chosen tenant-isolation mechanism. De-Supabasing means swapping the *auth source inside the wrappers*, not removing RLS.
- This repo's old A→D "schema completion" plan is dead — superseded by `execution-kickoff.md`. Ignore any A–D references.
