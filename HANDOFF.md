# Handoff: Work Unit 6 Session 3K-deposits (Domain 11 pt 2 — Write-Off, Deposits & Unclaimed Property)

**Generated**: 2026-08-07
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3K complete (**Domains 1–11 done**, Domains 12–13 remaining). Thirty-six open items across the last nine sessions await Kyle: **two compiled briefs** (one amended) plus **Sessions 3I, 3J, 3K-collections and 3K-deposits' seventeen items, not yet briefed**. Nothing blocks 3L.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/canonical-invariants.md` — 135 invariants (CI-001–135) across 17 families, plus Appendix A's 21 schema-enforcement gaps. Q-4/Q-7/Q-9/Q-12 open by design. **CI-077's enforcement status is now known to be wrong — see Warnings.**
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3)
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: **112 files**
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's resolved decisions
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — **Q-6, the §366 research, D8-1/D8-2/D8-3, D9-1/D9-2, and Family 16's day-30/31 sequencing flag all live here**
- `application/configurable-rules/wu6-sessions-3e-3f-review-brief.md` and `wu6-sessions-3g-3h-review-brief.md` — both open, both awaiting Kyle. **The 3G–3H brief was amended 2026-08-07** with a correction; if he has read it, he needs to know.
- `application/wiki-ingestion-pending.md` — Sections A–T
- `application/execution-kickoff.md` — the 12-work-unit sequence; no per-session WU6 marker

## Completed (this session)

- [x] **Session 3K-deposits — Domain 11 part 2, clusters 51–55** — five decision tables (`write-off-eligibility` #51 priority, `customer-credit-scoring` #52 unique/**pending**, `deposit-eligibility-and-waiver` #53 priority/**regulated**, `deposit-refund-and-interest` #54 unique, `deposit-alternatives-and-triggers` #55 first-match) and five workflows (`agency-placement`, `write-off-authorization`, `escheatment-processing`, `deposit-refund-processing`, `deposit-interest-accrual-cycle`). Ten files. **Domain 11 is complete.**
- [x] Logged in `wiki-ingestion-pending.md` Section T + both CHANGELOGs.

## Not Yet Done

- [ ] **Session 3L** — Domain 12 customer/account lifecycle: `billing-responsibility-resolution` (#56, first-match) and `service-transition-charges` (#57, unique). The inventory notes these may fold into the workflows that consume them if the row counts do not warrant standalone tables — **decide that first, it changes the file count.** **This is next.**
- [ ] **Session 3M** — Domain 13 import/admin (clusters 58–60).
- [ ] **Three review briefs are outstanding across four sessions (3I, 3J, 3K-collections, 3K-deposits) — seventeen items.** The shape proposed two handoffs ago still holds and is now actionable: a **3I–3J brief** (payments + programs; they pair on the agency-pledge and installment-tracking threads) and a **single Domain 11 brief covering both 3K sessions**. Domain 11's items divide cleanly — physical-harm consequences in part 1, unprompted-obligation failures in part 2 — and the two halves argue *better together* than either does inside a twelve-item omnibus, because the inversion between them is itself the argument.
- [ ] **Kyle answers the two open briefs**, with a note that 3G–3H has been amended.
- [ ] **`tally-utility` has no git remote** — local-only, six handoffs running.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (2026-07-05): spawns a *real* agent that takes the literal text as its assignment. End the turn with a short text update and no tool call.
- **Asserting a column has no CHECK constraint without grepping `<table>_<column>_check`** (2026-08-06, corrected 2026-08-07). The constraint list sits ~50 lines below the column definition in `sql/tu.sql`.
- **Editing a section's closing "Next:" line as the anchor for appending a new section** (2026-08-07). The Edit replaced text serving as the prior section's closer, orphaning it as a stray heading at EOF. Anchor appends on a stable heading or the separator, and re-read the seam afterwards. *(Section T was appended by anchoring on the closing sentence and re-emitting it ahead of the new content, then verifying the seam — that variant is safe.)*
- **Trusting a canonical invariant's `Schema enforcement status` field** (2026-08-07). CI-077 says the `deposits` table exists. It does not. Grep `^CREATE TABLE public.<name>` before relying on any enforcement claim, exactly as with Appendix A.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Framed the session as the inversion of 3K-collections** rather than as ten more findings | Part 1's obligations constrain an action the LDC wants to take; part 2's require actions it has no commercial reason to take, unprompted. That difference determines the fail direction, and stating it once (**the unevaluable case resolves against the party that controls the data**) unifies two conventions that would otherwise look contradictory across one domain. |
| Made cluster 52's rule 2 **fail open**, explicitly inverting Domain 11 part 1 | A fail-closed habit carried across the seam would block deposit *waivers*, harming exactly the customers §7.45 protects. Written as a rule with the reasoning attached so an implementer carrying part 1's convention notices the change. |
| **Led with CI-077's contradiction rather than with the missing `deposits` table** | The absent table is A-21, already known and well specified. That four sibling entries call it a gap and one calls it enforced is new, and it is the finding with a method attached — the enforcement-status field is a hypothesis register, which nobody had established. |
| Recommended `credit_bureau_reporting` be **explicitly out of scope**, not merely unbuilt | The catalog lists it as one boolean beside three numeric thresholds. Enabling it makes the tenant an FCRA furnisher with duties that need substrate the platform lacks, and furnishing is durable for seven years in a way the write-off is not. A boolean that turns on an unbuilt compliance regime should not ship undecided. |
| Argued cluster 55's residential-alternatives row should be **decided as scope**, not left blank | "Cash only for residential at launch" and "we never got to guarantors" look identical in the product and are very different when a customer asks why their co-signer was refused. |
| Escalated the grain pattern from **modelling awkwardness to control failure** | Three prior sessions found it as a reporting problem. The write-off instance is an authorization bypass that every individual record passes review on, which is the evidence that makes it brief-worthy rather than list-worthy. |
| Recommended **consolidating** the vendor criteria rather than appending a seventh | Four sessions have each surfaced one or two. Seven scattered across session findings will not reach procurement; one list might. |

## Session 3K-deposits' five open items

1. **CI-077 asserts a `deposits` table that does not exist, and it is the entry governing the regulated 1/6 cap.** Its `Schema enforcement status` reads `partially-structurally-enforced` on the strength of "`deposits` table exists; the credit-evaluation rule and the deposit-interest-accrual mechanism live in workflow code," and its Scope line names `deposits` as a table. `sql/tu.sql` defines fifty-nine tables and none is that one. The siblings are correct — CI-125, CI-129, CI-130, CI-131 all read `unenforced-gap` and cite A-21, and A-21 specifies the missing table well. **So the invariant corpus contradicts itself about whether the deposit substrate exists, and the single entry claiming it does governs the highest-consequence computation in the sub-family.** The practical hazard is specific: `partially-structurally-enforced` is the status a hardening pass reads as "no schema work needed here." This is a different failure from the six prior Appendix A errors — that was the appendix, this is a canonical entry's enforcement status — so **that field joins the appendix as a hypothesis register.**
2. **Deposit interest is one mutable column, in a schema with full bi-temporal rate machinery.** `interest` occurs exactly once across the whole schema: `customers.deposit_interest_earned numeric(12,2) DEFAULT 0`. No rate, no rate history, no accrual event, no period, no as-of date, no ledger transaction type. Three consequences: a deposit held across a PUCT rate change **cannot be computed correctly at all** (CI-130 requires the rate in force during each period; there is one number and no periods); the total is **mutable**, so a recomputation destroys the record of what was previously owed, while the account beside it is append-only; and "what interest was owed as of last March" — the question a complaint asks — has no answer. Kyle's 2026-06-12 effective-dated-rate-table ruling is **settled and unbuilt**; the accrual sub-ledger is the undesigned half. On top sits the **day-30/day-31 cliff**: §7.45 owes zero at day 30 and thirty-one days' interest at day 31, and the natural paraphrase ("no interest for the first 30 days") under-pays every long-held deposit uniformly across the entire book — the profile of a restitution order rather than a complaint. **The argument for Kyle is proportion**: the effort spent making a gas commodity rate reproducible against the effort spent making a statutory interest obligation reproducible is the corpus's clearest illustration of regulatory obligations modelled with less rigour than commercial ones.
3. **The deposit-refund monitoring is pointed at the wrong event.** CI-131's obligation is *automatic and mandatory* — the LDC must notice, unprompted, that twelve clean bills have elapsed. `credit_aging_statistics.deposit_refund_overdue` fires on `origin_type = 'deposit_refund' AND remaining_amount > 0 AND CURRENT_DATE - issued_date > 60`, with a matching anomaly type and a partial index behind it. That detects **a refund credit that was issued and has sat unpaid for sixty days** — a real failure, and the one *after* the one that matters. A deposit whose trigger never fired produces no credit, so it never enters the view, so no anomaly is ever raised, and the account looks healthy forever. **The monitoring is structurally blind to the failure with the statute behind it and vigilant about its sequel.** Not an omission — an inversion, which is why it is its own item: someone built deposit-refund monitoring and anchored it one step downstream. The corrected version needs the twelve-bill counter, which cluster 52 shows is not computable, so this item's fix runs through a cluster the inventory marks `pending`.
4. **The grain pattern has crossed from awkward into unsafe.** Write-off state is per-invoice (`invoices.write_off_*`), `dunning_events.invoice_id` is **NOT NULL**, and `customers.status = 'collections'` carries no amount or date — so there is nowhere to record "this $4,000 decision, approved by this person." A write-off decision is a judgment that a *relationship* has ended without payment, and the authorization band keys on the total. Represented per-invoice, **an actor with a $1,000 limit can clear a $4,000 relationship in eight individually-compliant steps, and every record passes review.** Sessions 3G, 3H and 3K-collections found this pattern as a reporting problem in three domains; this is the instance with a control consequence, and `agency-placement` supplies a sixth appearance where it defeats the FDCPA question *which agency held this balance on this date*.
5. **Q-6's affirmative half has no substrate, and it is the mandatory half.** §7.45(5)(C) makes family violence a **mandatory deposit waiver** — Kyle's ruling relocated the protection out of the disconnect-bypass set, correctly, and there is nothing at the destination. `family_violence` appears nowhere in `sql/tu.sql`; there is no deposit-waiver enum because there is no deposit record. Wherever it lands it needs a certification reference and date (not a boolean), **field-level sensitivity** (a family-violence flag visible to every CSR is a safety question, and `custom_field_definitions.is_sensitive` shows the schema has the vocabulary), and a recorded determination rather than a re-derivation. The §7.45 **good-payment-history exception** — the other mandatory no-deposit rule — is uncomputable for three separate reasons (mutable `dunning_stage`, `dunning_events` logging only engine actions, and no `disconnect_reason`), and **every one of those failures runs toward charging a deposit that is not owed**, on the population least able to absorb it.

**Also surfaced, smaller:** `account_ledger.reference_type` has `invoice_void` and **no `write_off`**, so a recovery cannot point at its loss (CI-076's phrasing implies a write-off event exists; none does); `invoices` enum-codes void reasons and free-texts write-off reasons on the same table; `payments.payment_method = 'write_off'` lets a write-off enter the payment history that two regulated rules read; `payments.deposit_status` is nullable and unconstrained against `is_deposit`, and its 4-value vocabulary lacks `refund_pending` while `customers.deposit_status`'s 6-value one has it; deposits have **four write paths** and A-21's fix adds a fifth unless the migration is specified with it; deposit **basis** is unrecorded though §7.45, §366 and trigger deposits refund on three different rules; the 1/6 cap's *estimated annual billing* input is undefined for the new applicants it governs; `credit_aging_statistics` hardcodes 1095/1005/365/60/250 **inside a materialized view** (a migration, not a config change, not per-tenant, not effective-dated); `escheatment_events.customer_credit_id` NOT NULL bounds escheatable property to credit rows, excluding unapplied payment balances and uncashed cheques; there is no report or remittance entity against Texas's June-30/November-1 cycle; non-cash instruments have no expiry watch though the pattern ships twice (`tax_exemption_expiry_date`, `disconnect_protection_expiry`); §366's six assurance forms and the catalog's four-instrument list were specified independently; and there is **no forgiveness concept distinct from write-off** (different act, 1099-C consequences).

**Two procurement criteria, bringing the corpus to seven — and the recommendation is now to consolidate rather than extend.** A **collection-agency agreement** carrying contractual recall-acknowledgement, dispute intake, and bankruptcy-cease terms (the same requirement 3K-collections raised for field-service dispatch, closable here as a contract term rather than an API); and, contingently, **credit-bureau furnishing** if `credit_bureau_reporting` is ever enabled — recommended out of scope for launch. **Seven criteria across four sessions is enough: the corpus should carry one consolidated vendor-criteria list, and it needs to reach whoever runs procurement before contracts are signed.**

## Current State

**Working:** `gas-billing-memory` main. WU5 output (15 axes docs) and WU6 Sessions 3A–3K output (112 files) internally consistent. `tally-utility` has no remote.
**Broken:** Nothing — no application code exists yet; this is Layer 1–3 planning/decision-table documentation.
**Uncommitted changes:** verify with `git status` in both repos; do not carry a number forward from this document.

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

Non-obvious: hit policies aren't decorative. 3I used `priority` as a **constraint stack**; 3J's cluster 45 is where **the hit policy is itself the finding**; 3K-collections' cluster 46 is `priority` **rank-but-do-not-stop**. This session adds a fourth variant that is not about the policy name but about the **default row**: cluster 51's no-match row **blocks**, inverting every other table in the corpus, because a write-off requires an affirmative basis and "nothing matched" is not one. `[split-with-addenda]` workflows carry a partner-neutral spec plus a deferred Addenda section (two each in 3H and 3I).

## Resume Instructions

1. **Session 3L — Domain 12, clusters 56–57.** `billing-responsibility-resolution` (#56, first-match): bill owner vs. occupant, revert-to-owner on move-out, reading `customers.landlord_responsible` / `is_property_owner` / `landlord_customer_id`, gap-list `revert-to-owner-agreement`, Check #4 fix #7 (tenant terminology). `service-transition-charges` (#57, unique): MIMO charges, `tenants.default_partial_period_policy = 'charge_both'` per-customer-month, `tenants.settings.service_transition` (five documented keys — the only fully-documented settings sub-object relevant here), Check #4 fix #5.
2. **Decide the file count before writing.** The inventory says Domain 12 is "folded into the workflows that consume them; Session 3L **if rows warrant**." Both clusters are small. Check whether they carry enough rows to stand alone or should be sections inside the MIMO workflows — this is the first session where the inventory leaves the shape open, and getting it wrong costs a rewrite.
3. **Substrate to verify first:** `customers.landlord_customer_id` is the schema's **only customer-to-customer link** (cluster 55 established this), and it is a billing-responsibility link with no `revert_to_owner_on_moveout` flag. Check whether `is_property_owner` (DEFAULT **true**, NOT NULL) and `landlord_responsible` (DEFAULT false, NOT NULL) can contradict each other, and what the default-true means for imported data — a customer imported without the field asserts property ownership.
4. **Carry-ins from this session:** cluster 53's grain question (the 1/6 cap is per-premise, the credit judgment is per-customer) is Domain 12's question arriving early; the `service_transition` settings keys are the one place a well-documented settings sub-object exists, worth using as the positive example when arguing elsewhere that settings keys need documentation.
5. **Keep testing claims — and now test the corpus against itself.** This session's headline came from **cross-entry consistency-testing**: reading CI-077 against CI-125/129/130/131 and noticing that four entries call something a gap and one calls it enforced. Prior sessions tested the appendix against the schema. Both techniques are live, and both the appendix (**wrong six times, silent once**) and the `Schema enforcement status` field (**wrong at least once**) are hypothesis registers.

## Warnings

- **Commit before ending a session.** An earlier session left 52 files of correct work uncommitted.
- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`** (both get a CHANGELOG entry each session).
- **The open items are deliberate, not authoring mistakes.** Don't resolve them unilaterally.
- **Verify push state; don't carry a number forward.** Use `git rev-list --left-right --count origin/main...HEAD` after a fetch.
- **Texas-only launch** remains the scope discipline.
- **The load-bearing absences now number eight**, one per recent domain: `tax_jurisdictions` (A-8, Domain 5); the exception-queue substrate (A-20, Domain 7); the outbound communication log (A-16, Domain 8) with A-17/A-18; the payment-classification and effective-date column set (Domain 9); the program-enrollment substrate (Domain 10 — A-11's design sound but incomplete); the collections-engine substrate (Domain 11 pt 1 — A-14 silent on determination expiry, the holiday calendar, and the weather feed); and now **the deposit substrate** (Domain 11 pt 2 — **A-21 specifies the missing `deposits` table well and is silent on the four existing deposit representations it would collide with**, so implementing A-21 as written adds a fifth rather than replacing four).
- **A closed question is not a safe question** (3I's D7-1). **A locked design is not a landed design** (3J's v5.4). **An absent claim is not an absent gap** (3K-collections' item 3). **And a present claim is not a true claim** (3K-deposits' item 1) — CI-077 states affirmatively that a table exists, and it does not.
- **Appendix A has been materially wrong six times in five sessions**, in both directions, and silent on at least one structural gap — **and the `Schema enforcement status` field on canonical entries is now known to be wrong at least once too.** This corpus's own prior output has been wrong once, in a brief that reached Kyle. Treat all three as hypothesis registers; any schema-hardening estimate derived from Appendix A **or from an enforcement status** will be wrong in both directions until each entry is re-checked against `sql/tu.sql`.
