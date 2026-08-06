# Handoff: Work Unit 6 Session 3H (Domain 8 — Delivery & Communications)

**Generated**: 2026-08-06
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3H complete (Domains 1–8 of 13). Nineteen open items across the last five sessions await Kyle, now organized into **two open briefs**; none blocks Session 3I.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/canonical-invariants.md` — 135 invariants (CI-001–135) across 17 families, plus Appendix A's 21 schema-enforcement gaps. Q-4/Q-7/Q-9/Q-12 open by design.
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3); governs WU6
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: **72 files** across Sessions 3A–3H
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's earlier resolved decisions
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — historical source record, fully folded in
- `application/configurable-rules/wu6-sessions-3e-3f-review-brief.md` and `wu6-sessions-3g-3h-review-brief.md` — the fourth and fifth briefs, **both open, both awaiting Kyle**, independent of each other
- `application/wiki-ingestion-pending.md` — Sections A–P; every file change logged with a wiki-ingestion target
- `application/execution-kickoff.md` — the 12-work-unit sequence. It does **not** carry a per-session WU6 progress marker; session progress lives here and in `wiki-ingestion-pending.md` only.

## Completed (this session)

- [x] **Session 3H — Domain 8 (Delivery & Communications), clusters 36–38** (`gas-billing-memory 60a4557`, pushed): three decision tables — `delivery-method-routing` (#36, first-match), `communication-language-format` (#37, unique), `notice-and-alert-triggering` (#38, collect) — and four workflows: `invoice-pdf-generation-and-retention`, `email-delivery-with-fallback` [addenda], `print-vendor-handoff` [addenda], `consolidated-invoice-assembly`. Seven files.
- [x] **Corrected a Session 3G overstatement in place** — see "Correction carried" below.
- [x] **Compiled `wu6-sessions-3g-3h-review-brief.md`** (`c4a36cc`, pushed) — the fifth brief, spanning both sessions' 14 files. Part A holds four items; **Part D is new to the format** and carries two things that aren't rulings (a proposed fourth option closing the *previous* brief's Part A item 4, and a print-vendor procurement criterion whose deadline attaches to vendor selection). Opens with a methodological note rather than a question. Carries the Session 3G dispute correction in its narrowed form.
- [x] Logged in `wiki-ingestion-pending.md` Sections O and P + both CHANGELOGs. Pushed; `origin/main` level (0/0).

## Not Yet Done

- [ ] **Sessions 3I through 3M** — payments (39–42), programs (43–45), collections/disconnect/deposits (46–55), customer/account lifecycle (56–57), import/admin (58–60). Untouched. **Session 3I is next.**
- [ ] **Kyle answers both open briefs** — `wu6-sessions-3e-3f-review-brief.md` (four Part A items, awaiting him since earlier today) and `wu6-sessions-3g-3h-review-brief.md` (four more). **Two briefs are now outstanding simultaneously, which is a first.** They're independent — neither depends on the other's answers — but eight Part A items across two documents is a lot to hand someone at once, and it may be worth asking Kyle which he'd rather take first. My suggestion if asked: 3G–3H, because its item 2 ("Check #4") resolves cheaply and changes how expensive item 1 is, and because the `bill_messages` mutability finding is a live violation rather than a design question.
- [ ] **`tally-utility` has no git remote configured** — local-only, with nowhere to push, while holding the canonical schema and all session history. Worth deciding.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (2026-07-05): `Agent({prompt: "placeholder", name: "waiter"})` spawns a *real* agent that takes the literal text as its assignment and does unwanted work. **End the turn with a short text update and no tool call** — background-task notifications arrive on the next turn regardless.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Corrected Session 3G's dispute finding in place rather than leaving it | It claimed a bill dispute had "nowhere to live except `customers.billing_hold_reason`." `customer_interactions` carries `reason='high_bill_complaint'` with an `invoice_id` FK and a full status lifecycle — a real partial substrate I missed. The corrected ask is smaller and better-anchored, and Kyle would have been asked to fund a bigger build than the gap warrants. Marked as a dated correction in the file so the change is visible rather than silent. |
| Clusters 37 rows 4/6 **hold** rather than degrade to English | The one genuinely contestable design choice in the domain, and it is made rather than deferred. A silently-degraded notice looks delivered and is legally not-served; a held one has to be resolved by a person. Recorded with the counter-argument and a defensible split (hold regulated, degrade non-regulated *with the degradation recorded*) — which itself depends on A-16, and that dependency is the reason to prefer holding today. |
| Named A-17 as **smaller** than the appendix says, not just unmet | `bill_messages` already supplies the effective-date bracket, approval workflow, lifecycle, and targeting; Q-8's resolution removes the per-county variants the appendix still describes. Saying "three columns plus generalization" instead of "the table does not exist" changes what gets built and how it is priced. |
| Escalated the print-vendor match assertion as a **procurement criterion** | Schema work cannot make CI-135 implementable if the selected vendor has no per-piece assertion capability. That is a decision with a deadline attached to a vendor selection, not a ruling for Kyle, and it would have been lost inside an Open question. |
| Offered a **fourth option** on the 3F consolidated-ledger question instead of re-asking the three | The delivery side surfaces something the ledger framing alone does not: the customer pays against the parent, because that is the document with the invoice number. Children-post + parent-as-presentation-and-payment-construct keeps per-location arrears real for collections and gives payments one earmark target. Closing an open question beats accumulating another. |
| Fourth session running with no research agents | Every item again came from reading `sql/tu.sql` against the invariants and catalog. Two of this session's four came specifically from testing an appendix claim against the schema (A-17's "no table exists", A-16's outcome enum vs. CI-135) — the same move that produced Session 3G's central finding about CI-134. |

## Session 3H's four open items

1. **No E-SIGN consent substrate, and the schema defaults every customer into electronic delivery.** `customers.billing_delivery_method` is `NOT NULL DEFAULT 'email'`; a search for `consent` returns only `donation_opt_in`. E-SIGN §101(c) permits an electronic record to satisfy a writing requirement only on affirmative consent with a right-to-paper disclosure — so the default *is* the prohibited condition, and cluster 36's consent rows have nothing to evaluate. Needed shape is small and statute-defined: consent event, timestamp, disclosure version, scope (bills/notices/both), channel.
2. **"Check #4 fix #4" has no source document, and two adjacent columns disagree.** `preferred_contact_method` defaults to `'mail'`; `billing_delivery_method`, three lines below, to `'email'`. **"Check #4" appears nowhere else in the KB** — only Checks #1 and #2 are recorded, in `de-review-answers.md`. Same shape as 3F's DE-3. Also: `preferred_contact_method` has no CHECK constraint, so it cannot be safely routed on regardless.
3. **A-16's stated shape is one field short; A-17's is both smaller and larger than recorded.** A-16's outcome enum can't express CI-135's per-bill content-to-envelope match assertion — and CI-135 needs three things, only one of which A-16 produces (assertion field, pre-mailing quarantine state, breach-event classification with the statutory clock). A-17 overstates the gap (`bill_messages` supplies most of the shape; three columns missing) and Q-8 shrinks it further (no per-county variants). **And `bill_messages` rows are mutable — an approved, active `message_body` is editable in place, making every bill already rendered with the prior text unreproducible. A live CI-094 violation today, not a future gap.**
4. **Which column gates a collections step.** `sent_at` (handed to a provider) vs. `delivery_confirmed_at` (provider confirmed). The schema separates them correctly; nothing says which a consumer must read, and `sent_at` is more discoverable by name. One canonical sentence prevents the bounce-treated-as-delivered failure across Domains 8, 9, and 11. Cheapest item in the session.

**Also surfaced, smaller:** `alerts` is entirely operator-facing (no `customer_id`) while carrying `disconnect_warning` / `account_past_due` / `credit_approaching_escheat` and external `email`/`sms`/`push` channels — the only outbound-message-shaped table can't address a customer while looking like it can. `invoices.delivery_method` permits `text_message`, unelectable by any customer and unroutable by any contact field. `customers.email` is nullable while `billing_delivery_method` is NOT NULL DEFAULT `email`. Delivery tracking lives entirely on `invoices` — complete for bills, **absent for disconnect and rate-change notices**. No terminal undeliverable state (fourth consumer of that gap).

**Procurement action, not a ruling:** a print vendor without per-piece OMR/IMb match-assertion capability makes CI-135 unimplementable regardless of schema work. Needs to reach whoever runs vendor selection.

## Correction carried

Session 3G's `high-bill-dispute-intake-and-resolution` Open question 1 claimed a bill dispute "has nowhere to live except `customers.billing_hold_reason`." **Too strong; amended in place with a dated note.** `customer_interactions` carries `reason='high_bill_complaint'`, an `invoice_id` FK, `channel`, inbound/outbound types, a lifecycle through `escalated`, `resolution`/`resolved_at`, `handled_by`, `follow_up_*`. Missing is what makes a dispute regulatory rather than conversational: disputed **amount**, linkage to `pending_dispute` protection, a resolution basis distinct from free text, and any distinction between disputing a bill and asking about one. **Read Session 3G's item 4 in its corrected form** — and when the brief is compiled, brief the corrected version.

## Current State

**Working:** `gas-billing-memory` main, level with `origin/main` (pushed 2026-08-06). `tally-utility` has no remote. WU5 output (15 axes docs) and WU6 Sessions 3A–3H output (72 decision-table/workflow files) all committed and internally consistent.
**Broken:** Nothing — no application code exists yet; this is Layer 1–3 planning/decision-table documentation.
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

Non-obvious: hit policies aren't decorative. `rule-order` isn't row-matching at all — clusters 17 and 23 are staged procedures in table form. `collect` (rules co-fire) vs. `priority` (first-in-order wins) vs. `first-match` (ordered, stops on hit) vs. `unique` (mutually exclusive; an overlap is a defect) imply different test-case shapes. `[split-with-addenda]` workflows carry a partner-neutral spec plus a deferred **Addenda** section — `ami-amr-file-ingestion` is the shape precedent, and 3H added two more.

## Resume Instructions

1. **Session 3I — Domain 9 (Payments), clusters 39–42** (`payment-posting-allocation`, `overpayment-and-credit-disposition`, `nsf-and-ach-return-handling`, `autopay-eligibility-and-failure`), plus `lockbox-remittance-ingestion` [addenda], `payment-gateway-webhook-handling` [addenda], `ach-return-handling`, `autopay-enrollment-and-management`, `unapplied-cash-resolution`, `refund-processing`. Known content: **DE-2** (allocation configurable, not mandated); **Q-5 resolved** 2026-07-10 (D7-1, tiered payment-class allocation) — the UCC §3-310 earmark invariant; **action #21** (Texas timeliness keys off postmark for mailed payments and sent date for electronic ones, with the explicit design implication that payment records need a **customer-initiation date distinct from the posting date** — check `payments` for whether one exists).
2. **Read the schema directly.** Four sessions running, that's where every item has come from. Two of 3H's four came from testing an *appendix claim* against the schema — A-17's "no table exists" and A-16's outcome enum vs. CI-135. That move (check what Appendix A asserts against what `sql/tu.sql` actually has) is now the highest-yield single technique in this work and should be applied to Domain 9's gaps deliberately.
3. **Domain 9 substrate already located:** `payments` (with `channel` 10-value enum, `nsf_original_payment_id`), `customer_credits` (`origin_type` 10-value enum incl. `dispute_resolution`, `overpayment`, `escheatment` path), `auto_pay_settings`, `account_ledger`. The catalog's `payment-policy-gaps` entry carries Kyle's 2026-06-12 postmark ruling verbatim.

## Warnings

- **Commit before ending a session.** An earlier session left 52 files of correct work uncommitted; the next session's first act was rescuing it.
- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`** (which has its own, more detailed CHANGELOG — both get an entry each session).
- **The open items are deliberate, not authoring mistakes.** Don't resolve them unilaterally.
- **Verify push state; don't carry a number forward.** A stale "42 unpushed commits" figure propagated across several handoffs. Use `git rev-list --left-right --count origin/main...HEAD` after a fetch.
- **Texas-only launch** remains the scope discipline. Sewer billing and government/wholesale classes are flagged likely-out-of-scope-for-v1 but not formally deferred, unlike Q-12's transport-balancing/submetering/multi-commodity.
- **The load-bearing absences now number four, one per recent domain:** `tax_jurisdictions` (A-8, Domain 5), the exception-queue substrate (A-20, Domain 7 — **known too narrow**, no canary registry or revenue-requirement baseline), the outbound communication log (A-16, Domain 8 — **known one field short**, no CI-135 match assertion), and A-17/A-18 alongside it. Any schema-hardening session inherits all four *as amended by these sessions*, not as the appendix states them.
- **Appendix A's claims have now been wrong twice in two sessions** (CI-134's "canary values are configured"; A-17's "no notice-template table exists"). Treat the appendix as a starting hypothesis to test against `sql/tu.sql`, not as a settled inventory.
