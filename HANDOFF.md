# Handoff: Work Unit 6 Session 3I (Domain 9 — Payments)

**Generated**: 2026-08-07
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3I complete (Domains 1–9 of 13). Twenty-three open items across the last six sessions await Kyle: **two compiled briefs** plus **Session 3I's four items, not yet briefed**. None blocks Session 3J.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/canonical-invariants.md` — 135 invariants (CI-001–135) across 17 families, plus Appendix A's 21 schema-enforcement gaps. Q-4/Q-7/Q-9/Q-12 open by design.
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3); governs WU6
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: **82 files** across Sessions 3A–3I
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's earlier resolved decisions
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — historical source record, fully folded in. **D7-1 and D7-2 are Domain 9's; read them before touching payments again.**
- `application/configurable-rules/wu6-sessions-3e-3f-review-brief.md` and `wu6-sessions-3g-3h-review-brief.md` — the fourth and fifth briefs, **both open, both awaiting Kyle**, independent of each other
- `application/wiki-ingestion-pending.md` — Sections A–Q; every file change logged with a wiki-ingestion target
- `application/execution-kickoff.md` — the 12-work-unit sequence. It does **not** carry a per-session WU6 progress marker; session progress lives here and in `wiki-ingestion-pending.md` only.

## Completed (this session)

- [x] **Session 3I — Domain 9 (Payments), clusters 39–42** — four decision tables (`payment-posting-allocation` #39 priority, `overpayment-and-credit-disposition` #40 priority, `nsf-and-ach-return-handling` #41 first-match, `autopay-eligibility-and-failure` #42 first-match) and six workflows (`lockbox-remittance-ingestion` [addenda], `payment-gateway-webhook-handling` [addenda], `ach-return-handling`, `autopay-enrollment-and-management`, `unapplied-cash-resolution`, `refund-processing`). **Ten files — largest single WU6 session.**
- [x] **Narrowed Session 3H's item 2** — cluster 42's "Check #4 fix #3" citation has its substance recorded in the catalog under the 2026-06-12 review, in Kyle's voice. Mislabeling is likelier than an unrecorded ruling. See "Correction carried" below.
- [x] Logged in `wiki-ingestion-pending.md` Section Q + both CHANGELOGs.

## Not Yet Done

- [ ] **Sessions 3J through 3M** — programs (43–45), collections/disconnect/deposits (46–55), customer/account lifecycle (56–57), import/admin (58–60). Untouched. **Session 3J is next.**
- [ ] **Session 3I has no review brief yet.** The pattern from 3E–3F and 3G–3H is a consolidated brief every two sessions, so the natural move is to draft **3I–3J jointly after Session 3J** rather than briefing 3I alone. That also matches the domains: Domain 9's `agency_pledge` payment-restriction gap and Domain 10's `agency_pledge` program enrollment are the same program seen from the money side and the enrollment side, and briefing them together is the only way Kyle sees that.
- [ ] **Kyle answers the two open briefs** — `wu6-sessions-3e-3f-review-brief.md` (four Part A items) and `wu6-sessions-3g-3h-review-brief.md` (four more). Still both outstanding. My suggestion if asked which first remains 3G–3H, for the reasons recorded in the prior handoff.
- [ ] **`tally-utility` has no git remote configured** — local-only, with nowhere to push, while holding the canonical schema and all session history. Worth deciding; carried unchanged from the last three handoffs.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (2026-07-05): `Agent({prompt: "placeholder", name: "waiter"})` spawns a *real* agent that takes the literal text as its assignment and does unwanted work. **End the turn with a short text update and no tool call** — background-task notifications arrive on the next turn regardless.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Ranked CI-050's regulated-first floor **above** D7-1's agency restriction | The one genuine collision in cluster 39, and it is made rather than deferred. D7-1 says an agency restriction wins over posting order; CI-050 says regulated-first binds "regardless of earmarking." They collide only when an agency pledges to an unregulated balance while gas is in arrears — and there, honoring the restriction produces the CenterPoint failure mode, where the LDC (not the agency) is the party the regulator sanctions. Recorded with a mandatory notice to both customer and agency, so the override of a third party's stated intent is never silent. |
| Corrected A-12 **downward** rather than restating it | A-12 cites a column that does not exist (`payments.account_id`) and claims the received-but-unapplied state has no substrate. `payments.unapplied_amount` exists with a purpose-built partial index. The unidentified-*payer* half is real and total; the amount-mismatch half — much the most frequent — already works. That changes the build from a parallel suspense ledger to a five-column intake table whose items leave it by *becoming* payments. Third consecutive session in which an Appendix-A gap proved materially smaller against the schema. |
| Raised the balance-maintenance finding in **three files** rather than once | `payments.applied_amount` / `unapplied_amount` have no CHECK (unlike `customer_credits`) and nothing maintains them — no posting function exists anywhere in `sql/tu.sql`. It is repeated in `lockbox-remittance-ingestion`, `ach-return-handling`, and `unapplied-cash-resolution` because three workflows read the same unmaintained column, and the repetition *is* the priority argument. |
| Proposed scoping the E-SIGN and Reg E consent substrates **jointly** | Session 3H found no E-SIGN delivery-consent record; this session found no Reg E debit-authorization record. The shapes are near-identical (event, timestamp, disclosure/terms version, scope, channel). Landing two near-duplicate consent tables six weeks apart is how a schema acquires two ways to answer one question. Stated as a design note across both files rather than as a fifth open item. |
| Named the appendix a **hypothesis register** rather than an inventory | Fifth material error in three sessions, now erring in both directions. The planning consequence is concrete: any schema-hardening estimate derived from Appendix A is wrong both ways until each entry is re-checked against `sql/tu.sql`. |

## Session 3I's four open items

1. **D7-1's ruling cannot be executed — the tier that wins has nowhere to be recorded.** Kyle closed Q-5 with tiered payment-class allocation, where agency/pledge payments carry a restriction "stored on the payment record." There is no such field: no payer-class, restriction-target, or restriction-source column, and `channel` (10 values), `payment_method` (12), and `source_system` (6) each describe something else entirely. **An agency check and a customer check arriving by mail are the same record.** Three small columns close it, and A-11's v5.4 patch already lands `agency_pledge` as a `program_types` value — so without this, the enrollment and the money arrive in different releases. **New failure mode for the corpus: a gap under a *closed* question, not an open one.**
2. **`invoice_applications` is per-invoice, not per-charge, so CI-050's floor has no expression even after D7-2.** CI-049's schema-status line says the table "records the per-charge-per-payment application." It has `invoice_id`, `source_type`, `source_id`, `amount` — no line-item FK, and all four indexes key on `invoice_id` or `(source_type, source_id)`. Regulated and unregulated charges sit on the **same** consolidated invoice by design. So D7-2's `regulatory_class` enum classifies the charge and the application record still cannot say which charges a payment covered. Closing CI-050 needs the classification **and** either line-item granularity or a versioned derivation rule — the second is cheaper and satisfies CI-049's reproducibility, and should be chosen rather than defaulted into.
3. **A-12 is two gaps under one name, and the schema already solves one.** See Key Decisions. Corrected ask: a narrow unidentified-receipt intake table (amount, intake timestamp for CI-056's clock, channel, evidence refs, candidate matches, resolution lineage into `payments`). **Separately and sharply: `payments` lacks the balance CHECK `customer_credits` has, nothing maintains either column, and no payment-posting or allocation function exists anywhere in the schema** — the complete function inventory is `compute_ledger_running_balance()` and `void_invoice()`. Five denormalized totals across three tables rest on convention.
4. **The escheatment dormancy clock is hardcoded to one value for every property type, in a shipped materialized view.** `credit_aging_statistics` computes `escheat_due` at `>= 1095` days for all ten `origin_type` values. The catalog's own 2026-06-12 Texas check established that utility deposits run §72.1017's deposit-specific clock (18 months, with the Comptroller chart listing one year) while general credits fall under §72.101's three years — "the escheatment engine needs per-property-type dormancy periods, not one number." `origin_type = 'deposit_refund'` is in the enum and the view ignores it. **Not a missing feature — a view that computes a wrong answer for deposits by roughly eighteen months, on the exact artifact an unclaimed-property audit requests.** Cheapest of the four.

**Also surfaced, smaller:** no unique constraint or index on `payments.provider_transaction_id` (one constraint closes duplicate-webhook phantom refunds — cheapest high-value item in the domain); `nsf_reason` is free text where every sibling classification column has a CHECK, and every code-specific NACHA rule dispatches on it; no autopay disable threshold exists anywhere despite the platform counting, indexing, and reporting failures; `skipped_below_threshold` names the opposite of its documented meaning; `billing_day` accepts 29/30/31 with no month-end rule and three candidate behaviors that differ by a whole payment; `auto_pay_settings UNIQUE (customer_id)` caps a multi-premise customer at one enrollment; `payment_provider_logs.operation_type` has no value for a return, NOC, or chargeback; no ACH re-presentment counter; no hold period before refunding recently-received funds despite `source_payment_id` already carrying the inputs; **CI-057's Notice-of-Change window has no substrate at all**, and its failure chain (NOC unrecorded → three R03 returns → threshold → enrollment disabled → late fees) is the session's clearest end-to-end story.

**Design note, not a ruling:** the E-SIGN (3H) and Reg E (3I) consent substrates should be scoped as one table with a type discriminator.

**Procurement criterion, not a ruling (second in the corpus):** lockbox postmark capture is a priced vendor service tier. A bank selected without per-item capture makes Kyle's 2026-06-12 Texas timeliness ruling unimplementable for mailed payments — same shape as Session 3H's print-vendor match-assertion criterion, and it needs to reach vendor selection before contracting.

## Correction carried

Session 3H's item 2 flagged that **"Check #4" appears nowhere in the KB** while the inventory cites "Check #4 fix #4" as settled. That stands. What this session adds is a narrowing: cluster 42 cites "**Check #4 fix #3**" for the `billing_day` → `draft_day` rename, and **that substance is recorded** — in the configuration catalog's `autopay-enrollment` entry, under the 2026-06-12 review, in Kyle's voice with the reasoning intact. So at least some of what "Check #4" cites is real and landed elsewhere under a different label. **Mislabeling is now the likelier explanation than an unrecorded ruling.** Session 3H's item 2 should be put to Kyle as "which document is Check #4 a wrong name for?" rather than "did these decisions happen?" — a smaller and more answerable question. When the 3I brief is compiled, brief the narrowed form.

## Current State

**Working:** `gas-billing-memory` main. WU5 output (15 axes docs) and WU6 Sessions 3A–3I output (82 decision-table/workflow files) all internally consistent. `tally-utility` has no remote.
**Broken:** Nothing — no application code exists yet; this is Layer 1–3 planning/decision-table documentation.
**Uncommitted changes:** verify with `git status` in both repos before assuming; do not carry a number forward from this document.

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

Non-obvious: hit policies aren't decorative. `rule-order` isn't row-matching at all — clusters 17 and 23 are staged procedures in table form. `collect` (rules co-fire) vs. `priority` (ranked; highest-ranked match decides) vs. `first-match` (ordered scan, stops on hit) vs. `unique` (mutually exclusive; an overlap is a defect) imply different test-case shapes. Session 3I used `priority` as a **constraint stack** for clusters 39 and 40 — a floor-and-override structure rather than an ordered scan — which is the clearest use of that policy in the corpus so far and worth reusing where a regulatory floor binds above a configurable rule. `[split-with-addenda]` workflows carry a partner-neutral spec plus a deferred **Addenda** section; `ami-amr-file-ingestion` is the shape precedent and Sessions 3H and 3I added two each.

## Resume Instructions

1. **Session 3J — Domain 10 (Programs & Assistance), clusters 43–45** (`budget-billing-eligibility-and-trueup` unique, `dpa-eligibility-and-breach` priority, `program-enrollment-eligibility` collect), plus workflows `budget-billing-enrollment`, `budget-billing-trueup`, `budget-billing-exit`, `dpa-creation`, `dpa-payment-progress`, `dpa-breach-handling`. **This session is v5.4-coupled** — the clusters carry forward notes against the locked Q-13 `customer_program_enrollments` + `program_types` design rather than the current `customers.disconnect_protection_type` column, which v5.4 drops. Known content: **D8-1** (breach is terminal, new enrollment required, with a tenant-configurable grace window — no cure state machine); **D8-3** (no conflict matrix; max one active installment/deferred-payment agreement per account, enforced as validation; holds compose freely); **D9-2** (medical hold + broken IA → uniform grace window); **DE-9 / action #36** (Texas medical = §7.45 physician statement, 5-working-day window after delinquency, time-bounded with re-cert cadence — explicitly **not** the PUCT electric Critical Care registry); **CI-064** additive composition; **action #10** (`agency_pledge` added to the program-type set).
2. **Read the schema directly.** Five sessions running, that's where every item has come from. The single highest-yield technique remains **testing a specific Appendix-A or schema-enforcement-status claim against `sql/tu.sql`** — it produced the sharpest finding in five of Session 3I's ten files and found three wrong claims. Apply it deliberately to A-11, whose locked v5.4 design is long and detailed and has never been checked against what is actually in the SQL today.
3. **Domain 10 substrate is mostly absent by design and that is the point.** `customers.disconnect_protection_type` (8-value enum, single-valued — the CI-064 limitation), `disconnect_protection_start/expiry/notes`, `service_locations.budget_billing`. `customer_program_enrollments` and `program_types` are **not in `sql/tu.sql`** — verify that before drafting, since the appendix describes them as locked design and the schema is where the truth is. Note also that Session 3I found `agency_pledge` payments have no restriction substrate on the payment record; Domain 10 lands the enrollment side of the same program, and the two halves should be briefed together.
4. **Consider drafting the 3I–3J consolidated brief after 3J** rather than briefing 3I alone — see "Not Yet Done."

## Warnings

- **Commit before ending a session.** An earlier session left 52 files of correct work uncommitted; the next session's first act was rescuing it.
- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`** (which has its own, more detailed CHANGELOG — both get an entry each session).
- **The open items are deliberate, not authoring mistakes.** Don't resolve them unilaterally.
- **Verify push state; don't carry a number forward.** A stale "42 unpushed commits" figure propagated across several handoffs. Use `git rev-list --left-right --count origin/main...HEAD` after a fetch.
- **Texas-only launch** remains the scope discipline. Sewer billing and government/wholesale classes are flagged likely-out-of-scope-for-v1 but not formally deferred, unlike Q-12's transport-balancing/submetering/multi-commodity.
- **The load-bearing absences now number five**, one per recent domain: `tax_jurisdictions` (A-8, Domain 5); the exception-queue substrate (A-20, Domain 7 — **known too narrow**, no canary registry or revenue-requirement baseline); the outbound communication log (A-16, Domain 8 — **known one field short**, no CI-135 match assertion) with A-17/A-18 alongside it; and now the payment-classification/effective-date column set (Domain 9 — **A-12 known too large, A-13 known incomplete**, plus CI-058's two columns and CI-057's NOC substrate having no appendix entry at all). Any schema-hardening session inherits all five *as amended by these sessions*, not as the appendix states them.
- **A closed question is not a safe question.** Session 3I's headline finding sits under D7-1, a ruling Kyle made and closed. Resolved decisions still need their substrate checked; "Kyle answered this" does not mean "this is implementable."
- **Appendix A's claims have now been materially wrong five times in three sessions**, in both directions (over- and under-stating gaps). Treat it as a hypothesis register to test against `sql/tu.sql`, not as a settled inventory, and expect any estimate derived from it to be wrong both ways.
