# Handoff: Work Unit 4 — Test Fixture Catalog (Session 1 draft complete)

**Generated**: 2026-06-30
**Branch**: main (both repos)
**Status**: Ready for Review — WU4 Session-1 draft committed; awaiting Kyle's answers on the combined review brief before Work Unit 5 begins.

## Goal

Execute **Work Unit 4** of `gas-billing-memory/application/execution-kickoff.md` = **Session 1** of the fixture-catalog strategy: produce `application/test-fixtures/` — the canonical, synthetic, Texas-only named entities (tenants, customers, cities, meters, rate schedules, …) every scenario references by ID, so config values don't drift across the scenario corpus. Prerequisite for scenario-writing (WU5+).

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/test-fixtures/` — **the WU4 deliverable** (committed `c554c69`; review brief `8b46ea2`)
- `application/test-fixtures/session-1-review-brief.md` — **the Kyle-facing ask** (fixture A1–A8 + gating invariant Qs)
- `application/test-fixtures/session-1-recon.md` — dense recon: coverage, structural findings, DE-FX-1..9
- `application/test-fixture-catalog-strategy.md` — the governing spec for this work unit
- `application/execution-kickoff.md` — the 12-work-unit sequence (WU1–4 ✅; **WU5 = Method 1 per-invariant scenarios next**)

## Completed (this session)

- [x] **Resumed WU3 handoff, checked drift:** found Kyle had resolved DE-8..11 (`gas-billing-memory bea5e17`) since the handoff was written — gate cleared.
- [x] **Reconciliation pass** (`gas-billing-memory f523b06`): threaded action #36 (§7.45 medical semantics) inline into inventory clusters 45/46 (was only in the Part 4/5 audit); bumped stale date; backfilled wiki-ingestion log Section C (WU2-review→WU3→DE-8..11 history).
- [x] **WU4 fixture catalog** (`gas-billing-memory c554c69`): 11 files, **87 fixtures**, Texas-only. jurisdictions (FIX-JUR-001..003), customer-classes (FIX-CLASS-001..006), programs (FIX-PGM-001..011, v5.4 enum), cities (FIX-CITY-001..009), tenants (FIX-T-001..006), franchise-agreements (FIX-FA-001..007), rate-schedules (FIX-RS-001..014), customers (FIX-C-001..012), service-locations (FIX-SL-001..012), meters (FIX-M-001..008), accounts (structural note). Config values pulled from the Layer-1 config-catalog + `tu.sql` (not invented).
- [x] **Cross-reference verification walk — clean** (no dangling refs, no orphans; fixed one typo FIX-CLASS-007→006).
- [x] **Richer franchise coverage** (per Ryan): added Hill Country Gas Cooperative (2nd multi-city operator) + 3 cities + 3 franchise agreements.
- [x] **Combined Kyle review brief** (`gas-billing-memory 8b46ea2`): fixture questions A1–A8 + gating invariant questions; logged D14.
- [x] **wiki-ingestion-pending.md** updated with Sections C (C1–C5) and D (D1–D14).

## Not Yet Done

- [ ] **Kyle answers the review brief** (`session-1-review-brief.md`) — the gate. Headline: **A1 (§182.025 2% franchise cap)**.
- [ ] **Fold answers into the catalog** — if A1 flips (franchise > 2% allowed), sweep the tagged rates; finalize.
- [ ] **Work Unit 5 — Method 1 per-invariant scenario docs** (`application/invariant-scenarios/<invariant>.md`) — references these fixtures by ID. Itself gated by the invariants' remaining flagged-question review (folded into the same brief, Part B).

## Failed Approaches (Don't Repeat These)

- **None abandoned.** One research-contamination correction applied (see Warnings): the parallel grounding subagents repeated two errors already corrected in project canon (deposit interest as a "PUCT rate"; a "12-month" backbilling cap). Caught and corrected against the config-catalog/invariants before writing — do NOT trust fresh LLM research on Texas gas regulation over the DE-reviewed catalog.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| DE-FX-1: assume §182.025 = 2% franchise cap (all `fee_percentage` ≤ 2%) | Per Ryan, proceed on the config-catalog reading; every rate tagged `# DE-FX-1` so reversal is a one-file sweep. Nothing downstream consumes rates until WU5. |
| Ground to schema enums, not the strategy's lists | 7-value class enum (DE-6) over the strategy's 5 (transport = service-type, not a class); v5.4 `program_types` (11) over the strategy's 9-item program list. Schema/catalog are authoritative. |
| 5 entity types are reference fixtures (no schema columns) | jurisdictions, customer-classes, programs, cities, tax_jurisdictions have no backing table (invariants gaps A-8/A-14; v5.4 pending). Modeled as enumeration fixtures grounded in regulatory/catalog material, not `tu.sql` columns. |
| No `accounts.md` fixtures — structural note only (DE-FX-9) | No `accounts` table exists: account = `customers.customer_number` + `service_locations`; balance-state is ledger seed (per-scenario transactions), not a fixture attribute. |
| Only IOU + Hill Country co-op pay franchise fees | A municipal utility serving its own city pays no franchise fee (it *is* the city); the environs-only co-op has no city. Added a 2nd multi-city operator (per Ryan) for richer coverage. |

## Current State

**Working**: Full WU4 catalog committed and internally consistent (cross-ref walk clean). Reconciliation + review brief committed. gas-billing-memory HEAD = `8b46ea2`.
**Broken**: Nothing — no application code exists yet.
**Uncommitted changes**: In `tally-utility`: `HANDOFF.md` (this rewrite), `CHANGELOG.md` (new entry), `TECH-STACK-DISCUSSION.md` (pre-existing, parallel thread). In `gas-billing-memory`: only `Clippings/` untracked.

## Code Context

Fixture entry shape (YAML-in-markdown), one file per entity type, grouped by parent:
```
id: FIX-<TYPE>-###      # stable, permanent; scenarios reference this
name: <human label>
attributes: { <schema columns, values pulled from config-catalog/tu.sql> }
variation_axes_exercised: [...]     # why this fixture exists
cross_references: [FIX-...: relationship]
source: { config_catalog:[], kb_files:[], invariants:[CI-###], regulatory:[] }
valid_from / valid_to / recorded_at / supersedes    # bi-temporal
```
DE-FX-1 reversal mechanism (if Kyle says franchise can exceed 2%):
```bash
grep -rn "# DE-FX-1" application/test-fixtures/franchise-agreements.md   # every rate to revisit
```
Cross-reference verification (re-run after any edit):
```bash
cd application/test-fixtures && grep -rhoE "^(id: |## |### )FIX-[A-Z]+-[0-9]+" *.md | grep -oE "FIX-[A-Z]+-[0-9]+" | sort -u > /tmp/d.txt
grep -rhoE "FIX-[A-Z]+-[0-9]+" *.md | sort -u | comm -13 /tmp/d.txt -   # dangling refs
```

## Resume Instructions

1. **Check whether Kyle has answered `gas-billing-memory/application/test-fixtures/session-1-review-brief.md`** (inline answers or a new `*-answers` file).
   - Expected: answers to A1–A8 + the Part B invariant questions.
   - If not answered: the build is gated for *final* sign-off, but per the kickoff's cadence you MAY start WU5 on invariants whose framing is already locked. Nudge via the brief.
2. **Once answered:** fold answers into the catalog. If **A1 flips**, `grep "# DE-FX-1"` and adjust franchise rates + the `-INC` rate-schedule notes. Update `README.md` change log + `session-1-recon.md` status.
3. **Then Work Unit 5 (Method 1):** write `application/invariant-scenarios/<invariant-name>.md`, referencing fixtures by ID. Read the scenario-mapping-strategy + this catalog + the invariants doc first; state which invariant you're starting.

## Warnings

- **Fixtures are a provisional draft.** Nine `DE-FX` judgment calls (esp. the 2% franchise) await Kyle. Franchise rates are tagged for cheap reversal; don't let scenario-writing (WU5) compute bills off them until A1 is confirmed.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; the work artifacts live in `gas-billing-memory`.** Don't look for the fixtures in this repo.
- **Don't trust fresh LLM research on Texas gas regulation over the DE-reviewed catalog** — it re-introduced "PUCT rate" and "12-month backbilling" errors this session (both corrected in `jurisdictions.md`).
- **WU5 has its own gate:** the canonical-invariants doc says its remaining flagged questions (Q-1,3,4,5,6,7,8,9,10,12) must be reviewed before per-invariant scenario writing — folded into the same brief (Part B).
- **Texas-only launch.** Multi-state is a deferred Layer-4 axis; don't let it leak into fixtures.
