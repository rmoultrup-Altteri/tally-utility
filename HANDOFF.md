# Handoff: Work Unit 6 Session 3J (Domain 10 — Programs & Assistance)

**Generated**: 2026-08-07
**Branch**: main (both repos)
**Status**: Ready for Review — WU5 complete; WU6 Sessions 3A–3J complete (Domains 1–10 of 13). Twenty-seven open items across the last seven sessions await Kyle: **two compiled briefs** (one of them amended this session) plus **Sessions 3I and 3J's eight items, not yet briefed**. Nothing blocks Session 3K.

## Goal

Continue **Work Unit 6** (Configurable-Rules Sessions 3+, one rule domain per session) per `cluster-and-workflow-inventory.md`'s Part 3 work queue.

## Orientation (read first)

Authoritative state lives in the **sibling repo** `/Users/ryanscomputer/code/gas-billing-memory/`, NOT this one. This repo (tally-utility) holds `sql/tu.sql` (canonical schema) + these handoff/discussion docs. Key files in gas-billing-memory:
- `application/canonical-invariants.md` — 135 invariants (CI-001–135) across 17 families, plus Appendix A's 21 schema-enforcement gaps. Q-4/Q-7/Q-9/Q-12 open by design.
- `application/configurable-rules/cluster-and-workflow-inventory.md` — the Sessions 3+ work queue (Part 3); governs WU6
- `application/configurable-rules/decision-tables/` and `workflows/` — WU6 output: **91 files** across Sessions 3A–3J
- `application/configurable-rules/configuration-catalog.md` + `de-review-answers.md` / `de-review-answers-8-11.md` — the catalog and Kyle's earlier resolved decisions. **`de-review-answers-8-11.md` carries DE-9 and the two regulatory corrections that govern Domain 10 and 11.**
- `application/wu5-wu6-kyle-decisions-2026-07-10.md` — historical source record. **D8-1, D8-2, D8-3, D9-1, D9-2 govern Domains 10–11; read them before Session 3K.**
- `application/configurable-rules/wu6-sessions-3e-3f-review-brief.md` and `wu6-sessions-3g-3h-review-brief.md` — the fourth and fifth briefs, **both open, both awaiting Kyle**. **The 3G–3H brief was amended 2026-08-07** with a correction (see below) — if Kyle has already read it, he needs to know.
- `application/wiki-ingestion-pending.md` — Sections A–R
- `application/execution-kickoff.md` — the 12-work-unit sequence; no per-session WU6 marker (progress lives here and in `wiki-ingestion-pending.md`)

## Completed (this session)

- [x] **Session 3J — Domain 10 (Programs & Assistance), clusters 43–45** — three decision tables (`budget-billing-eligibility-and-trueup` #43 unique, `dpa-eligibility-and-breach` #44 priority, `program-enrollment-eligibility` #45 collect) and six workflows (`budget-billing-enrollment`, `budget-billing-trueup`, `budget-billing-exit`, `dpa-creation`, `dpa-payment-progress`, `dpa-breach-handling`). Nine files.
- [x] **Verified the v5.4 substrate is absent before drafting** — `customer_program_enrollments` and `program_types` are not in `sql/tu.sql`. A-11 describes the current substrate accurately.
- [x] **Corrected a Session 3H error of my own, in three places** — see "Correction carried" below. This is the first correction in the corpus to a claim I authored rather than one the appendix asserted.
- [x] Logged in `wiki-ingestion-pending.md` Section R + both CHANGELOGs.

## Not Yet Done

- [ ] **Sessions 3K through 3M** — collections/disconnect/deposits (46–55), customer/account lifecycle (56–57), import/admin (58–60). **Session 3K is next and is the largest remaining**; the inventory flags it as splitting into 3K-collections and 3K-deposits.
- [ ] **Sessions 3I and 3J have no review brief yet.** The two-session cadence now points at a **3I–3J consolidated brief**, and the domains genuinely pair: Domain 9's agency-pledge *payment* restriction gap and Domain 10's agency-pledge *enrollment* are the same program from two sides, and Domain 10's DPA installment-tracking gap is Domain 9's payment-classification gap seen from its second consumer. Drafting it before 3K is defensible; drafting it after 3K would put three sessions in one brief, which is more than the format has carried.
- [ ] **Kyle answers the two open briefs.** Suggestion if asked which first remains 3G–3H — **and it now needs a note that the brief has been amended**, since he may have read the superseded text.
- [ ] **`tally-utility` has no git remote configured** — local-only while holding the canonical schema and all session history. Carried unchanged from four handoffs.

## Failed Approaches (Don't Repeat These)

- **Using the Agent tool with a placeholder prompt as a "wait for background task" mechanism** (2026-07-05): `Agent({prompt: "placeholder", name: "waiter"})` spawns a *real* agent that takes the literal text as its assignment and does unwanted work. **End the turn with a short text update and no tool call** — background-task notifications arrive on the next turn regardless.
- **Asserting a column has no CHECK constraint without grepping for its constraint by name** (2026-08-06, corrected 2026-08-07). The constraint list sits ~50 lines below the column definition in `sql/tu.sql`, so reading the column block alone is not sufficient evidence of absence. Grep `<table>_<column>_check` before claiming any column is unconstrained.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Led cluster 45 with the **tax-exemption migration precedent** rather than with the missing enrollment table | The missing table is already documented (A-11, CI-059–066) and adding a tenth restatement adds nothing. What is new is that the *pattern A-11 copies* has already drifted in production — `should_charge_tax()` and `compliance_statistics` disagree about tax exemption in both directions because the legacy scalar was preserved with no trigger. That reframes A-11's `do_not_disconnect` trigger from implementation detail to the load-bearing element, using evidence from this schema rather than from principle. |
| Applied **Kyle's own Q-6 reasoning** to `elderly_disabled` | He closed Q-6 by finding that the family-violence flag sits in §7.45's deposit subsection and therefore does not join the disconnect bypass list. `elderly_disabled` has the same provenance — A-11's own gloss calls it "Texas deposit waiver per CI-129" — and sits in `disconnect_protection_type` alongside genuine discontinuance bars. Raised as *his ruling applied to a value he wasn't asked about*, to be confirmed rather than assumed. |
| Treated the **premise→customer grain change** as one item rather than two | Budget billing (cluster 43) and DPAs (cluster 44) hit it independently in the same session, from opposite directions. Two clusters converging on one question is the argument for resolving it once at the design level — one nullable `location_id` on the enrollment row — rather than twice in implementation. |
| Named `dpa-payment-progress`'s gap as **D7-1's counterpart, not D7-1's flaw** | Kyle's removal of customer payment designation is sound consumer-protection design and should not be reopened. What is missing is the LDC-side mechanism to mark a payment as satisfying an installment *by rule* — a different mechanism that does not conflict with his ruling. Framing it as a flaw would have invited him to relitigate a closed and correct decision. |
| Corrected my own error **in the open brief first**, written to be read before the original claim | The 3G–3H brief is with Kyle now. A correction that appears only in the source file would let him act on superseded text. The brief's note leads with what was wrong and why the item survives in sharper form. |

## Session 3J's four open items

1. **The scalar/multi-row migration precedent v5.4 copies has already drifted, in production.** A-11 says the enrollment lifecycle mirrors CI-046's tax-exemption pattern. It does — but `customers.is_tax_exempt` was kept "for backward compat" and today **`should_charge_tax()` reads only `customer_tax_exemptions` while `compliance_statistics` reads only `is_tax_exempt`, with nothing synchronizing them.** A customer with a valid certificate and the boolean unset is untaxed by the engine and reported `not_exempt`; the reverse case is taxed and reported permanently exempt. Both are live. This is exactly what v5.4 reproduces for disconnect protection if A-11's trigger is skipped — so it **validates** the locked design and prices its least glamorous element. The tax divergence is separately a bug worth fixing now.
2. **`customers.do_not_disconnect` is maintained by no trigger today, and the compliance view treats it as authoritative.** A-11 says the boolean is "*preserved* as a trigger-maintained denormalization," which reads as though it already is one. The only triggers on `customers` are `set_updated_at` and `trg_enforce_billing_hold_metadata`. Meanwhile `compliance_statistics.disconnect_protection_status` opens with `WHEN (do_not_disconnect = false) THEN 'no_protection'` — the boolean short-circuits the whole classification and the protection type is never consulted — and `idx_customers_protection` is a partial index on `do_not_disconnect = true`. **An active medical certificate with an unset boolean reads as unprotected and is invisible to the fast path a collections engine would use.** Given DE-9's framing (documented deaths from dropped holds at cutover), this is the highest-consequence instance of the class in the corpus, and it exists *before* v5.4 rather than because of it.
3. **v5.4 changes program grain from premise to customer, and no document acknowledges it.** `service_locations.budget_billing`/`budget_amount` is per premise today (the catalog records the level explicitly); A-11's `customer_program_enrollments` is customer-keyed with one `levelized_amount`, so a three-premise commercial customer loses two amounts in the migration. D8-3's "one active agreement per account" inherits the same ambiguity from the DPA side, since gas service and arrears are per location while the enrollment key is per customer. **One nullable `location_id` on the enrollment row closes both**; without a decision the migration makes it silently by collapsing rows.
4. **`elderly_disabled` may be miscategorized as a disconnect protection.** Q-6 closed with the finding that Texas's family-violence flag sits in §7.45's *deposit* subsection and "does **not** join the disconnect bypass list." `elderly_disabled` has identical provenance — A-11 glosses it "Texas deposit waiver per CI-129" — and sits in `customers.disconnect_protection_type`, whose every other value is a genuine discontinuance bar. Marked protective it blocks collections Texas does not bar; quietly demoted without moving the deposit obligation, the waiver is lost.

**Also surfaced, smaller:** no DPA agreement record at all — nine cluster-44 inputs have no substrate, defeating both CI-060's reproducibility and **§7.45's non-discrimination clause** (raised in three files; the repetition is the priority argument); no running budget balance, making CI-059's dual-balance discipline structurally impossible rather than partially met (three files); no `depends_on_enrollment_id`, so CI-081's medical-hold/IA dependency and D9-2's cascade have no edge to traverse even after v5.4 (`supersedes_enrollment_id` expresses replacement, a different relation); breach configuration landing in A-11's explicitly un-CHECK-enforced `enrollment_data jsonb`, where DPA and medical are the two types whose malformed blobs produce wrongful disconnections rather than bad reports; the §7.45 **five-working-day receipt test** absent from A-11's field list, with no working-day calendar anywhere in the schema; a tenant-extensible `program_types` table carrying a regulatory `is_disconnect_protective` flag; `budget_amount` as a mutable scalar with no effective date on a term the customer agreed to (third instance of that pattern, after `bill_messages.message_body` and `invoices.pdf_url`); no plan-breach notice type in cluster 38; no budget-billing policy keys (three settings keys — cheapest item in the domain); no `origin_type` or `transaction_type` value naming a budget settle-up; no reason or actor on enrollment lifecycle transitions; and **the default `oldest_first` posting order working against DPAs systematically** rather than occasionally.

**Rule worth stating once, now at three instances:** any customer-owed balance must become a `customer_credits` row to enter the dormancy and escheatment machinery, and the platform currently has three ways to hold customer money without one — unapplied payment balances (3I), undeliverable refunds (3I), and over-collected budget-billing exits (3J).

## Correction carried

**Sessions 3G and 3H corrected appendix errors. This one corrects an error I authored.**

`delivery-method-routing.md` (Session 3H) asserted in two places, and the **open** `wu6-sessions-3g-3h-review-brief.md` repeated, that `customers.preferred_contact_method` has **no CHECK constraint**. It has a 5-value CHECK — `mail`, `email`, `phone`, `text`, `portal` — at `sql/tu.sql:2536`. The error came from reading the column definition block without grepping for the constraint, which sits ~50 lines below it. All three places are corrected with dated notes, and the brief's note is written to be read *before* the original claim, since Kyle may already have read it.

**The correction sharpens 3H item 2 rather than weakening it.** Both columns are properly constrained enums with deliberately *different* value sets: `preferred_contact_method` has 5 including `phone` and `text`; `billing_delivery_method` has 4 including `both` and `portal_only`, excluding `phone` and `text` entirely. Two carefully-specified non-overlapping vocabularies do not look like an oversight — they look like **two columns answering two different questions**, general correspondence versus bill delivery. On that reading the "opposite defaults" are not a contradiction (`mail` for correspondence and `email` for bills are each defensible), and a Check #4 fix applied to only one of them may have been correct. **Revised ask: are these two columns deliberately distinct?** — cheaper to answer, and if yes it resolves the item and leaves item 1's E-SIGN exposure standing on its own merits.

**3H Open question 3 refined by the same correction.** "`text_message` is unelectable at the customer level" is false. The better-anchored finding: `invoices.delivery_method` permits `text_message`, `preferred_contact_method` permits `text`, `billing_delivery_method` permits neither — the two ends of the path allow SMS and the middle does not — and beneath all three, `customers.phone`/`alt_phone` are bare `text` with no line-type column, no mobile flag, no verification state. A three-column half-built feature, not a stray enum value reachable only by a bug.

## Current State

**Working:** `gas-billing-memory` main. WU5 output (15 axes docs) and WU6 Sessions 3A–3J output (91 decision-table/workflow files) internally consistent. `tally-utility` has no remote.
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

Non-obvious: hit policies aren't decorative. `rule-order` isn't row-matching at all — clusters 17 and 23 are staged procedures in table form. `collect` (rules co-fire) vs. `priority` (ranked; highest-ranked match decides) vs. `first-match` (ordered scan, stops on hit) vs. `unique` (mutually exclusive; overlap is a defect) imply different test shapes. Session 3I used `priority` as a **constraint stack** (a regulatory floor binding above a configurable rule) — reuse that where a statutory minimum overrides tenant configuration. Session 3J's cluster 45 is the corpus's clearest case where **the hit policy is itself the finding**: `collect` is required by CI-064's additive composition, and the current single-valued column forces `unique` semantics, which is a violation rather than a simplification. `[split-with-addenda]` workflows carry a partner-neutral spec plus a deferred Addenda section; `ami-amr-file-ingestion` is the precedent, with two each added in 3H and 3I.

## Resume Instructions

1. **Session 3K — Domain 11 (Collections, Disconnect & Deposits), clusters 46–55.** The largest remaining session; the inventory explicitly flags it as splitting into **3K-collections** and **3K-deposits**, and taking that split is probably right rather than optional — ten clusters is more than any prior session by a wide margin. Known content: **Q-6 research** (family violence = deposit waiver only; CI-069's bypass list finalizes without it); the **EWE research** (self-executing, at-or-below 32°F previous-day high with ≤32°F forecast next 24h, county-level via nearest NWS station, **no declaration required**, **no heat trigger for gas** — do not conflate with PUCT §25.483); **D9-1** (no-photo-evidence disconnect sites → supervisor-role approval recorded as an event with a reason code); **D9-2**; **D8-2** (bankruptcy holds event-terminated, not date-terminated; expiry-type enum, nullable end date, no auto-expiry); the **§366 research** (no Texas overlay on federal bankruptcy for gas; 20-day individual / 30-day Ch. 11 adequate-assurance windows); and Family 16's sequencing flag that **the day-30-vs-day-31 deposit-interest boundary is the first scenario written in that family**.
2. **Three of Session 3J's items land directly in 3K's path** and should be carried in rather than rediscovered: `do_not_disconnect`'s unreliability (every bypass evaluation reads it), `elderly_disabled`'s categorization (it is a value in the bypass list), and the additive-composition read that cluster 46 depends on.
3. **Read the schema directly, and now also read this corpus's own prior claims.** The appendix-testing technique has produced the top finding in four consecutive sessions. Session 3J extended it: pointed at my own Session 3H output, it found an error that had already propagated into a live brief. **Before relying on any prior session's schema claim, re-verify it** — and specifically, grep `<table>_<column>_check` before repeating any "no CHECK constraint" assertion.
4. **Domain 11 substrate to verify first:** `dunning_events` (11-value `event_type`), `invoices.dunning_stage` (10-value CHECK), `customers.deposit_*` (7 columns incl. `deposit_interest_earned`), `customers.disconnect_protection_*`, `service_orders`, `escheatment_events`. Note that `customers.deposit_status` and `payments.is_deposit`/`deposit_status` are two separate deposit representations — worth checking whether they agree.

## Warnings

- **Commit before ending a session.** An earlier session left 52 files of correct work uncommitted; the next session's first act was rescuing it.
- **Don't spawn an Agent with a placeholder prompt to "wait."** See Failed Approaches.
- **HANDOFF.md and CHANGELOG.md live in `tally-utility`; all work artifacts live in `gas-billing-memory`** (which has its own, more detailed CHANGELOG — both get an entry each session).
- **The open items are deliberate, not authoring mistakes.** Don't resolve them unilaterally.
- **Verify push state; don't carry a number forward.** A stale "42 unpushed commits" figure propagated across several handoffs. Use `git rev-list --left-right --count origin/main...HEAD` after a fetch.
- **Texas-only launch** remains the scope discipline. Sewer billing and government/wholesale classes are flagged likely-out-of-scope-for-v1 but not formally deferred, unlike Q-12's transport-balancing/submetering/multi-commodity.
- **The load-bearing absences now number six**, one per recent domain: `tax_jurisdictions` (A-8, Domain 5); the exception-queue substrate (A-20, Domain 7 — known too narrow); the outbound communication log (A-16, Domain 8 — known one field short) with A-17/A-18 alongside it; the payment-classification and effective-date column set (Domain 9 — A-12 known too large, A-13 known incomplete, CI-057's NOC substrate with no appendix entry at all); and now the program-enrollment substrate (Domain 10 — A-11's design is sound but **misses the §7.45 receipt test, the enrollment dependency edge, and the grain question**, and its `do_not_disconnect` trigger is load-bearing rather than incidental). Any schema-hardening session inherits all of these *as amended by these sessions*, not as the appendix states them.
- **A closed question is not a safe question.** Session 3I's headline sat under D7-1, a ruling Kyle made and closed. Resolved decisions still need their substrate checked.
- **A locked design is not a landed design.** Session 3J's substrate check took two minutes and changed how every file was written. `customer_program_enrollments` has been described as locked since 2026-05-26 and is still not in the SQL.
- **Appendix A has now been materially wrong six times in four sessions**, in both directions — and this corpus's own prior output has been wrong once, in a brief that reached Kyle. Treat both as hypothesis registers. Any schema-hardening estimate derived from Appendix A will be wrong in both directions until each entry is re-checked against `sql/tu.sql`.
