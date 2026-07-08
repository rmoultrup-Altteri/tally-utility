# Handoff: Work Unit 5 completion + Work Unit 6 Sessions 3A–3D (Configurable-Rules)

**Generated**: 2026-07-05
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 fully complete (all 17 invariant families); WU6 Sessions 3A–3D complete (Domains 1–4 of the Sessions 3+ configurable-rules queue). Two consolidated Kyle review briefs awaiting answers before either work unit's next phase.

## Goal

Finish **Work Unit 5** (Method 1 per-invariant scenario docs, per `execution-kickoff.md`) — axes-of-variation drafts for all 17 canonical-invariant families — then begin **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/canonical-invariants.md` — 135 canonical invariants (CI-001–135) across 17 families; **status line and Flagged section were stale on Q-3 until this session fixed it (see Failed Approaches / Key Decisions)**
- `application/invariant-scenarios/` — WU5 output: 15 Method-1 axes docs (all 17 families represented; Family 17's 4 residuals folded into 4 existing docs) + `wu5-axes-review-brief.md` (consolidated Kyle brief)
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3); governs WU6
- `application/configurable-rules/decision-tables/` and `application/configurable-rules/workflows/` — WU6 output so far: 39 files across Sessions 3A–3D
- `application/configurable-rules/wu6-decision-tables-review-brief.md` — consolidated Kyle brief for WU6
- `application/configurable-rules/de-review-answers.md` — Kyle's resolved decisions (DE-1..7, plus later batches); cross-check this against `canonical-invariants.md`'s Flagged section before trusting the latter as current
- `application/wiki-ingestion-pending.md` — Sections A–I; every file change this session is logged here with a wiki-ingestion target
- `execution-kickoff.md` — the 12-work-unit sequence (WU1–4 ✅, WU5 ✅ this session, **WU6 in progress: Sessions 3A–3D ✅, 3E–3M remaining**)

## Completed (this session)

**Work Unit 5 (finished):**
- [x] Drafted Families 14, 15, 16 (4 docs): `read-exception-handling-and-estimation.md`, `tenant-isolation-and-structural-integrity.md`, `account-lifecycle-mimo-and-final-bill.md`, `deposits-credits-and-operational-integrity.md`
- [x] Family 17 fold-in pass: CI-132 (regulatory posture) → `mid-period-and-temporal-rate-selection.md`; CI-133 (transport eligibility) → `pga-and-commodity-pass-through.md`; CI-134 (batch absolute-baseline gate) → `read-exception-handling-and-estimation.md`; CI-135 (print-mail PII-breach) → `customer-communication-and-notice-discipline.md`
- [x] Compiled `wu5-axes-review-brief.md` — consolidated, plain-language Kyle brief across all 17 families (Part A: new judgment calls; Part B: 9 still-open Q-numbers now mapped to specific blocking docs/axes; Part C: 2 doc-placement calls)
- [x] **Found and fixed a stale cross-document status**: Q-3 (WNA deadband scoping) was resolved by Kyle on 2026-06-12 (`de-review-answers.md`, `wna-config-gaps`, action item #12) but `canonical-invariants.md` was never updated — its status line, Flagged section, and CI-041 all still said "open." Also corrected the two downstream docs that inherited the stale status (`weather-normalization.md`, and the WU5 review brief itself, which had incorrectly asked Kyle to re-answer it).

**Work Unit 6 (Sessions 3A–3D of the Sessions 3+ queue):**
- [x] Session 3A — Domain 1 (Reads, Validation & Estimation): 6 decision tables (clusters 1–6) + 6 workflows
- [x] Session 3B — Domain 2 (Gas Measurement & Consumption): 4 decision tables (clusters 7–10) + 4 workflows
- [x] Session 3C — Domain 3 (Rating & Tariff Engine): 9 decision tables (clusters 11–19) + 4 workflows — the queue's own largest single domain
- [x] Session 3D — Domain 4 (PGA / WNA / Gas Cost Recovery): 3 decision tables (clusters 20–22) + 3 workflows
- [x] Compiled `wu6-decision-tables-review-brief.md` — consolidated Kyle brief across all 39 files, with 4 flagged tensions in Part A (see Key Decisions)

**Method used throughout:** parallel Explore-agent research (grounding facts, exact schema/catalog columns, named failure incidents) before drafting each table/workflow personally, to keep voice and rigor consistent — never delegated authorship, only research.

## Not Yet Done

- [ ] **Kyle answers `wu5-axes-review-brief.md` and `wu6-decision-tables-review-brief.md`** — both gates, same pattern as WU4's brief. Per the kickoff's cadence, drafting MAY continue in parallel on domains/families whose framing is already locked.
- [ ] **Work Unit 6, Session 3E — Domain 5 (Taxes & Fees)**, clusters 23–26 (`tax-application-and-stacking`, `tax-exemption-eligibility`, `adhoc-charge-taxation`, `franchise-fee-application`) + workflows. Next in the Part 3 queue. This domain consumes Session 3C's settled rider stack and Session 3D's PGA output as its own inputs (per CI-100's canonical pipeline order).
- [ ] Sessions 3F through 3M (billing run/corrections, pre-mail QA, delivery/comms, payments, programs, collections/disconnect/deposits, customer/account lifecycle, import/admin) — untouched.
- [ ] Fold Kyle's answers into both briefs once received (especially WU6 Part A's 4 tensions, which block downstream sessions the most directly).
- [ ] `git push` the 42 unpushed commits in `gas-billing-memory` — left local-only this session; wasn't asked to push.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism**: tried calling `Agent({prompt: "placeholder", name: "waiter"})` repeatedly, intending only to pause and pick up a background-task notification on the next turn → this spawns a *real* agent that takes the literal text as its assignment, so it went and did unwanted investigative work (6 times, compounding) → **instead, just end the turn with a short text update and no tool call; the harness delivers background-task notifications automatically on the next turn regardless.** Had to send stand-down `SendMessage`s to all 6 spawned agents to stop them.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Fixed the stale Q-3 status forward (updated `canonical-invariants.md` + 2 downstream docs) rather than leaving it | It was actively producing wrong output — the WU5 review brief was asking Kyle to re-answer something he'd resolved 3 weeks earlier. Caught mid-research for an unrelated session (3D's WNA table), not through a systematic check — flagged in both CHANGELOGs as a process gap worth addressing (a lighter-weight periodic reconciliation between `de-review-answers.md` and the Flagged section). |
| Family 17's 4 residual invariants folded in one batched pass, after all 16 topic families existed, rather than incrementally | Every prior family's fold-in was deferred by design (all 16 prior docs noted the deferral); doing all 4 at once avoided drafting against still-changing predecessor docs, since each fold-in cross-references invariants living in its own home doc. |
| WU6 tables/workflows: research-then-draft via parallel Explore agents, but authorship stayed manual (never delegated) | Same practice as WU5 — keeps voice, rigor, and cross-referencing consistent across 39+ files; agents supply grounding facts (exact schema columns, named incidents), not prose. |
| 4 genuine tensions (PGA correction path; `pga-monthly-trueup`'s name; `prorate_tier_breakpoints` schema default vs. CI-108's stated invariant default; WNA floor/ceiling guard) flagged explicitly rather than resolved unilaterally | Each is a conflict between two sources that both look authoritative (an invariant statement vs. a named failure-mode description, or a schema default vs. an invariant's stated default) — picking a side without Kyle's input risks encoding a wrong assumption into 39 files' worth of downstream scenario-writing. |

## Current State

**Working:** `gas-billing-memory` main branch, 42 commits ahead of `origin/main` (not pushed). All WU5 output (15 axes docs covering 17 families) and WU6 Sessions 3A–3D output (39 decision-table/workflow files) committed and internally consistent. Two consolidated Kyle review briefs exist, both awaiting answers.
**Broken:** Nothing — no application code exists yet; this is all Layer 1–3 planning/decision-table documentation per the configurable-rules and invariant strategies.
**Uncommitted changes:** In `tally-utility`: `TECH-STACK-DISCUSSION.md` (pre-existing, unrelated parallel thread — not touched this session), `HANDOFF.md` (this rewrite), `CHANGELOG.md` (new entry pending). In `gas-billing-memory`: only `Clippings/` untracked (pre-existing, not KB content).

## Code Context

No application code exists. The relevant "interfaces" are the two Layer-2/Layer-3 templates every WU6 file follows exactly (`application/configurable-rules-scenario-strategy.md`):

```
# Decision Table: <Name>
**Cluster:** <name> (#N)  **Hit policy:** unique|first-match|priority|collect|rule-order
**Catalog refs / Invariant refs / Pending decisions / KB refs**
## Inputs | Outputs | Rules | Out of scope | Open questions | Test note
```

```
# Workflow: <Name>
**Goal / Primary actor / Trigger / Preconditions / Postconditions (success, failure)**
**Decision table refs / Catalog refs / Invariant refs / KB refs**
## Main success scenario | Alternative flows | Exception flows | State transitions | Open questions | Test note
```

Non-obvious logic: hit policies are not decorative — `collect` (multiple rules can co-fire, e.g. `read-vee-validation`) vs. `priority` (first-in-order wins on conflict, e.g. `gas-conversion-and-energy`'s residential-Fp-always-1.0 rule) vs. `rule-order` (a topological sort, not row-matching at all — `rate-item-dependency-ordering`) each imply different test-case shapes.

## Resume Instructions

1. **Check whether Kyle has answered either review brief** (`application/invariant-scenarios/wu5-axes-review-brief.md` or `application/configurable-rules/wu6-decision-tables-review-brief.md`) — look for inline answers or a new `*-answers` file, per the `de-review-answers.md` precedent.
   - Expected: answers to WU5's 9 remaining Q-numbers and WU6 Part A's 4 tensions.
   - If not answered: proceed to Session 3E anyway per the kickoff's parallel-drafting cadence (same as this session did for WU5/WU6).
2. **If continuing to Session 3E:** read `cluster-and-workflow-inventory.md` Domain 5 (clusters 23–26) + its workflow list. Use the same research-then-draft pattern: spawn parallel Explore agents for grounding (exact tax-stacking rules, franchise-fee mechanics, named failure incidents), then personally author each decision table and workflow file against `configurable-rules-scenario-strategy.md`'s templates.
3. **Once Kyle's answers land:** fold them into the axes/tables — WU6 Part A's 4 tensions first, since they block the most downstream work (Sessions 3E+ all consume the settled rider/tax stack).

## Warnings

- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches — it does real unwanted work instead.
- **`canonical-invariants.md`'s Flagged section can drift from `de-review-answers.md`'s action items** — Q-3 just demonstrated this. Before treating any Q-number as "open," cross-check `de-review-answers.md` and `configuration-catalog.md` for a resolution that was never back-propagated.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`.** Don't look for the decision tables, workflows, or invariant docs in this repo.
- **The 4 flagged tensions are deliberate open questions, not authoring mistakes** — don't resolve them unilaterally in a future session; they're waiting on Kyle specifically because both sides have textual support.
- **Texas-only launch** remains the scope discipline throughout WU6, same as WU5 — sewer billing and government/wholesale customer classes are flagged as likely-out-of-scope-for-v1 in Sessions 3B/3C but not yet formally deferred (unlike Q-12's transport-balancing/submetering/multi-commodity, which already has a tracked deferral).
