# Handoff: Work Unit 6 Sessions 3E + 3F (Domains 5–6), after committing the pending Kyle fold-in

**Generated**: 2026-08-06
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3F complete (Domains 1–6 of 13). Kyle's 2026-07-10 decisions are folded in and committed. Eleven open items across the last three sessions await Kyle; none blocks Session 3G.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue. This session committed the prior session's uncommitted fold-in, then drafted Sessions 3E and 3F.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — Kyle's consolidated rulings on both review briefs (186 lines). **Fully folded in as of `fe435cc`**; treat it as a historical source record, like `de-review-answers.md`, not as pending work.
- `application/canonical-invariants.md` — 135 canonical invariants (CI-001–135) across 17 families. Q-4/Q-7/Q-9/Q-12 remain open by design; everything else is resolved.
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3); governs WU6
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: 58 files across Sessions 3A–3F
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's earlier resolved decisions (incl. action #28, the §182.025 ceiling)
- `application/invariant-scenarios/` — WU5 output: 15 Method-1 axes docs covering all 17 families
- `application/wiki-ingestion-pending.md` — Sections A–L; every file change is logged with a wiki-ingestion target
- `execution-kickoff.md` — the 12-work-unit sequence (WU1–5 ✅, **WU6 in progress: Sessions 3A–3F ✅, 3G–3M remaining**)

## Completed (this session)

- [x] **Committed the orphaned fold-in** (`gas-billing-memory fe435cc`) — 52 files edited + 1 renamed, applying every one of Kyle's 2026-07-10 rulings. The prior session did the work and never committed it.
- [x] **Session 3E — Domain 5 (Taxes & Fees), clusters 23–26** (`fe07a10`): `tax-application-and-stacking` (#23, rule-order), `tax-exemption-eligibility` (#24, unique), `adhoc-charge-taxation` (#25, priority), `franchise-fee-application` (#26, first-match), plus the `tax-exemption-cert-submission-and-renewal` workflow.
- [x] **Session 3F — Domain 6 (Billing Run, Corrections & Backbilling), clusters 27–32** (`5b10d7e`): `backbilling-cap-enforcement` (#27), `correction-and-void-eligibility` (#28), `cancel-rebill-bitemporal` (#29), `billing-run-read-gating` (#30), `invoice-consolidation` (#31), `adjustment-authorization` (#32), plus eight workflows — 14 files, the largest remaining domain.
- [x] **Consolidated the Phase 0–9 billing pipeline** (previously only in scattered `sql/tu.sql` column comments) into `billing-run-normal-cycle`, as the reference the whole domain points at.
- [x] Logged in `wiki-ingestion-pending.md` Sections K and L + both CHANGELOGs.

## Not Yet Done

- [ ] **Sessions 3G through 3M** — pre-mail QA (33–35), delivery/comms (36–38), payments (39–42), programs (43–45), collections/disconnect/deposits (46–55), customer/account lifecycle (56–57), import/admin (58–60). Untouched. **Session 3G is next.**
- [ ] **Two workflows deferred from 3F into 3G:** `pre-mail-bill-correction` and `high-bill-dispute-intake-and-resolution`. Part 2 files both under pre-mail/correction, but pre-delivery correction is a different operation from void/rebill and belongs with the pre-mail QA cluster set.
- [ ] **Eleven open items awaiting Kyle** — five from 3F and four from 3E (both listed below), plus two from the fold-in pass (the PSF $1.00-vs-$0.50 cap discrepancy in `regulatory-cost-recovery-surcharges-texas.md`; CI-043's WNA program-exclusion premise in `weather-normalization.md`). None blocks 3G. **A consolidated brief is now worth compiling** — eleven items across three sessions is past the point where one brief per session would have been the lighter option; follow the `wu6-decision-tables-review-brief.md` precedent.
- [ ] `git push` — `gas-billing-memory` is now **46 commits ahead of origin/main**, still local-only. Never been asked to push.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (from the 2026-07-05 session): `Agent({prompt: "placeholder", name: "waiter"})` spawns a *real* agent that takes the literal text as its assignment and goes off doing unwanted work. **Instead, end the turn with a short text update and no tool call** — the harness delivers background-task notifications on the next turn regardless.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Drafted `tax-exemption-cert-submission-and-renewal` even though the Part 3 queue lists no workflows for Session 3E | The queue's "tax steps fold into billing-run" is right for the tax *application* steps. But this workflow's entire subject is cluster 24's substrate; leaving it to Session 3L means writing it cold, months after walking CI-046. Session 3L inherits it. |
| Skipped research agents this session | The grounding was already in the KB and in `sql/tu.sql`. Reading the schema *directly against* `canonical-invariants.md` Family 6 is what surfaced all four open items — each is a disagreement between the schema and a doc, invisible from either side alone. Prior sessions' agent research was for facts the KB didn't have (named incidents, statutory values); this domain didn't need any. |
| Four schema-vs-doc conflicts flagged, not resolved | Same discipline as Sessions 3A–3D's four tensions. Each has real textual support on both sides, and picking silently would encode a base-composition or exemption assumption into everything downstream. |
| Stated `tax_jurisdictions`' absence as a scoping fact rather than an open question | A-8 is a known, tracked gap. The useful thing wasn't re-asking about it but saying what follows: cluster 23's per-jurisdiction loop has one or two iterations for Texas launch, not eight, and the only implementable slice today is cluster 26. |
| Session 3F drafted 8 workflows against the queue's listed 4 | Domain 6's Part 2 workflow set genuinely spans that many distinct operations (two run types, final bill, two cancel-rebill paths, two adjustment scales, one compliance review). Precedent exists — 3C shipped 13 files. Only the two pre-mail ones were deferred, and for a reason of kind rather than volume. |
| No research agents for a second session running | Domains 5 and 6 both have substrate already in `sql/tu.sql`. Every open item from both sessions came from reading the schema *against* the prose docs — they disagree in specific, findable ways that neither side reveals alone. This now looks like the right default for any domain whose substrate exists; agent research remains right for domains needing facts the KB lacks. |

## Session 3E's four open items (the ones a future session needs to know)

1. **`rate_items.is_taxable_default` defaults to `false`** — CI-045's named silent failure ("new charge rolled out with no explicit classification") is the current schema default, in the under-collecting direction, and "explicitly false" is indistinguishable from "never decided."
2. **`franchise_fee_rules.applies_to` vs. the per-item `is_taxable` chain** — two mechanisms for one concept; none of `applies_to`'s four values can express "gross revenue minus PSF," the carve-out 16 TAC §8.201 mandates. **The most consequential of the four** — decides whether CI-038's exclusion is implementable today.
3. **Two exemption substrates, one wired** — `should_charge_tax()` reads only `customer_tax_exemptions`, never the legacy `customers.is_tax_exempt`. And the renewal prompt CI-046 asks for *already exists on the legacy substrate* (`tax_exemption_expiry_date` + a 60-day `expiring_soon` view), never ported.
4. **`franchise_city` on both `service_locations` and `rate_schedules`**, both indexed, no precedence stated. The tables assume premise-side (CI-044) and say so.

Plus two smaller defects with suggested resolutions attached: `miscellaneous` is the one `adhoc_charges.charge_type` value absent from the platform taxability-defaults list, and the taxability settings key is spelled `adhoc_taxability_overrides` in the schema comment vs. `adhoc.taxability_overrides` in the catalog.

## Session 3F's five open items

1. **DE-3's gas guard doesn't exist and the schema argues against it.** DE-3 requires gas correction runs to reject `correction_rate_mode='current'` via a hard guard and marks it a proposed new invariant. Never implemented, never added to `canonical-invariants.md`, and **both relevant column comments document `current` as existing precisely for the wrong-meter case** the prohibition would forbid. Governs cluster 29 and both cancel-rebill workflows identically. **The most consequential item across 3E and 3F.**
2. **Backbilling is unenforced end to end.** No cap table (A-2), no cause column, no period check in `void_invoice()` — current behavior is unbounded backbilling for every cause, including ones §7.45 caps at three months. Underneath: the cause enum can't be derived from `invoices.void_reason_code`'s seven *operational* values, and **`rate_misapplication`'s 6-month rule is a collectability protection (disconnection prohibited), not a rebill window** — the cap table holds two kinds of limit in one enum.
3. **Consolidated invoices: parent or children post to `account_ledger`?** Unencoded. Both double-counts and breaks CI-019; parent-only hides per-location arrears from collections; children-only leaves the delivered artifact with no ledger presence.
4. **No aggregate authorization.** Ten thousand $1 adjustments each pass the per-charge threshold a single $10,000 adjustment would fail. No aggregate concept in the schema, no bulk-operation entity.
5. **Unapproved charges aren't excluded from billing pickup.** The documented Phase-5 predicate doesn't test `requires_approval` / `approved_at` — approval is currently advisory. One predicate clause, but it changes a documented engine contract.

Plus two smaller findings: cluster 32's threshold must compare `abs(amount)` (the column is signed; a naive `>=` leaves credits ungated, the direction that costs money), and `adhoc_charges.voided_from_invoice_id`'s comment documents the correction audit chain with its last hop pointing the wrong way.

**`pending-decision: rbac-model` is not new but is now pinned to a consequence:** cluster 32 is where its absence removes a control rather than coarsening one — rule 1 is purely about authority, so with no role model the table degrades to a size check.

## Current State

**Working:** `gas-billing-memory` main, 46 commits ahead of `origin/main` (not pushed). WU5 output (15 axes docs, 17 families) and WU6 Sessions 3A–3F output (58 decision-table/workflow files) all committed and internally consistent.
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
- **Domain 6 is the first domain where substantial application logic already ships.** `void_invoice()` (~270 lines) and `get_correction_rate_date()` implement much of clusters 28 and 29. Its tables specify what those functions *don't* do — don't read them as proposing behavior from scratch, and don't propose changes to those functions without noting they are shipped contracts documented in column comments.
