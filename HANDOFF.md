# Handoff: Work Unit 6 Session 3K-collections (Domain 11 pt 1 — Collections & Disconnect)

**Generated**: 2026-08-07
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3K-collections complete (Domains 1–10, plus Domain 11 part 1 of 2). Thirty-one open items across the last eight sessions await Kyle: **two compiled briefs** (one amended) plus **Sessions 3I, 3J and 3K-collections' twelve items, not yet briefed**. Nothing blocks 3K-deposits.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/canonical-invariants.md` — 135 invariants (CI-001–135) across 17 families, plus Appendix A's 21 schema-enforcement gaps. Q-4/Q-7/Q-9/Q-12 open by design.
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3)
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: **102 files**
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's resolved decisions
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — **D8-1/D8-2/D8-3 and D9-1/D9-2 govern Domain 11; the EWE and §366 research entries are there too**
- `application/configurable-rules/wu6-sessions-3e-3f-review-brief.md` and `wu6-sessions-3g-3h-review-brief.md` — both open, both awaiting Kyle. **The 3G–3H brief was amended 2026-08-07** with a correction; if he has read it, he needs to know.
- `application/wiki-ingestion-pending.md` — Sections A–S
- `application/execution-kickoff.md` — the 12-work-unit sequence; no per-session WU6 marker

## Completed (this session)

- [x] **Session 3K-collections — Domain 11 part 1, clusters 46–50** — five decision tables (`collections-bypass-evaluation` #46 priority, `dunning-step-routing` #47 first-match, `disconnect-eligibility` #48 priority, `cold-weather-moratorium` #49 unique, `reconnect-eligibility-and-fees` #50 first-match) and six workflows (`bypass-conditions-evaluation`, `dunning-event-action`, `disconnect-order-creation-and-dispatch`, `disconnect-field-execution`, `reconnection-request-and-gas-relight`, `bankruptcy-stay-and-adequate-assurance`). Eleven files.
- [x] **Took the inventory's split, with one regrouping** — `escheatment-processing` moved into 3K-deposits. Rationale in "Key Decisions."
- [x] Logged in `wiki-ingestion-pending.md` Section S + both CHANGELOGs.

## Not Yet Done

- [ ] **Session 3K-deposits** — clusters 51–55 plus `agency-placement`, `write-off-authorization`, `escheatment-processing`, `deposit-refund-processing`, `deposit-interest-accrual-cycle`. Ten files. **This is next.**
- [ ] **Sessions 3L–3M** — customer/account lifecycle (56–57), import/admin (58–60).
- [ ] **Sessions 3I, 3J and 3K-collections have no review brief — twelve items across three sessions.** The two-session cadence has now been exceeded, and the natural move has changed shape: rather than one enormous brief, consider a **3I–3J brief** (payments + programs; they pair on the agency-pledge and installment-tracking threads) and a **separate 3K brief after 3K-deposits** covering all of Domain 11. Domain 11's items are the ones with physical-harm consequences and deserve their own document rather than being item 9 of twelve.
- [ ] **Kyle answers the two open briefs**, with a note that 3G–3H has been amended.
- [ ] **`tally-utility` has no git remote** — local-only, five handoffs running.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (2026-07-05): spawns a *real* agent that takes the literal text as its assignment. End the turn with a short text update and no tool call.
- **Asserting a column has no CHECK constraint without grepping `<table>_<column>_check`** (2026-08-06, corrected 2026-08-07). The constraint list sits ~50 lines below the column definition in `sql/tu.sql`.
- **Editing a section's closing "Next:" line as the anchor for appending a new section** (2026-08-07). The Edit replaced text that was serving as the prior section's closer, orphaning it as a stray heading at EOF. Anchor appends on a stable heading or the separator, and re-read the seam afterwards.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Split Domain 11 at "the service side" vs. "money at end of life"** rather than at the cluster numbering | Ten clusters would have been more than double any prior session. The chosen seam is coherent: 46–50 are the pipeline that ends in a physical act at a premise, and 51–55 are what happens to a receivable that will not be collected. It also puts every physical-harm item in one document. |
| **Moved `escheatment-processing` into 3K-deposits** | The inventory lists it under collections. Session 3I established that its central problem — per-property-type dormancy, with `credit_aging_statistics` hardcoding 1095 days — is fundamentally about deposits versus general credits. It belongs with the deposit refund and interest work. |
| Made cluster 46's `priority` policy **rank-but-do-not-stop** | An ordinary priority scan stops at the first hit. CI-064's additive composition requires knowing *every* active condition, because lifting one must not lift the others — cluster 44's DPA breach handling depends on exactly that. Ranking survives so a bar can be attributed to its strongest basis in a dispute. |
| Wrote cluster 48 to be evaluated **at execution as well as issuance**, with rank 0 asserting it | The gap between authorization and action is where wrongful disconnections actually happen, and nothing in the schema bounds it. Putting the discipline in the table as a rank-0 bar makes it testable rather than advisory. |
| Led with the **aggregation** rather than with any individual gap | Six of cluster 48's eleven bars are unevaluable, and every one of those gaps was already reported in an earlier session as its own item. Re-listing them would have added nothing; showing that they jointly leave the last gate before a disconnection able to check almost nothing is a different and much stronger claim. |
| Framed the relight-verification gap with a **scoped alternative** | `service_orders`' own comment says it is "NOT a field service system." Rather than proposing a full appliance checklist, the file offers the smaller option — store the technician's attestation and its reference, leave the checklist to the tenant's field software — so the choice is deliberate instead of defaulting to no record at all. |

## Session 3K-collections' four open items

1. **There is no holiday calendar, so both §7.45 working-day clocks are uncomputable — and a settings key advertises the capability.** Texas pins two windows: disconnect-eligible only after **5 working days** past delinquency, and notice at least **5 working days** before the stated disconnection date. The schema has no holiday table, no business-day function, and no calendar reference; the concept's only appearance anywhere is `mail_batch_skip_holidays` in the `tenants.settings` COMMENT, documented as rolling batches to the next business day — **a promise with no data behind it**, which reads as capability. The build is small (a holiday reference table plus `working_days_between()`, in a schema already shipping `get_effective_rate()`, `should_charge_tax()`, `compute_ledger_running_balance()`). The consequence of skipping it is not a missing feature but a **systematically early pipeline**: five calendar days across Thanksgiving or Christmas is three working days, so accounts become disconnect-eligible two working days before the statute permits, silently and always in the same direction. Domain 10's §7.45 medical-certificate window is already a second consumer — flagged there as a missing field when it is really this missing calendar.
2. **The EWE moratorium is self-executing and the platform has no way to learn it fired.** Kyle's research: previous day's high ≤32°F (32.0 qualifies) *and* forecast ≤32°F next 24h, per nearest NWS station for the customer's **county**, **no declaration required**, cold-only. The schema has no weather feed, no station reference, no county-to-station mapping, no daily temperature, no forecast, and **no record that an EWE period occurred** — so the platform also cannot afterwards demonstrate it correctly suppressed disconnects during one. The only weather data is `wna_zones`/`wna_monthly_adjustments`, and all four of its properties are wrong for this consumer: **monthly** HDD (needs daily + forecast), **WNA-zone**-keyed (needs county), **winter-only** (`active_months` Nov–Apr), and present **only for tenants running WNA**. `service_locations.county` is nullable while every sibling geographic column is NOT NULL, with no county-by-ZIP reference to backfill it. §7.460 carries a 2023 civil-penalty table, and "we didn't know" is not available against a self-executing rule. **Appendix A-5's missing weather-station FK is the same build.**
3. **Nothing makes an eligibility determination expire, and the interval between authorization and execution is unguarded.** `service_orders` has twenty-nine columns and none references the authorization that created the order — no determination id, no evaluated-at, no validity window, and no `disconnect_reason` at all. So a technician working a Thursday queue executes Monday's decision, and every condition that could have changed in between (a pledge posting, a freeze beginning, a stay being filed, a payment landing) is invisible at the point of action. **This is the most consequential structural gap in Domain 11 and it is not in Appendix A.** Two halves, and the second matters more: a determination record the order references, and a **mandatory re-evaluation at execution the field workflow cannot skip** — a stamped-but-unchecked determination is still one someone relies on past its usefulness.
4. **D9-1 cannot be implemented.** Kyle's ruling — no-photo-evidence disconnect sites require supervisor-role approval recorded as an event with a reason code, "process control plus audit trail, no new mechanism" — is right about the concept and optimistic about the substrate. Four things are missing: `meter_photos.photo_type` has ten values with **no `disconnect` and no `reconnect`**; `meter_photos` has **no `service_order_id`**, so evidence cannot be tied to the order it evidences; `service_orders` has **no approval columns** (though `adhoc_charges` carries `requires_approval`/`approved_by`/`approved_at` one table over) and **no event log at all** — the only major lifecycle table without one, against `invoice_events`, `dunning_events`, and `escheatment_events`; and the approval **cannot be role-checked** because `rbac-model` is open and `service_orders.assigned_to` is free text rather than a FK to `users`. Two enum values and an FK are trivial; the approval record follows an established pattern; the role model is the real dependency.

**The aggregation point, which is this session's actual argument:** cluster 48 is the last gate before a household loses heat, and **six of its eleven bars are unevaluable** for want of substrate documented in earlier sessions — notice delivery tracking for non-invoices (3H), working-day arithmetic (this session), the elderly determination, the disputed-amount concept (A-15, 3G), and cluster 46's own six-of-eight unevaluable conditions. What remains evaluable is a check that the platform's own pipeline advanced. Presented individually across five sessions these read as feature deferrals; presented together they describe a disconnect pipeline that cannot verify the law permits what it is about to do. **This aggregation is what belongs in the brief, not the individual gaps Kyle has already seen.**

**Also surfaced, smaller:** no fail-closed convention anywhere (one canonical sentence — *an unevaluable bypass condition blocks the action, and the inability to evaluate is itself recorded* — covers ~12 rows across three clusters); `dunning_events` cannot record restraint (no bypass-applied, step-held, order-created, or notice-returned event, so a correctly-suppressed disconnect and a job that never ran produce identical records); the **per-invoice `dunning_stage` versus per-premise disconnect** grain question, third appearance of the pattern and now stateable as a schema-wide property — *this schema attaches state to the document while the regulated act operates on the premise*; no wrongful-disconnect flag, so the LDC cannot count its own wrongful disconnections; no `disconnect_reason`, though five reasons reconnect on different rules; no reconnection SLA target or visit-outcome value (and the SLA is genuinely **two clocks** because gas needs a customer present); no appliance or relight substrate; no detection of consumption on a disconnected premise (the `anomalies` vocabulary already has `tamper_detected`, `unbilled_usage`, `unbilled_service` — the rule is what is missing); `service_orders` lacking a `blocked` status and structured blocking reason; no constraint preventing two open disconnect orders on one premise; no §366 timer (usefully in **calendar** days, so not blocked on the holiday calendar); no petition-date ledger partition; D8-2's expiry-type enum absent while `compliance_statistics` reports an event-terminated stay as `permanent`; and no idempotency key on `dunning_events`.

**Three procurement criteria this session, bringing the corpus to five.** A **weather-feed integration** (without it the EWE moratorium is unimplementable regardless of schema work); **acknowledged cancellation in the field-service integration** (without it CI-082's absolute recall of in-flight activity is unachievable); and a **bankruptcy-scrub service** (the standard mitigation for the knowledge-date gap). With 3H's print-vendor match assertion and 3I's lockbox postmark tier, the pattern is worth stating to Kyle directly: **this platform's regulatory obligations repeatedly terminate at a vendor capability, so vendor selection is a compliance activity rather than a purchasing one, and the criteria need to reach whoever runs it before contracts are signed.**

## Current State

**Working:** `gas-billing-memory` main. WU5 output (15 axes docs) and WU6 Sessions 3A–3K-collections output (102 files) internally consistent. `tally-utility` has no remote.
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

Non-obvious: hit policies aren't decorative. Session 3I used `priority` as a **constraint stack** (a regulatory floor above a configurable rule). Session 3J's cluster 45 is where **the hit policy is itself the finding** (`collect` required by CI-064; the single-valued column forces `unique`, which is a violation). Session 3K adds a third variant: cluster 46 is `priority` **rank-but-do-not-stop** — ranking attributes a bar to its strongest basis while evaluation continues, because CI-064 needs every active condition known. `[split-with-addenda]` workflows carry a partner-neutral spec plus a deferred Addenda section (two each in 3H and 3I).

## Resume Instructions

1. **Session 3K-deposits — Domain 11 part 2, clusters 51–55**: `write-off-eligibility` (51, priority), `customer-credit-scoring` (52, unique — **starter cluster, no schema yet, marked `pending`**), `deposit-eligibility-and-waiver` (53, priority, **regulated**), `deposit-refund-and-interest` (54, unique), `deposit-alternatives-and-triggers` (55, first-match). Workflows: `agency-placement`, `write-off-authorization` (CFO), `escheatment-processing` (CFO), `deposit-refund-processing`, `deposit-interest-accrual-cycle`. Ten files.
2. **Known content for 3K-deposits:** **Q-6's affirmative half** — family violence is a **mandatory deposit waiver** (§7.45(5)(C)); part 1 only used the negative half (it does not bar disconnection). The **1/6 residential cap**. Elderly waiver is **tariff-by-tariff** (Kyle) — and this is where Session 3J's `elderly_disabled` question resolves, since the answer likely is that it belongs here rather than in the disconnect-protection enum. Gap-list `deposit-interest-rate-table` (**effective-dated**, action #25). `pending-decision: rbac-model` gates cluster 51's authorization levels. Family 16's sequencing flag: **the day-30-vs-day-31 deposit-interest boundary is the first scenario written in that family.**
3. **Substrate to verify first, and there is a specific suspicion:** `customers.deposit_*` (seven columns: `deposit_amount`, `deposit_status` 6-value CHECK, `deposit_received_date`, `deposit_refund_date`, `deposit_refund_amount`, `deposit_interest_earned`, `deposit_notes`) and `payments.is_deposit` + `payments.deposit_status` (4-value CHECK) are **two separate deposit representations with overlapping status vocabularies**. Check whether they can disagree, and which one `customer_credits.origin_type = 'deposit_refund'` is derived from. This is the same scalar-versus-record shape that Session 3J found had already drifted for tax exemption.
4. **Session 3I's escheatment findings land directly in `escheatment-processing`**: `credit_aging_statistics` hardcodes a 1095-day dormancy for every `origin_type` against the catalog's Texas per-property-type finding (§72.1017 deposits ~18 months vs. §72.101 general 3 years), and `escheatment_events.customer_credit_id` is NOT NULL so an unapplied payment balance can never escheat.
5. **Keep testing claims — including this corpus's own.** Appendix A has been wrong six times in five sessions and, this session, **silent** once (item 3 has no appendix entry). Silence is harder to find: the technique for it is asking what happens *between* two documented states, rather than testing a stated claim.

## Warnings

- **Commit before ending a session.** An earlier session left 52 files of correct work uncommitted.
- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`** (both get a CHANGELOG entry each session).
- **The open items are deliberate, not authoring mistakes.** Don't resolve them unilaterally.
- **Verify push state; don't carry a number forward.** Use `git rev-list --left-right --count origin/main...HEAD` after a fetch.
- **Texas-only launch** remains the scope discipline.
- **The load-bearing absences now number seven**, one per recent domain: `tax_jurisdictions` (A-8, Domain 5); the exception-queue substrate (A-20, Domain 7 — known too narrow); the outbound communication log (A-16, Domain 8 — known one field short) with A-17/A-18; the payment-classification and effective-date column set (Domain 9 — A-12 known too large, A-13 incomplete, CI-057's NOC substrate with no appendix entry); the program-enrollment substrate (Domain 10 — A-11's design sound but missing the §7.45 receipt test, the dependency edge, and the grain question); and now **the collections-engine substrate** (Domain 11 — A-14 names the configuration gap and is silent on the determination-expiry gap, the holiday calendar, and the weather feed, all three of which are preconditions for the pipeline being lawful at all).
- **A closed question is not a safe question** (3I's D7-1). **A locked design is not a landed design** (3J's v5.4). **And an absent claim is not an absent gap** (3K's item 3) — Appendix A's silence on determination expiry is not evidence that nothing is missing there.
- **Appendix A has been materially wrong six times in five sessions**, in both directions, and silent on at least one structural gap. This corpus's own prior output has been wrong once, in a brief that reached Kyle. Treat both as hypothesis registers; any schema-hardening estimate derived from Appendix A will be wrong in both directions until each entry is re-checked against `sql/tu.sql`.
