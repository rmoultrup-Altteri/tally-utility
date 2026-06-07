# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

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
