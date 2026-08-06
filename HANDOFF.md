# Handoff: Work Unit 6 Session 3E (Domain 5 — Taxes & Fees), after committing the pending Kyle fold-in

**Generated**: 2026-08-06
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3E complete (Domains 1–5 of 13). Kyle's 2026-07-10 decisions are folded in and committed. Six open items across the last two sessions await Kyle; none blocks Session 3F.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue. This session committed the prior session's uncommitted fold-in, then drafted Session 3E.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — Kyle's consolidated rulings on both review briefs (186 lines). **Fully folded in as of `fe435cc`**; treat it as a historical source record, like `de-review-answers.md`, not as pending work.
- `application/canonical-invariants.md` — 135 canonical invariants (CI-001–135) across 17 families. Q-4/Q-7/Q-9/Q-12 remain open by design; everything else is resolved.
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3); governs WU6
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: 44 files across Sessions 3A–3E
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's earlier resolved decisions (incl. action #28, the §182.025 ceiling)
- `application/invariant-scenarios/` — WU5 output: 15 Method-1 axes docs covering all 17 families
- `application/wiki-ingestion-pending.md` — Sections A–K; every file change is logged with a wiki-ingestion target
- `execution-kickoff.md` — the 12-work-unit sequence (WU1–5 ✅, **WU6 in progress: Sessions 3A–3E ✅, 3F–3M remaining**)

## Completed (this session)

- [x] **Committed the orphaned fold-in** (`gas-billing-memory fe435cc`) — 52 files edited + 1 renamed, applying every one of Kyle's 2026-07-10 rulings. The prior session did the work and never committed it.
- [x] **Session 3E — Domain 5 (Taxes & Fees), clusters 23–26** (`fe07a10`): `tax-application-and-stacking` (#23, rule-order), `tax-exemption-eligibility` (#24, unique), `adhoc-charge-taxation` (#25, priority), `franchise-fee-application` (#26, first-match), plus the `tax-exemption-cert-submission-and-renewal` workflow.
- [x] Logged in `wiki-ingestion-pending.md` Section K + both CHANGELOGs.

## Not Yet Done

- [ ] **Sessions 3F through 3M** — billing run/corrections (27–32), pre-mail QA (33–35), delivery/comms (36–38), payments (39–42), programs (43–45), collections/disconnect/deposits (46–55), customer/account lifecycle (56–57), import/admin (58–60). Untouched. **Session 3F is next.**
- [ ] **Six open items awaiting Kyle** — four from Session 3E (below), two from the fold-in pass (the PSF $1.00-vs-$0.50 cap discrepancy in `regulatory-cost-recovery-surcharges-texas.md`; CI-043's WNA program-exclusion premise in `weather-normalization.md`). None blocks 3F. No consolidated brief has been compiled for these yet — worth doing after 3F or 3G rather than one brief per session.
- [ ] `git push` — `gas-billing-memory` is now **45 commits ahead of origin/main**, still local-only. Never been asked to push.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (from the 2026-07-05 session): `Agent({prompt: "placeholder", name: "waiter"})` spawns a *real* agent that takes the literal text as its assignment and goes off doing unwanted work. **Instead, end the turn with a short text update and no tool call** — the harness delivers background-task notifications on the next turn regardless.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Drafted `tax-exemption-cert-submission-and-renewal` even though the Part 3 queue lists no workflows for Session 3E | The queue's "tax steps fold into billing-run" is right for the tax *application* steps. But this workflow's entire subject is cluster 24's substrate; leaving it to Session 3L means writing it cold, months after walking CI-046. Session 3L inherits it. |
| Skipped research agents this session | The grounding was already in the KB and in `sql/tu.sql`. Reading the schema *directly against* `canonical-invariants.md` Family 6 is what surfaced all four open items — each is a disagreement between the schema and a doc, invisible from either side alone. Prior sessions' agent research was for facts the KB didn't have (named incidents, statutory values); this domain didn't need any. |
| Four schema-vs-doc conflicts flagged, not resolved | Same discipline as Sessions 3A–3D's four tensions. Each has real textual support on both sides, and picking silently would encode a base-composition or exemption assumption into everything downstream. |
| Stated `tax_jurisdictions`' absence as a scoping fact rather than an open question | A-8 is a known, tracked gap. The useful thing wasn't re-asking about it but saying what follows: cluster 23's per-jurisdiction loop has one or two iterations for Texas launch, not eight, and the only implementable slice today is cluster 26. |

## Session 3E's four open items (the ones a future session needs to know)

1. **`rate_items.is_taxable_default` defaults to `false`** — CI-045's named silent failure ("new charge rolled out with no explicit classification") is the current schema default, in the under-collecting direction, and "explicitly false" is indistinguishable from "never decided."
2. **`franchise_fee_rules.applies_to` vs. the per-item `is_taxable` chain** — two mechanisms for one concept; none of `applies_to`'s four values can express "gross revenue minus PSF," the carve-out 16 TAC §8.201 mandates. **The most consequential of the four** — decides whether CI-038's exclusion is implementable today.
3. **Two exemption substrates, one wired** — `should_charge_tax()` reads only `customer_tax_exemptions`, never the legacy `customers.is_tax_exempt`. And the renewal prompt CI-046 asks for *already exists on the legacy substrate* (`tax_exemption_expiry_date` + a 60-day `expiring_soon` view), never ported.
4. **`franchise_city` on both `service_locations` and `rate_schedules`**, both indexed, no precedence stated. The tables assume premise-side (CI-044) and say so.

Plus two smaller defects with suggested resolutions attached: `miscellaneous` is the one `adhoc_charges.charge_type` value absent from the platform taxability-defaults list, and the taxability settings key is spelled `adhoc_taxability_overrides` in the schema comment vs. `adhoc.taxability_overrides` in the catalog.

## Current State

**Working:** `gas-billing-memory` main, 45 commits ahead of `origin/main` (not pushed). WU5 output (15 axes docs, 17 families) and WU6 Sessions 3A–3E output (44 decision-table/workflow files) all committed and internally consistent.
**Broken:** Nothing — no application code exists yet; this is all Layer 1–3 planning/decision-table documentation.
**Uncommitted changes:** In `tally-utility`: `TECH-STACK-DISCUSSION.md` (pre-existing, unrelated parallel thread — untouched), plus this HANDOFF rewrite and the CHANGELOG entry. In `gas-billing-memory`: only `Clippings/` untracked (pre-existing, not KB content).

## Code Context

No application code. The two Layer-2/Layer-3 templates every WU6 file follows exactly (`application/configurable-rules-scenario-strategy.md`):

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

Non-obvious: hit policies aren't decorative. `rule-order` is not row-matching at all — clusters 17 and 23 are both *staged procedures* documented in table form, and their "rules" are pipeline stages. `collect` (multiple rules co-fire, e.g. `read-vee-validation`) vs. `priority` (first-in-order wins, e.g. `adhoc-charge-taxation`'s three-level chain) vs. `first-match` (ordered, stops on hit, e.g. `franchise-fee-application`) imply different test-case shapes.

## Resume Instructions

1. **Session 3F — Domain 6 (Billing Run, Corrections & Backbilling), clusters 27–32.** Read `cluster-and-workflow-inventory.md` Domain 6 plus its workflow list (billing-run, final-bill, cancel-rebill, adjustments). This is a heavy domain: cluster 27's backbilling cap is **per-cause** per §7.45 (action #9 corrected it from per-jurisdiction), cluster 28 carries DE-3 (gas = full correction, no threshold, historical-rate guard), and cluster 29 is the bi-temporal cancel-rebill replay.
2. **Read the schema directly, not just the docs.** Session 3E's whole yield came from `sql/tu.sql` vs. `canonical-invariants.md`. For Domain 6 the relevant functions already exist: `get_correction_rate_date()` (documented resolution order: custom date > per-target historical/current > run-level default) and the `adhoc_charges` `void_pending_rebill` lifecycle state.
3. **Don't re-litigate the six open items** — they're waiting on Kyle specifically because both sides have textual support. Consider compiling them into one consolidated brief after 3F or 3G, following the `wu6-decision-tables-review-brief.md` precedent, rather than one brief per session.

## Warnings

- **Commit before ending a session.** The prior session left 52 files of correct work uncommitted; this session's first act was rescuing it. It survived, but only because nothing touched the working tree in between.
- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`.** Don't look for decision tables, workflows, or invariant docs in this repo.
- **The open items are deliberate, not authoring mistakes.** Don't resolve them unilaterally in a future session.
- **Texas-only launch** remains the scope discipline. Sewer billing and government/wholesale customer classes are still flagged as likely-out-of-scope-for-v1 (Sessions 3B/3C) but not formally deferred, unlike Q-12's transport-balancing/submetering/multi-commodity.
- **`tax_jurisdictions` (A-8) is the load-bearing absence across all of Domain 5.** Any future session that touches tax, franchise fee, or premise jurisdiction assignment inherits it.
