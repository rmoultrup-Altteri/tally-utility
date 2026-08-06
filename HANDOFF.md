# Handoff: Work Unit 6 Session 3G (Domain 7 — Pre-Mail QA & Exceptions)

**Generated**: 2026-08-06
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3G complete (Domains 1–7 of 13). Fifteen open items across the last four sessions await Kyle; none blocks Session 3H.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue. This session drafted Session 3G and cleared the two workflows deferred from 3F.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/canonical-invariants.md` — 135 canonical invariants (CI-001–135) across 17 families, plus Appendix A's 21 schema-enforcement gaps. Q-4/Q-7/Q-9/Q-12 remain open by design.
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3); governs WU6
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: **65 files** across Sessions 3A–3G
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's earlier resolved decisions (DE-10 and DE-11 live in the `-8-11` file)
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — historical source record, fully folded in; not pending work
- `application/configurable-rules/wu6-sessions-3e-3f-review-brief.md` — the fourth brief, awaiting Kyle
- `application/invariant-scenarios/` — WU5 output: 15 Method-1 axes docs covering all 17 families
- `application/wiki-ingestion-pending.md` — Sections A–N; every file change is logged with a wiki-ingestion target
- `application/execution-kickoff.md` — the 12-work-unit sequence. **Correction:** it does *not* carry a per-session WU6 progress marker (a prior handoff implied it did). Session progress is tracked here and in `wiki-ingestion-pending.md` only — don't go looking for it in the kickoff.

## Completed (this session)

- [x] **Session 3G — Domain 7 (Pre-Mail QA & Exceptions), clusters 33–35** (`gas-billing-memory 8e22bc6`, pushed): three decision tables — `statistical-anomaly-detection` (#33, collect), `absolute-baseline-qa` (#34, collect), `exception-threshold-and-routing` (#35, first-match) — and four workflows: `pre-mail-exception-review`, `canary-account-reconciliation`, plus the two deferred from 3F, `pre-mail-bill-correction` and `high-bill-dispute-intake-and-resolution`. Seven files.
- [x] Logged in `wiki-ingestion-pending.md` Section N + both CHANGELOGs.
- [x] **Pushed** — `gas-billing-memory` level with `origin/main` (verified with `git rev-list --left-right --count origin/main...HEAD`, 0/0).

## Not Yet Done

- [ ] **Sessions 3H through 3M** — delivery/comms (36–38), payments (39–42), programs (43–45), collections/disconnect/deposits (46–55), customer/account lifecycle (56–57), import/admin (58–60). Untouched. **Session 3H is next.**
- [ ] **Kyle answers `wu6-sessions-3e-3f-review-brief.md`** — still awaiting him. Session 3G's four items are not yet in a brief; see "Decide first thing next session" below.
- [ ] **`tally-utility` has no git remote configured** — its commits are local-only with nowhere to push. Worth deciding whether it should have one, given it holds the canonical schema (`sql/tu.sql`) plus all session history.

## Decide first thing next session

**Whether to fold Session 3G's items into the existing 3E–3F brief or start a fifth.** The 3E–3F brief is compiled and unanswered. Three options, and they differ in a way worth a moment's thought rather than a default: append 3G to the unanswered brief (one document for Kyle, but it edits something already handed over); hold 3G and brief 3G+3H together after the next session (matches the batching precedent, and Domains 7 and 8 are genuinely coupled through CI-115/CI-134/CI-135 and the delivery gate); or brief 3G alone now. **Recommendation: hold and brief 3G+3H together** — Domain 8's print-mail integrity work will almost certainly touch the same delivery-gate seam, and item 3 below (defaults leave the gate nearly off) reaches directly into delivery.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (from the 2026-07-05 session): `Agent({prompt: "placeholder", name: "waiter"})` spawns a *real* agent that takes the literal text as its assignment and goes off doing unwanted work. **Instead, end the turn with a short text update and no tool call** — the harness delivers background-task notifications on the next turn regardless.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Third session running with no research agents | Domain 7's substrate is entirely in `sql/tu.sql` and the KB. All four open items came from reading the schema *against* `canonical-invariants.md` and the catalog — specifically, checking CI-134's enforcement-status claim ("canary expected values are configured") against the schema, which is where the session's central finding came from. This is now the confirmed default for any domain whose substrate exists. |
| Stated the two missing baselines as **input-table rows** in cluster 34, not as a note | Three of eleven inputs have no home in the schema. Burying that in Open questions would have let the table read as buildable. Putting `**no substrate**` in the source column makes the reduced slice (row 2 only) obvious at a glance. |
| Both 3F-deferred workflows drafted here, as planned | `pre-mail-bill-correction` earns its separation from cancel-rebill by naming a boundary nothing else in the corpus names: none of Domain 6's apparatus applies before delivery. `high-bill-dispute-intake-and-resolution` earns its place in Domain 7 by being the pre-mail gate's mirror — the dispute rate on bills clusters 33/35 cleared is the only measure of whether those thresholds are right. |
| Cluster 34 given a reduced-slice recommendation rather than left blocked | Row 2 (class average vs. prior year same month) is fully buildable today — both sides queryable from `invoices`. Saying so means the vertical slice isn't gated on Kyle's ruling, and it makes the mass-error gate partially real now rather than entirely notional. |
| `blocks_delivery` separated from `queue` in cluster 35 | It is the output that makes the table a control gate rather than work-tracking, and it is the only output that survives `rbac-model` being unresolved. Separating them makes the v1 slice fall out. |
| Suggested resolutions attached to the three smaller items | Same discipline as 3E/3F: where the schema already demonstrates the pattern (the invoice hold trigger, the CHECK constraints on every sibling enum column), the resolution isn't a judgment call and shouldn't consume Kyle's attention as one. |

## Session 3G's four open items

1. **CI-134's two missing baselines — the session's most consequential item.** Its enforcement status asserts "canary expected values are configured … *not a missing-table gap*," and that claim is what classifies CI-134 `requires-application-discipline` rather than `unenforced-gap`. Against the schema: prior-year-same-month is queryable (correct); **canary expected values are configured nowhere** — no canary table, no `is_canary`/`is_test_account` column, no reserved settings key, so canary accounts cannot even be *identified*; and **the RRC/municipal GUD revenue requirement is not a known input** — no revenue-requirement or rate-case entity. Two of three baselines are gaps, and **A-20 does not cover a canary registry**, so it would fall through the schema-hardening queue entirely.
2. **Nothing in the settings blob is release-blocking.** The four `*_warning_threshold` keys are tenant-tunable and genuinely cycle-level, but they are aggregates of *the batch's own contents* (skip rate, estimation rate, anomaly rate, amount swing) — not comparisons against an external baseline. A misconfiguration in place since the prior cycle passes all four. And every one is named `warning`. DE-10's three thresholds cannot be satisfied by tuning what exists; they are new keys, and at least one must be a gate.
3. **Default settings leave the pre-mail gate nearly off.** `review_required_anomalies` defaults to `[negative_consumption]` — one value, and a *usage* value. No bill-amount condition blocks delivery out of the box, and the `anomaly_type` enum has no `high_bill`/`low_bill`/`zero_bill`/`negative_bill` values to put there. The queue still displays items, so the workflow looks like it's running while the gate is off. **The likeliest real-world failure in this domain, because it requires nobody to do anything wrong.**
4. **No bill-level dispute entity, and `pending_dispute` protection has no trigger.** The read-level dispute substrate is complete; a dispute of a rate, PGA, backbill, or proration has nowhere to live but `customers.billing_hold_reason` (whose own comment offers `"Disputed bill #INV-1247"` as an example). §7.45 collections suspension depends on a CSR remembering a flag, and with no disputed-*amount* concept a partial dispute holds the whole account or none of it — both wrong, in opposite directions.

**Also answered from the schema side: action #40's degree-day question.** HDD exists (`wna_zones.normal_hdd`, `wna_monthly_adjustments.actual_hdd`/`normal_hdd`) but zone-keyed rather than location- or cycle-keyed, limited to `active_months` (defaulting to Nov–Apr), and present only for tenants running WNA. DE-10's wider-band fallback is right for summer cycles and non-WNA tenants — recorded as a known sensitivity reduction in exactly the months a rate change is most likely to roll out. DE-11's portal graph inherits all three limits.

**Three smaller items, each with a suggested resolution:** `billing_runs` needs a `held` status mirroring the invoice pattern (third consumer of that gap, after `billing-run-read-gating` OQ2); `anomalies.entity_type` is the schema's one enum-shaped column without a CHECK, and cluster 35 routes on it; and no trigger freezes a delivered invoice's billing fields, though the pattern exists twice already.

**`rbac-model` gains a second pinned consequence** alongside cluster 32's: cluster 35's `queue` and `escalation_target` are role assignments, so without roles the routing table degrades to a `blocks_delivery` boolean — the sensible v1 slice, but a routing table that does not route.

## Current State

**Working:** `gas-billing-memory` main, **level with `origin/main`** (pushed 2026-08-06). `tally-utility` has no remote. WU5 output (15 axes docs) and WU6 Sessions 3A–3G output (65 decision-table/workflow files) all committed and internally consistent.
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

Non-obvious: hit policies aren't decorative. `rule-order` is not row-matching at all — clusters 17 and 23 are *staged procedures* in table form, and their "rules" are pipeline stages. `collect` (multiple rules co-fire, e.g. `read-vee-validation`, `statistical-anomaly-detection`) vs. `priority` (first-in-order wins) vs. `first-match` (ordered, stops on hit, e.g. `exception-threshold-and-routing`) imply different test-case shapes.

## Resume Instructions

1. **Session 3H — Domain 8 (Delivery & Communications), clusters 36–38.** Read `cluster-and-workflow-inventory.md` Domain 8 plus its Part 2 workflow list (`invoice-pdf-generation-and-retention`, `email-delivery-with-fallback` [addenda], `print-vendor-handoff` [addenda], `consolidated-invoice-assembly`). Known content: cluster 36 is **regulated** (E-SIGN) with Check #4 fix #4 making `mail` the default; cluster 37 is **regulated** (TX bilingual §7.45, and Q-8 resolved it to statewide EN/ES with no county table); cluster 38 merges notice-triggering with proactive alerts and carries the `returned-mail-handling` and `bill-message` targeting gaps. **CI-135 (print-mail integrity and PII-breach classification) lands in this domain.**
2. **Read the schema directly, not just the docs.** Three sessions running, that's where every open item has come from. For Domain 8 the substrate is dense and already located: `tenants.settings.delivery` (nine keys — `pdf_max_attempts`, both retry backoff arrays, `mail_batch_time` default 16:00, `mail_batch_skip_holidays`, `email_provider`, `mail_vendor`), `invoices.delivery_method` (5-value CHECK) / `sent_at` / `pdf_url` / `pdf_generated_at` / `delivery_confirmed_at` / `delivery_failed_reason` / `delivery_attempts`, and the `alerts.alert_type` 21-value enum. Note that `invoices.delivery_method` defaults to `'email'` while Check #4 fix #4 made `mail` the default — **that looks like a live contradiction and is the first thing to check.**
3. **Two of Domain 8's four workflows are `[split-with-addenda]`** — per the strategy, integration-touching workflows get a partner-neutral spec now, with partner-specific exception flows deferred to addenda once partners are selected. `ami-amr-file-ingestion` (Session 3A) is the precedent to follow for shape.
4. **Decide the briefing question above** before drafting, since it affects whether 3G's items get written up this session or next.

## Warnings

- **Commit before ending a session.** An earlier session left 52 files of correct work uncommitted and the next session's first act was rescuing it.
- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`** (which has its own, more detailed CHANGELOG — both get an entry each session). Don't look for decision tables, workflows, or invariant docs in this repo.
- **The open items are deliberate, not authoring mistakes.** Don't resolve them unilaterally in a future session.
- **Verify push state, don't carry a number forward.** A "42 unpushed commits" figure was propagated unverified across several handoffs and was stale. Use `git rev-list --left-right --count origin/main...HEAD` after a fetch.
- **Texas-only launch** remains the scope discipline. Sewer billing and government/wholesale customer classes are still flagged likely-out-of-scope-for-v1 (Sessions 3B/3C) but not formally deferred, unlike Q-12's transport-balancing/submetering/multi-commodity.
- **`tax_jurisdictions` (A-8) is the load-bearing absence across Domain 5. A-20 is Domain 7's** — and per open item 1, A-20's stated scope is now known to be too narrow (no canary registry, no revenue-requirement baseline). Any schema-hardening session that works A-20 inherits that.
- **Domain 7's asymmetry is worth carrying into Domain 8:** the per-bill gate is structurally enforced, the cycle-level gate has no structure at all. Delivery has the same shape — rich per-invoice columns (`delivery_attempts`, `delivery_failed_reason`, `delivery_confirmed_at`), and CI-135's print-mail integrity is a *batch*-level assertion about a vendor handoff. Expect the same gap and check for it early.
