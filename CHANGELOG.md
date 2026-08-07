# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

---

## 2026-08-07 — Session (cont.): Work Unit 6 Session 3J (Domain 10 — Programs & Assistance)

Drafted clusters 43–45 and six workflows in `gas-billing-memory`. Nine files: `budget-billing-eligibility-and-trueup` (#43, unique), `dpa-eligibility-and-breach` (#44, priority), `program-enrollment-eligibility` (#45, collect); `budget-billing-enrollment`, `budget-billing-trueup`, `budget-billing-exit`, `dpa-creation`, `dpa-payment-progress`, `dpa-breach-handling`. WU6 output now **91 files**; Domains 1–10 of 13 drafted.

**Substrate verified absent first.** `customer_program_enrollments` and `program_types` are **not in `sql/tu.sql`** — the v5.4 patch has not landed, so this domain is drafted against a locked design with the current single-column substrate's limits named per row.

**The organizing finding is a precedent rather than a gap.** A-11 says the enrollment lifecycle mirrors CI-046's tax-exemption pattern — and it does. But the scalar that pattern replaced was kept "for backward compat" and **has drifted in production**: `should_charge_tax()` reads only `customer_tax_exemptions`, `compliance_statistics` reads only `customers.is_tax_exempt`, nothing syncs them, and both directions are live today. That is exactly what v5.4 will reproduce for disconnect protection unless A-11's `do_not_disconnect` trigger lands — so the finding **validates** the locked design and prices the cost of skipping its least glamorous element.

**Four open items:** the drifted migration precedent; **`do_not_disconnect` maintained by no trigger today** while `compliance_statistics` short-circuits on it and `idx_customers_protection` indexes it — an active medical certificate with an unset flag reads as unprotected and is invisible to the fast path, which given DE-9's documented-deaths framing is the highest-consequence instance of this class in the corpus and exists *before* v5.4; **a premise→customer grain change** that budget billing and DPAs hit independently (one nullable `location_id` closes both); and **`elderly_disabled` likely miscategorized** as a disconnect protection by the same reasoning Kyle used to close Q-6.

**Correction to Session 3H — and this one was my own error, not the appendix's.** Both `delivery-method-routing.md` and the **open** 3G–3H brief asserted `customers.preferred_contact_method` has no CHECK constraint. It has a 5-value CHECK. Corrected in place, with the brief's note written to be read before the original claim. The correction **sharpens** 3H item 2: two properly-constrained enums with deliberately different value sets look like two columns answering different questions, on which reading the opposite defaults are not a contradiction at all.

**Method note.** Running total is **six material errors across four sessions**, in both directions — plus a new subcategory this session: an authoring error of mine, found by the same appendix-testing technique, already propagated into a live brief. The technique should be pointed at this corpus's own prior output, not only at Appendix A.

Logged in `wiki-ingestion-pending.md` Section R and both CHANGELOGs.

---

## 2026-08-07 — Session: Work Unit 6 Session 3I (Domain 9 — Payments)

Drafted clusters 39–42 and six workflows in `gas-billing-memory`. **Ten files — the largest single WU6 session so far.** Decision tables: `payment-posting-allocation` (#39, priority), `overpayment-and-credit-disposition` (#40, priority), `nsf-and-ach-return-handling` (#41, first-match), `autopay-eligibility-and-failure` (#42, first-match). Workflows: `lockbox-remittance-ingestion` [addenda], `payment-gateway-webhook-handling` [addenda], `ach-return-handling`, `autopay-enrollment-and-management`, `unapplied-cash-resolution` (CSR), `refund-processing`. WU6 output now stands at **82 files** across Sessions 3A–3I; Domains 1–9 of 13 are drafted.

**Domain 9 inverts Domain 8's shape** — substrate-rich and rule-poor. The reversal-lineage machinery is genuinely well built, `customer_credits` is a compliance-grade unclaimed-property substrate, and CI-051's no-PAN-storage discipline is the corpus's only `structurally-enforced` invariant. What is missing is narrower: the columns settled decisions need to read, and the functions that would keep five denormalized balance totals honest.

**New failure mode for the corpus: a *resolved* decision that turned out to be unexecutable.** Prior sessions found gaps under open questions. Kyle closed Q-5 with D7-1's tiered payment-class allocation, and the tier that overrides the posting order — agency/pledge, "restriction stored on the payment record" — has no field to store it in and no way to be told apart from an ordinary customer payment.

**Four open items:** D7-1's unexecutable tier (no payer-class or restriction columns; three enums all describe something else); `invoice_applications` being **per-invoice, not per-charge**, so CI-050's regulated-first floor has no expression even after D7-2's `regulatory_class` lands — contradicting CI-049's own schema-status line; **A-12 being two gaps under one name**, with `payments.unapplied_amount` plus a purpose-built partial index already solving the amount-mismatch case while the unidentified-*payer* case remains a total blocker (and `payments` lacking the balance CHECK `customer_credits` has, with **no payment-posting function anywhere in the schema**); and the escheatment dormancy clock **hardcoded to 1095 days for every `origin_type` in a shipped materialized view**, against the catalog's own Texas per-property-type finding — under-reporting deposits by roughly eighteen months.

**Design note:** Session 3H's E-SIGN delivery-consent substrate and this session's Reg E debit-authorization substrate have near-identical shapes and should be scoped as one consent table with a type discriminator, not two near-duplicates six weeks apart.

**Second procurement criterion in the corpus:** lockbox postmark capture is a priced vendor service tier. Without it, Kyle's 2026-06-12 Texas timeliness ruling is unimplementable for mailed payments — the same shape as Session 3H's print-vendor criterion.

**Narrows Session 3H item 2** rather than compounding it: cluster 42's "Check #4 fix #3" has its substance recorded in the catalog under the 2026-06-12 review in Kyle's voice, so mislabeling is likelier than an unrecorded ruling.

**Method note.** Five of ten files produced their sharpest finding by testing an Appendix-A or enforcement-status claim against `sql/tu.sql`; three were wrong, in both directions. At three sessions and five errors, the appendix is a hypothesis register, not an inventory — and the schema-hardening estimate derived from it will be wrong both ways until each entry is re-checked.

Logged in `wiki-ingestion-pending.md` Section Q and both CHANGELOGs.

---

## 2026-08-06 — Session (cont.): Work Unit 6 Session 3H (Domain 8 — Delivery & Communications)

Drafted clusters 36–38 and four workflows in `gas-billing-memory` (`60a4557`, pushed). Seven files: `delivery-method-routing` (#36, first-match), `communication-language-format` (#37, unique), `notice-and-alert-triggering` (#38, collect); `invoice-pdf-generation-and-retention`, `email-delivery-with-fallback` [addenda], `print-vendor-handoff` [addenda], `consolidated-invoice-assembly`. WU6 output now stands at 72 files across Sessions 3A–3H; Domains 1–8 of 13 are drafted.

**Domain 8 is the gap-densest domain in the corpus** — A-16 (outbound communication log), A-17 (notice-template versioning), and A-18 (bill-image archive) stacked, plus a fourth absence not in Appendix A at all. Per CI-095's own consequence, every notice the platform fires today is regulatorily not-sent.

**Four open items:** no E-SIGN consent substrate while `billing_delivery_method` defaults to `email` (the condition §101(c) prohibits); "Check #4 fix #4" cited by the inventory with **no source document anywhere in the KB**, alongside two adjacent `customers` columns defaulting to opposite channels; A-16's outcome enum being one field short of CI-135's content-to-envelope match assertion while A-17 overstates its own gap (`bill_messages` supplies most of the shape) and **`bill_messages` rows are mutable, a live CI-094 violation**; and no declaration of whether a collections step gates on `sent_at` or `delivery_confirmed_at` — the cheapest item, reaching three domains.

**Method note worth carrying:** two of the four came from testing an *Appendix A claim* against `sql/tu.sql` rather than from reading the schema cold. Combined with Session 3G's CI-134 finding, the appendix has now been materially wrong twice in two sessions. It should be treated as a hypothesis to test, not a settled inventory.

**Correction to Session 3G, made in place.** The claim that a bill dispute "has nowhere to live except `customers.billing_hold_reason`" was too strong — `customer_interactions` carries `reason='high_bill_complaint'` with an `invoice_id` FK and a full status lifecycle. The corrected ask (add disputed amount and protection linkage to existing substrate) is smaller than what was originally implied.

Logged in `wiki-ingestion-pending.md` Section O and both CHANGELOGs. Pushed and level with `origin/main`.

**Brief compiled the same session** (`c4a36cc`): `wu6-sessions-3g-3h-review-brief.md`, the fifth in the series, spanning both sessions' 14 files. Part A carries the four items above. **Part D is new to the brief format** and holds two things that aren't rulings — a proposed fourth option closing the *previous* brief's open consolidated-ledger question (children post; the parent is a presentation-and-payment construct, because the customer pays against the document carrying the invoice number), and the print-vendor procurement criterion. It opens with the methodological note rather than a question, and carries the Session 3G dispute correction in its narrowed form so Kyle meets the corrected version first.

**Two briefs are now outstanding simultaneously** — a first. They're independent, but eight Part A items across two documents is a lot to hand over at once; if Kyle wants a sequence, 3G–3H first, since its "Check #4" item resolves cheaply and changes the cost of the E-SIGN item beside it.

**Next:** Session 3I — Domain 9 (Payments), clusters 39–42.

---

## 2026-08-06 — Session (cont.): Work Unit 6 Session 3G (Domain 7 — Pre-Mail QA & Exceptions)

Drafted clusters 33–35 and four workflows in `gas-billing-memory` (`8e22bc6`, pushed). Seven files: `statistical-anomaly-detection` (#33, collect), `absolute-baseline-qa` (#34, collect), `exception-threshold-and-routing` (#35, first-match); `pre-mail-exception-review`, `canary-account-reconciliation`, and the two workflows deferred from 3F — `pre-mail-bill-correction` and `high-bill-dispute-intake-and-resolution`. WU6 output now stands at 65 files across Sessions 3A–3G; Domains 1–7 of 13 are drafted.

**What this session's schema reading produced** (third session running with no research agents — the substrate was already in `sql/tu.sql`):

- **CI-134's enforcement-status claim does not hold.** It reads "canary expected values are configured … not a missing-table gap," which is what classifies it `requires-application-discipline` rather than `unenforced-gap`. There is no canary table, no `is_canary`/`is_test_account` column, and no reserved settings key — the canary accounts cannot be identified, so their expected values cannot be stored. There is likewise no revenue-requirement or rate-case entity. Two of the invariant's three baselines are gaps, and **A-20 does not cover a canary registry**, so it would fall through the schema-hardening queue.
- **Nothing in `tenants.settings` is release-blocking.** The four cycle-level thresholds that exist are aggregates of the batch's own contents — skip rate, estimation rate, anomaly rate, amount swing — not comparisons against an external baseline, so a misconfiguration in place since the prior cycle passes all four. All four are named `warning`.
- **The pre-mail gate is nearly off on default settings.** `review_required_anomalies` defaults to a single read-level value, and the `anomaly_type` enum has no bill-amount values to add.
- **No bill-level dispute entity**, despite a complete read-level one. `disconnect_protection_type = 'pending_dispute'` exists with nothing to fire it.
- **Action #40 answered from the schema side:** HDD exists, but zone-keyed via WNA, winter-months-only, and absent for non-WNA tenants.

**Structural observation carried into 3H:** the per-bill gate is structurally enforced (`invoices.status = 'held'` with reason/timestamp/actor and a trigger), while the cycle-level gate CI-134 calls higher-leverage has no structure at all (`billing_runs.status` has no held value). Delivery is likely to have the same asymmetry, since CI-135 is a batch-level assertion about a vendor handoff.

Logged in `wiki-ingestion-pending.md` Section N and both CHANGELOGs. `gas-billing-memory` pushed and level with `origin/main`.

**Next:** Session 3H — Domain 8 (Delivery & Communications), clusters 36–38. First thing to check: `invoices.delivery_method` defaults to `'email'` while Check #4 fix #4 made `mail` the default — an apparent live contradiction.

---

## 2026-08-06 — Session (cont.): Work Unit 6 Session 3F (Domain 6 — Billing Run, Corrections & Backbilling)

**Status:** Same working session as 3E, continued. 14 files — six decision tables (clusters 27–32) and eight workflows — committed as `gas-billing-memory 5b10d7e`. WU6 now stands at Sessions 3A–3F done, 3G–3M remaining. No application code written.

### Done
- **Session 3F — Domain 6, clusters 27–32:** `backbilling-cap-enforcement` (#27, priority), `correction-and-void-eligibility` (#28, priority), `cancel-rebill-bitemporal` (#29, unique), `billing-run-read-gating` (#30, first-match), `invoice-consolidation` (#31, unique), `adjustment-authorization` (#32, priority).
- **Eight workflows:** `billing-run-normal-cycle`, `billing-run-offcycle`, `final-bill-generation`, `cancel-rebill-operator-correction`, `cancel-rebill-regulatory-retroactive`, `adjustment-with-approval-threshold`, `bulk-account-adjustment`, `backbilling-limit-compliance-review`.
- **Consolidated the Phase 0–9 billing pipeline**, which existed only as scattered `sql/tu.sql` column comments, into `billing-run-normal-cycle`: Phase 0 run initiation · 1 candidate selection · 2A estimation · 3 consumption · 4 rate items · 5 ad-hoc charges and correction rate dates · 6 invoice assembly · 7 operator review · 8 posting · 9 PDF and delivery. Agrees with CI-100 and is more specific.
- **Logged in `wiki-ingestion-pending.md` Section L** and the `gas-billing-memory` CHANGELOG.
- **Deferred deliberately:** `pre-mail-bill-correction` and `high-bill-dispute-intake-and-resolution`. Part 2 files both under pre-mail/correction, but pre-delivery correction is a different operation from void/rebill and belongs with Session 3G's pre-mail QA cluster set.

### This domain differs from every prior one: the code already exists
`void_invoice()` is a ~270-line function implementing most of cluster 28's mechanics — voidability validation, cross-tenant defense-in-depth, read release to `void_released`, ad-hoc charge disposition, `void_reversal` ledger posting, `invoice_events` logging. `get_correction_rate_date()` implements cluster 29's resolver. The tables mostly specify what those functions *don't* do, which is a different authoring job than Domains 1–5 and produced sharper findings.

### Five open items surfaced, in order of consequence
1. **DE-3's gas guard doesn't exist and the schema argues against it.** DE-3 requires gas correction runs to reject `correction_rate_mode='current'` via a hard guard, and marks it a proposed new invariant. It was never implemented, never added to `canonical-invariants.md`, and **both relevant column comments document `current` as existing precisely for the wrong-meter case** the prohibition would forbid. Governs cluster 29 and both cancel-rebill workflows identically.
2. **Backbilling is unenforced end to end.** No cap table (A-2), no cause column, no period check in `void_invoice()` — current behavior is unbounded backbilling for every cause, including ones §7.45 caps at three months. Underneath: the cause enum can't be derived from `invoices.void_reason_code`'s seven *operational* values, and **`rate_misapplication`'s 6-month rule is a collectability protection (disconnection prohibited), not a rebill window** — so the cap table holds two different kinds of limit in one enum.
3. **Consolidated invoices: nothing says whether parent or children post to `account_ledger`.** Both double-counts and breaks CI-019; parent-only hides per-location arrears from collections; children-only leaves the delivered artifact with no ledger presence.
4. **No aggregate authorization.** Ten thousand $1 adjustments each pass the per-charge threshold a single $10,000 adjustment would fail. No aggregate concept in the schema, and no bulk-operation entity to hold a reviewed population.
5. **Unapproved charges aren't excluded from billing pickup.** The documented Phase-5 predicate doesn't test `requires_approval` / `approved_at`, while the approval queue's partial index defines exactly those charges as outstanding — approval is currently advisory.

Two smaller findings: cluster 32's threshold must compare `abs(amount)`, since `amount` is signed and a naive `>=` leaves credits ungated — the direction that costs money; and `adhoc_charges.voided_from_invoice_id`'s comment documents the correction audit chain with its last hop pointing the wrong way.

### One coherence worth recording
`void_invoice()`'s auto-revert reason set (`wrong_read`, `wrong_rate`, `service_date_error`, `system_error`) has as its complement exactly the void-only-eligible set (`wrong_customer`, `duplicate`, plus `other`). Where a rebill is coming the charges ride it automatically; where no corrected bill may exist a human decides each one. It reads as two unrelated `UPDATE` branches until they're lined up — worth naming so nobody "simplifies" the duplication away.

### Method
Same as 3E and for the same reason: no research agents, reading `sql/tu.sql` directly against `canonical-invariants.md` Families 1, 2, 13, and 16 plus the catalog, DE-3, and action #9. All five open items came from that comparison. Two sessions in, this looks like the right default for domains whose substrate already exists in the schema — the prose docs and the schema disagree in specific, findable ways, and only reading both surfaces them.

### Next
Session 3G — Domain 7 (pre-mail QA and exceptions), clusters 33–35, carrying CI-134's mass-error gate and DE-10's tenant-tunable thresholds. `billing-run-normal-cycle`'s Exc 4 already names the seam it inherits.

---

## 2026-08-06 — Session: Commit the pending fold-in, then Work Unit 6 Session 3E (Domain 5 — Taxes & Fees)

**Status:** Two units of work. First, the prior session's Kyle-decisions fold-in was sitting uncommitted in `gas-billing-memory` (52 files edited, 1 renamed) — committed as `fe435cc`. Then Session 3E drafted: 4 decision tables + 1 workflow, committed as `fe07a10`. WU6 now stands at Sessions 3A–3E done, 3F–3M remaining. No application code written.

### Done
- **Committed the orphaned fold-in** (`gas-billing-memory fe435cc`). Kyle answered both consolidated review briefs on 2026-07-10 (`application/wu5-wu6-kyle-decisions-2026-07-10.md`); the prior session applied all 40+ resolutions across 52 files but never committed. Nothing was lost — but it had been sitting in the working tree for a day with no commit, which is exactly the state a `git stash`, a branch switch, or a wrong `git checkout` destroys silently.
- **Session 3E — Domain 5 (Taxes & Fees), clusters 23–26** (`gas-billing-memory fe07a10`): `tax-application-and-stacking` (#23, rule-order), `tax-exemption-eligibility` (#24, unique), `adhoc-charge-taxation` (#25, priority), `franchise-fee-application` (#26, first-match), plus the `tax-exemption-cert-submission-and-renewal` workflow.
- **Drafted a workflow the Part 3 queue doesn't list for this session.** The queue says "tax steps fold into billing-run" — correct for the *application* steps, but `tax-exemption-cert-submission-and-renewal` is a Part 2 customer-lifecycle workflow whose entire subject is cluster 24's substrate. Writing it in Session 3L would mean writing it cold, months after walking CI-046. Session 3L inherits it instead of producing it.
- **Logged in `wiki-ingestion-pending.md` Section K** and the `gas-billing-memory` CHANGELOG, per the standing rule that every canonical-data change on main gets a wiki-ingestion target.

### Key finding: this domain's central substrate doesn't exist
Unlike Domains 1–4, cluster 23's per-jurisdiction loop iterates over `tax_jurisdictions` — gap A-8, a table that isn't in the schema. Stated plainly in the table rather than written around: for Texas launch that loop has one or two iterations driven off `service_locations.inside_city_limits`/`franchise_city`, not the eight-jurisdiction stack `11-taxes-and-gl-accounting.md` describes. The implementable slice today is essentially cluster 26 alone.

### Four schema-shaped open items surfaced, deliberately not resolved
Same discipline as Sessions 3A–3D's four tensions — each is a conflict between two things that both look authoritative, so picking a side silently would encode a wrong assumption downstream.
1. **`rate_items.is_taxable_default` defaults to `false`.** CI-045's central named silent failure is a new charge type rolled out with no explicit tax-base classification defaulting by omission. The schema default *is* that failure, under-collecting, and it makes "explicitly false" indistinguishable from "never decided."
2. **`franchise_fee_rules.applies_to` vs. the per-item `is_taxable` chain** — two mechanisms for one concept, diverging whenever any item is non-taxable, and none of `applies_to`'s four enum values can express "gross revenue minus PSF," the one carve-out 16 TAC §8.201 mandates. Decides whether CI-038's exclusion is implementable today or blocked on schema work. The session's most consequential item.
3. **Two exemption substrates, one wired.** `should_charge_tax()` reads only `customer_tax_exemptions`, never the legacy `customers.is_tax_exempt` flag kept "for backward compat." The sharper consequence: the renewal-prompt machinery CI-046 asks for **already exists — on the substrate being retired** (`tax_exemption_expiry_date` + a 60-day `expiring_soon` view). CI-046's "renewal-prompt gap" is really a never-ported prompt.
4. **`franchise_city` lives on both `service_locations` and `rate_schedules`**, both indexed, no stated precedence. The tables assume premise-side authority (per CI-044) and say so, so the assumption is visible if it's wrong.

Two smaller defects got suggested resolutions but were left for Kyle too: the platform charge-type defaults list enumerates 16 of 17 `adhoc_charges.charge_type` values and omits `miscellaneous` — the one type with no semantics to default from — and the taxability settings key is spelled two different ways between the schema comment and the catalog.

### What the schema already got right
`should_charge_tax(customer_id, item_is_taxable, service_type, as_of_date)` implements CI-046's valid-for-the-period rule correctly today, with its own comment instructing callers to pass a historical date on corrections. Cluster 24 is therefore largely a specification of an existing function, not a proposal — which is why its priority scenario asserts that *callers* pass the period date rather than testing the function.

### Method note
No research agents this session, a deliberate break from Sessions 3A–3D. The grounding — Texas §182.025/§182.024, §8.201 PSF, §7.45, Tax Code Ch. 151 ad-hoc defaults, the 2026-06-12 residential-taxability review, D6-1/D6-2 — was already in the KB and in `sql/tu.sql`. Reading the schema directly against `canonical-invariants.md` Family 6 is what surfaced all four open items above; none of them are visible from the prose docs alone, because each is a disagreement *between* the schema and a doc. Authorship manual throughout, same as every prior session.

### Next
Session 3F — Domain 6 (billing run, corrections, backbilling), clusters 27–32. None of the six open items above blocks it.

---

## 2026-07-05 — Session: Work Unit 5 completion (Families 14–17) + Work Unit 6 Sessions 3A–3D (Configurable-Rules)

**Status:** WU5 (Method 1 per-invariant scenario docs) is now fully complete — all 17 canonical-invariant families represented across 15 docs. WU6 (Configurable-Rules Sessions 3+) is underway — Sessions 3A through 3D done (Domains 1–4 of 13). Two consolidated Kyle review briefs compiled and awaiting answers. No application code written.

### Done
- **Finished WU5:** drafted axes-of-variation docs for Families 14 (`read-exception-handling-and-estimation.md`), 15 (`tenant-isolation-and-structural-integrity.md`), and 16 (`account-lifecycle-mimo-and-final-bill.md` + `deposits-credits-and-operational-integrity.md`), then ran the **Family 17 fold-in pass**: CI-132 (regulatory posture) into the Family 13 doc, CI-133 (transport eligibility) into the Family 4 doc, CI-134 (batch absolute-baseline mass-error gate) into the Family 14 doc, CI-135 (print-mail PII-breach classification) into the Family 12 doc — closing the deferral every one of the prior 13 family docs had explicitly left open.
- **Compiled `wu5-axes-review-brief.md`** (`gas-billing-memory c042493`): a consolidated, plain-language Kyle-facing brief spanning all 17 families, built by having 5 parallel research agents extract "Next steps" judgment calls from the docs not already in working context, then synthesizing directly. Part A: new judgment calls by family. Part B: the 10 still-open Q-numbers from the WU4 brief, now mapped to the exact doc/axis each blocks. Part C: 2 doc-placement calls.
- **Started and progressed WU6** (Configurable-Rules Sessions 3+, one rule domain per session, per `cluster-and-workflow-inventory.md`'s Part 3 queue) — the first work on this track since the WU3 scoping session:
  - **Session 3A** (Domain 1: Reads, Validation & Estimation) — 6 decision tables (clusters 1–6) + 6 workflows (`gas-billing-memory b0f87fd`).
  - **Session 3B** (Domain 2: Gas Measurement & Consumption) — 4 decision tables (clusters 7–10) + 4 meter-lifecycle workflows (`d830ddd`).
  - **Session 3C** (Domain 3: Rating & Tariff Engine) — 9 decision tables (clusters 11–19, the queue's own largest single domain) + 4 workflows (`2f2bc23`).
  - **Session 3D** (Domain 4: PGA / WNA / Gas Cost Recovery) — 3 decision tables (clusters 20–22) + 3 workflows (`4c97fbf`).
  - Method: for each session, dispatched 3–4 parallel Explore-agent research tasks to ground the drafting (exact schema/catalog column names, named real-world failure incidents, statutory values) before personally authoring every table and workflow file — research was delegated, authorship never was, to keep voice and cross-referencing consistent across 39 files.
- **Compiled `wu6-decision-tables-review-brief.md`** (`1c58a37`): the same consolidated-brief treatment applied to all 39 WU6 files, synthesized directly from the session's own work (no new research needed). Leads with 4 genuine tensions between two sources that both look authoritative, rather than picking a side silently.
- **Found and corrected a stale cross-document status**: `canonical-invariants.md`'s status line and Flagged section still listed Q-3 (WNA deadband scoping) as open, but `de-review-answers.md` shows Kyle resolved it on 2026-06-12 — the invariants-doc update was the action item itself and it never happened. Fixed `canonical-invariants.md` (Q-3 entry, CI-041 upgraded medium→high confidence, top status line), `weather-normalization.md` (the WU5 Family 5 doc, which had inherited the stale status), and `wu5-axes-review-brief.md` (which had incorrectly asked Kyle to re-answer something he'd already resolved three weeks earlier).

### Decisions (and the "why NOT")
- **Family 17's 4 residual invariants folded in one batched pass**, only after all 16 topic families existed. NOT done incrementally as each home doc was drafted, because every fold-in cross-references invariants living in its own home doc — batching avoided rework against still-changing predecessors.
- **The stale Q-3 status was fixed forward**, not left as a note for Kyle to sort out. NOT leaving it, because it was actively producing wrong output — the WU5 brief was asking Kyle to re-answer a question already closed three weeks prior. It surfaced by accident (mid-research for Session 3D's WNA table), which both CHANGELOGs flag as a process gap worth a lighter-weight periodic reconciliation check.
- **WU6's 4 genuine tensions (PGA correction path — cancel-rebill vs. deferred-account; `pga-monthly-trueup`'s possibly-wrong name; the `prorate_tier_breakpoints` schema default contradicting CI-108's own stated invariant default; whether the WNA adjustment needs a floor/ceiling guard) were surfaced explicitly, not resolved unilaterally.** NOT picking a side, because each pits an invariant statement against a named failure-mode description (or a schema default against its governing invariant) with textual support on both sides — a wrong unilateral call would propagate into every downstream scenario derived from these 39 files.
- **Research delegated to parallel Explore agents; authorship was not.** NOT having agents draft the tables/workflows directly, to keep the voice, rigor, and cross-referencing density consistent with the 15 WU5 docs already establishing that pattern.

### Errors caught & resolved (process note, not a code bug)
- **Accidental Agent spawns while waiting on background research.** Used `Agent({prompt: "placeholder"})` several times intending only to trigger a wait-and-resume, which instead spawned 6 real agents that took the literal placeholder text as their assignment and began investigating on their own. Caught immediately; sent stand-down messages to all 6 via `SendMessage`. No output from any of them was used. Lesson recorded in `HANDOFF.md`: end the turn with a text-only update instead — background-task notifications arrive automatically on the next turn without needing a tool call to "wait."

### Open questions for Kyle
- **WU5** (`wu5-axes-review-brief.md`): 9 remaining Q-numbers (Q-1, Q-4–Q-10, Q-12), each now mapped to the specific doc/axis it blocks — headline items are Q-10 (consecutive-estimate counter shape, the single most load-bearing open item across both work units) and Q-6 (Texas disconnect bypass-set completeness, incl. family-violence).
- **WU6** (`wu6-decision-tables-review-brief.md`): the 4 Part-A tensions above are the priority; Parts B–E cover per-session schema gaps (no `meter_skip_reason`/tamper-flag/pressure-class columns exist yet) and scope questions (is sewer billing or government/wholesale rating actually in v1 scenario scope?).

### Next step
Kyle answers both briefs → fold answers in, starting with WU6's 4 tensions since they block the most downstream work → **Session 3E (Domain 5: Taxes & Fees, clusters 23–26)**, which consumes Session 3C's settled rider stack and Session 3D's PGA output as its own inputs per the canonical billing-pipeline order (CI-100). Sessions 3F–3M remain after that.

### Repo state
No commits in `tally-utility` this session; uncommitted here: `HANDOFF.md` (full rewrite), `CHANGELOG.md` (this entry), `TECH-STACK-DISCUSSION.md` (pre-existing, unrelated parallel thread, untouched this session). In `gas-billing-memory`: 15 commits this session (WU5 completion: `0cb783d`, `78035fb`, `23a4ee0`, `0c71016`, `0a4eb05`, `02f1593`, `9070bdb`, `e5a3370`, `c042493`, `3de7242`; WU6 + correction: `b0f87fd`, `84022ae`, `d830ddd`, `594a86f`, `2f2bc23`, `61fa175`, `e3d9536`, `6d5fca6`, `4c97fbf`, `a1faea2`, `1c58a37`, `42f36c9`); HEAD = `42f36c9`; 42 commits ahead of `origin/main`, not pushed; only `Clippings/` untracked.

---

## 2026-06-30 — Session: Work Unit 4 — test fixture catalog (Session 1 draft) + DE-8..11 reconciliation

**Status:** WU4 Session-1 draft complete and committed in `gas-billing-memory`; awaiting Kyle's answers on a combined review brief before Work Unit 5 (per-invariant scenarios). No application code written.

### Done
- **Resumed the WU3 handoff and checked drift:** Kyle had already resolved DE-8..11 (`gas-billing-memory bea5e17`, 2026-06-19) since the handoff was written — the WU3 gate had cleared, changing "Next" from "nudge Kyle" to "proceed to WU4."
- **Reconciliation pass** (`gas-billing-memory f523b06`): the `bea5e17` commit captured DE-9's §7.45 medical semantics only in the inventory's audit sections (Part 4/5), not the Part-1 cluster rows. Threaded action #36 inline into clusters **45** (`program-enrollment-eligibility`) and **46** (`collections-bypass-evaluation`); bumped the stale `updated:` date; backfilled `wiki-ingestion-pending.md` **Section C (C1–C5)** — the WU2-review → WU3 → DE-8..11 history that had gone unlogged.
- **Prerequisite check for WU4:** config catalog DE-reviewed ✅; canonical invariants schema-audited ✅ (flagged-question review is a *soft* gate — open Qs land on post-midpoint entities); schema confirmed at `tally-utility/sql/tu.sql` (the strategy's `application/database/schema.sql` path is stale).
- **Produced the fixture catalog** `gas-billing-memory/application/test-fixtures/` (`c554c69`) — **11 files, 87 fixtures, Texas-only:** jurisdictions (FIX-JUR-001..003, TX-RRC + environs/special-rate markers), customer-classes (FIX-CLASS-001..006, 7-value DE-6 enum), programs (FIX-PGM-001..011, v5.4 `program_types` enum, 6 v1 + 5 seeded), cities (FIX-CITY-001..009, real Texas cities across population/governance/tax/region), tenants (FIX-T-001..006 — municipal ×3, IOU, cooperative ×2), franchise-agreements (FIX-FA-001..007), rate-schedules (FIX-RS-001..014), customers (FIX-C-001..012), service-locations (FIX-SL-001..012), meters (FIX-M-001..008), + an `accounts.md` structural note. Config values pulled from the Layer-1 config-catalog + `tu.sql` (not invented).
- **Method:** ran **4 parallel grounding subagents** (Texas regulatory params, LDC sizing realism, city tax/franchise, programs/collections) while reading the config-catalog + schema directly; synthesized the fixtures in one context to avoid drift.
- **Cross-reference verification walk — clean:** automated sweep confirmed no dangling `FIX-` references and no orphans (caught + fixed one typo, FIX-CLASS-007 → FIX-CLASS-006).
- **Richer franchise coverage** (per Ryan's steer): added **Hill Country Gas Cooperative** (a 2nd, contiguous multi-city operator) + 3 Hill Country cities + 3 franchise agreements — bringing fee-paying operators to two and agreements to 7, spanning rates 1.0–2.0%, four escalation types, and indefinite/superseded/expiring terms.
- **Combined Kyle review brief** (`8b46ea2`, `session-1-review-brief.md`): plain-language fixture questions A1–A8 plus the still-open canonical-invariant flagged questions (Q-1,3,4,5,6,7,8,9,10,12) that gate Work Unit 5. Logged everything as **wiki-ingestion Section D (D1–D14)**.

### Decisions (and the "why NOT")
- **DE-FX-1: proceed assuming Tax Code §182.025 caps the gas franchise fee at 2%** (all `fee_percentage` ≤ 2%). NOT guessing 3–5% (real-world/industry practice) because the DE-reviewed config catalog asserts the 2% ceiling; the conflict is flagged for Kyle (A1) and every rate is tagged `# DE-FX-1` so a reversal is a one-file sweep. Cheap now because nothing downstream consumes the rates until scenario-writing.
- **Grounded to the schema/catalog enums, not the fixture strategy's lists.** 7-value customer-class enum (DE-6) over the strategy's 5 — **transport is a service-type, not a class**; v5.4 `program_types` (11) over the strategy's 9-item program list. Schema + DE-reviewed catalog are authoritative over the older strategy prose.
- **Five entity types modeled as reference fixtures (no backing schema table).** jurisdictions, customer-classes, programs, cities, tax_jurisdictions have no table in `tu.sql` (invariants gaps A-8/A-14; program substrate is v5.4-pending) — so they're enumeration fixtures grounded in regulatory/catalog material, NOT the "fill every schema column" model the strategy assumed.
- **No account fixtures — a structural note instead (DE-FX-9).** There is no `accounts` table; account = `customers.customer_number` + `service_locations`, and balance-state ("in collections", "written off") is a *ledger* condition (per-scenario transaction seed), not fixture data. NOT inventing an accounts table.
- **Only the IOU + the Hill Country co-op pay franchise fees.** A municipal utility serving its own city pays none (it *is* the city); the environs-only co-op has no city. Realistic, and thinner than the strategy's "~12 agreements" guess — resolved by adding a 2nd multi-city operator rather than fabricating franchise fees for the munis.

### Errors caught & resolved (research contamination)
- The parallel grounding subagents (fresh LLM research) re-introduced two errors already corrected in project canon: framing **deposit interest as a "PUCT rate"** (it is statutory, TUC §183.002 — gas is RRC/municipal, never PUC) and citing a **"12-month" backbilling cap** (that is the PUC *water* rule §24.165; gas is per-cause — non-registering 3mo / rate-misapplication 6mo / meter-error 6mo-or-since-last-test / tampering uncapped). Both caught against the config-catalog/invariants and corrected in `jurisdictions.md` before writing. Lesson recorded in HANDOFF: don't trust fresh LLM research on Texas gas regulation over the DE-reviewed catalog.

### Open questions for Kyle (the gate — in `session-1-review-brief.md`)
- **A1 (headline)** — §182.025: is the 2% a franchise-fee cap, or a distinct street-use charge that lets the franchise fee exceed 2%?
- **A2–A8** — special-rate-area reality; customer-class enum confirmation; medical-hold duration (20 days vs. unstandardized); PIPP scope; city tax-rate representativeness; franchise coverage depth; balance-state as ledger seed.
- **Part B (gates WU5)** — invariant Qs: WNA-deadband placement (Q-3), bypass-set completeness + family-violence (Q-6), estimate-counter shape (Q-10), adjacent-domain launch scope incl. submetering (Q-12), plus payment-earmarking (Q-5), bilingual county scope (Q-8), concurrent bi-temporal edits (Q-1), CIS scope boundaries (Q-4/Q-9), AMP forgiveness (Q-7).

### Next step
Kyle answers the combined review brief → fold answers into the catalog (sweep the tagged franchise rates if A1 flips) → **Work Unit 5 (Method 1 per-invariant scenario docs)**, referencing these fixtures by ID. Per the kickoff's review cadence, WU5 drafting *may* start in parallel on invariants whose framing is already locked.

### Repo state
No commits in `tally-utility` this session; uncommitted here: `HANDOFF.md` (full rewrite for WU4), `CHANGELOG.md` (this entry), `TECH-STACK-DISCUSSION.md` (pre-existing, parallel thread). In `gas-billing-memory`: three commits this session — `f523b06` (reconciliation), `c554c69` (fixture catalog), `8b46ea2` (review brief); HEAD = `8b46ea2`; only `Clippings/` untracked.

---

## 2026-06-18 — Session: Work Unit 3 — cluster & workflow inventory (Layer 2/3 scoping)

**Status:** WU3 draft complete; gated on domain-expert answers (DE-8..11) before the per-domain build sessions. No application code written. Deliverables committed in `gas-billing-memory` `fe6b464`.

### Done
- **Executed Work Unit 3 = Session 2** (Layer 2/3 scoping) of the configurable-rules strategy, the step after Kyle's WU2 config-catalog approval (`de-review-answers.md`, DE-1..7 + 32 action items, 2026-06-12).
- **Ran five systematic coverage walks** (the Session-2 completeness-gate dimensions) against the source corpus: pipeline-stage (19 feature-list stages), schema-column (213 cols + 56 JSONB sub-keys), failure-mode (~175 failures across 9 billing-failure stages + cross-cutting), persona (5 roles), and catalog cluster-seeds (125 catalog entries — override chains, regulated entries, intended-config + gap-list, classification inputs).
- **Produced `gas-billing-memory/application/configurable-rules/cluster-and-workflow-inventory.md`** — the canonical work queue replacing the strategy's provisional starters: **42 decision-table clusters** in 13 rule domains, **51 workflows** by area (integration ones tagged `[split-with-addenda]`), a **Sessions 3+ work queue** (3A reads → 3M import/admin), and an **inline completeness audit** of all 6 dimensions (each marked covered / folded / out-of-scope with rationale). Net vs. the ~25-cluster starter: kept 22, merged/renamed 3 groups, added 17.
- **Threaded Kyle's 32 action items** into the clusters they touch (per-cause §7.45 backbilling, working-day dunning clocks, per-service late-fee scoping, `agency_pledge` protection type, postmark timeliness, effective-dated deposit-interest table, per-type escheatment dormancy, gas `correction_rate_mode` historical guard, DE-4/5/7 schema consolidations).
- **Wrote `cluster-workflow-review-brief.md`** — a plain-language brief so Kyle can answer the four open questions without opening the dense inventory (same pattern as `catalog-review-brief.md`).

### Decisions (and the "why NOT")
- **WU3 deliverable is tables/stubs, not full specs.** Session 2 is a *scoping* session by strategy design — it enumerates what to build and proves coverage; the actual DMN decision tables and Cockburn workflow specs are Sessions 3+. NOT writing specs now — the strategy's stated dominant failure mode is jumping feature→scenario without first naming the rule and confirming nothing's missing.
- **Stages 16 (reporting) and 19 (implementation) get NO rule cluster, by design.** Reporting = outputs/queries not configurable decisions; implementation = professional-services/cutover not product runtime. Documented as out-of-scope — the gate requires an explicit reason, not silence.
- **`absolute-baseline-qa` elevated to a mandatory cluster.** The "whole batch wrong by the same amount" blind spot (Hydro One, PGW 2022, Central Hudson) had no home in the starter and is the single highest-value missing control.
- **Medical-hold handling = data-migration/UAT concern, not a runtime configurable rule.** It's a drop-on-cutover data risk, not a decision; flagged as DE-9 for Kyle to confirm.
- **Separate plain-language brief for Kyle** rather than sending the inventory — he needs only 4 bounded judgment calls; the inventory is an engineering checklist.

### Scoping corrections applied (not failures)
- The failure-mode walk over-indexed on **multi-state** regulation (MN/IL/OH/NY caps, cold-weather windows) and treated CIS-go-live / parallel-run / DB-lock dashboards as decision clusters. Both corrected in synthesis: launch is **Texas-only** (§7.45/§7.460; multi-state is a deferred Layer-4 parametric axis), and implementation/ops governance is out-of-scope for the configurable-rules corpus. Recorded inline so it isn't re-litigated.

### Open questions for Kyle (the gate — DE-8..11)
- **DE-8** — four edge-case tasks in for v1 or deferred: vacation/seasonal hold, account split, customer credit transfer.
- **DE-9** — confirm medical-hold migration is handled as a data-conversion/go-live checklist item, not a live engine rule.
- **DE-10** — are the `absolute-baseline-qa` thresholds (cycle revenue ±2%, class-avg-vs-prior-year ±5%, canary ±3%) right for Texas gas, or tenant-tunable?
- **DE-11** — confirm AI features + portal *build* deferred (nice-to-have), with the usage+temperature graph kept for v1.

### Next step
Kyle answers DE-8..11 → fold answers into the inventory → **Work Unit 4 (fixture catalog)** → **Sessions 3+** produce the actual decision tables + workflow specs, one rule domain per session per the Part 3 queue.

### Repo state
No commits in `tally-utility` this session; uncommitted here: `HANDOFF.md` (full rewrite for WU3), `CHANGELOG.md` (this entry), `TECH-STACK-DISCUSSION.md` (pre-existing, parallel thread). In `gas-billing-memory`: WU3 files committed `fe6b464` ("Adds workflow intermediate step"); only `Clippings/` untracked.

---

## 2026-06-07 — Session: Tech-stack decisions — locked 5 of 6 axes

**Status:** Tech-stack discussion (parallel thread). Five axes locked, one deferred. No application code written. All decisions recorded with full rationale in `TECH-STACK-DISCUSSION.md` decisions log; this entry is the summary.

### Decisions locked (each with the "why" in the decisions log)
- **A. Tariff / rate engine = data-driven config + a typed, decimal-only calc core.** Engineers build a rich, composable charge-type library once (`FIXED`, `TIERED_VOLUME`, `PASSTHROUGH_RATE`, `PCT_OF_BASE`, `WNA_ADJUSTMENT`, demand/ratchet, min/max riders); billing staff operate it via forms as date-effective data writes; **all arithmetic runs in one linted core, never in tenant input.** Tiny pure decimal-only DSL held *in reserve* for the rate-math half only, if the vertical slice proves the vocabulary too rigid. DMN decision tables handle rule *selection*; charge-type library handles rate *math*.
- **B. Language = C#/.NET for engine + API; TypeScript/React for portal.** Strict .NET (nullable refs on, analyzers + warnings-as-errors), pure I/O-free calc core, typed frontend client generated from .NET's OpenAPI output. **Vertical slice doubles as Ryan's C# ramp** (he has TS experience, no prior C#).
- **C. Data access = raw SQL + Dapper over Npgsql. No heavy ORM.** Consequence of B + bi-temporal architecture; must work *with* range types, RLS, four-column bi-temporal predicates, linked snapshot tables.
- **High-level architecture = modular monolith + pure calc core.** One deployable, one transactional Postgres, strong in-code module boundaries; worker-extraction seams (batch-billing, EDI gateway, doc generation) pre-drawn but not cut. Microservices off the table until a real independent-scaling/many-teams axis appears.
- **D. Tax = build in-house for Texas-only launch; clean Tax-module seam for a hybrid commercial engine at multi-state.**

### Why NOT the alternatives
- **NOT a DSL or embedded scripting for tariffs (A).** Scripting fails determinism/auditability and **can't enforce float-leakage discipline inside tenant code** (kills exact-decimal constraint); a DSL re-imposes language-authoring on routine rate changes (breaks the "staff change rates, no consultant" positioning) and adds parser/type-checker/versioning burden for expressiveness the bounded gas-tariff domain rarely needs.
- **NOT all-TypeScript (B).** No native decimal → money math runs through an allocating userland lib (`decimal.js`) that LLMs can silently bypass with raw `number` arithmetic (no compile error). C#'s native base-10 `decimal` makes the worst LLM error in this domain *uncompilable*; the compiler is the load-bearing safety net when LLMs write most of the code. All-TS pays a permanent decimal-discipline tax to avoid a one-time, front-loadable C# ramp.
- **NOT microservices (architecture).** DB-per-service shatters atomic bills + bi-temporal consistency into sagas/eventual-consistency against requirements that demand strong consistency; small team pays the ops tax with no org-scaling benefit; load is batch + horizontally scalable across independent tenant runs.
- **NOT buying a tax engine at launch (D).** Franchise fees + regulatory assessments aren't modeled by commercial engines (built in-house regardless → never a clean buy); the engines' crown jewel (situsing) is nearly free for a defined-territory utility; per-transaction pricing × every line × meter × tenant × month threatens platform unit economics; bi-temporal as-of-historical reproducibility fights the "today's answer" API model. Texas tax is ~90% the data-driven charge-type + bi-temporal-rate machinery already being built. Revisit buy (hybrid) at multi-state.

### Deferred
- **E. Testing approach — deferred to when scenarios exist (Layer 4) and the build is closer to testing.** Carry-forward open questions documented in `TECH-STACK-DISCUSSION.md` axis E: scenario→test mechanics + fixture shape; property-based (invariants) vs. example-based (named fixtures); golden-master/snapshot for cancel-rebill reproducibility; clock-injection mechanism. Tooling now constrained by B: CsCheck/FsCheck (property) + xUnit (example/golden-master).

### Process note
- Ryan prefers tradeoffs worked as prose discussion, not `AskUserQuestion` menus (saved to project memory). Entertained and explicitly rejected DSL/scripting (A) and all-TS (B) before locking.

### Next step
Tech-stack thread is paused with E as the only open axis; resume it alongside scenario work. Main project track continues independently at Work Unit 2 (configuration catalog). No tech-stack work blocks Phase 2.

### Repo state
No commits this session. Edits to `TECH-STACK-DISCUSSION.md` (decisions log filled: A/B/C/architecture/D; status header updated; E marked deferred) and `CHANGELOG.md` (this entry). New project memory: `prefers-discussion-over-canned-options.md`.

---

## 2026-06-07 — Session: Orient on domain-expert audit; plan Phase 2; create tech-stack pickup doc

**Status:** Planning/discovery session — no application code written.

### Done
- **Mapped the real project state.** Authoritative knowledge + planning now lives in `/Users/ryanscomputer/code/gas-billing-memory/` (not this repo; the old `LLM-wiki/projects/TallyUtility/` path is gone — wiki moved to `LLM-wiki/wiki/projects/tally-utility/`).
- **Characterized the domain-expert audit.** Author: **Kyle Shaffer** (`kyle.shaffer@centric-us.com`), single commit `dcc4f67` (2026-05-29). New artifact `application/invariants/gap-analysis-v5.2.1.md` (1,347 lines) audits all 17 invariant families against the v5.2.1 schema; produced **40 "doc drift" findings** (predominantly the invariants doc *underselling* what the schema already enforces; plus a few real gaps and wrong table names — e.g., `work_orders`→`service_orders`, `service_agreements` doesn't exist).
- **Logged question resolutions.** Kyle resolved **3 of the flagged questions**: Q-2 (`account_ledger.running_balance` → stamp-at-insert via `compute_ledger_running_balance` trigger; CI-019 upgraded), Q-11 (tenant read-isolation → Postgres RLS; CI-116 upgraded to `structurally-enforced`), Q-13 (new — multi-program enrollment → `customer_program_enrollments` + `program_types`, drop single-column `disconnect_protection_*`). **10 remain open:** Q-1, Q-3, Q-4, Q-5, Q-6, Q-7, Q-8, Q-9, Q-10, Q-12.
- **Created `TECH-STACK-DISCUSSION.md`** (repo root) — a self-contained pickup doc for the parallel tech-stack thread: methodology frame, domain constraints (decimal money, determinism, Postgres-native, testability, auditability), five decision axes (tariff engine flagged resolve-first), open questions, empty decisions log.
- **Rewrote `HANDOFF.md`** to reflect actual current state (was a stale 2026-05-14 bi-temporality "Session A" handoff pointing at a decision already made and a dead KB path).

### Decisions (and the "why NOT")
- **Specification-first / waterfall on the regulated "what."** Requirements are externally fixed by regulation, so spec fully before building. NOT agile — agile's "discover requirements via iteration" bet is wrong for regulated billing.
- **Iterate the architectural "how"** (tariff engine, snapshot shape, stack) — regulation doesn't determine these; keep them empirical until a slice proves them.
- **Vertical slice proves the format before mass production.** Run the gas-pipeline spine end-to-end first (read→consumption→BTU/pressure→PGA→WNA→rate→immutable bill+snapshot) to validate scenarios→fixtures→tests→engine compose, then fan out. Avoids re-formatting ~350 features of specs.
- **Fixtures derive from scenarios, never from the engine** — engine-derived fixtures are circular and can't catch bugs. Slice teaches fixture *shape*; content comes from the spec.
- **Defer most drift reconciliation.** Config catalog reads schema + feature list directly (invariants only a soft prerequisite), so the ~37 annotation-level drift items ride with schema hardening; only the 3 domain-level findings (CI-064, CI-037, Q-13 model) fold in before Phase 2.
- **Next step is Work Unit 2 (config catalog), not scenarios directly** — per `execution-kickoff.md` the four-layer pipeline puts scenarios last (Layer 4), after catalog → decision tables → workflows → fixtures.

### Wrong assumption corrected (don't repeat)
- Claimed Kyle audited a separate **"de-Supabased v5.2.1 schema dump"** that needed locating, and made it a Phase-2 blocker. **Wrong:** misread two layers of the same file as two files. `tu.sql` *defines* the wrappers `get_user_tenant_id()` (line ~535) and `is_platform_admin()` (line ~570); their bodies call `auth.uid()`. RLS policies call the wrappers, not `auth.uid()` directly. **`tu.sql` v5.2.1 is the single canonical schema.** De-Supabasing = swap `auth.uid()` in those two function bodies (deferred to schema hardening). Also: the v5.3/v5.4 patches referenced in docs **do not exist as SQL** anywhere.

### Next step
Fold the 3 domain findings into `canonical-invariants.md`, then open Work Unit 2 — create `gas-billing-memory/application/configurable-rules/configuration-catalog.md` and run the Layer 1 inventory against `tu.sql`. Tech-stack discussion proceeds in parallel via `TECH-STACK-DISCUSSION.md`.

### Repo state
No commits this session. Uncommitted in `tally-utility`: `HANDOFF.md` (rewritten), `sql/tu.sql` (`auth.users` FK removed in prior edit), untracked `CONTEXT.md`, `TECH-STACK-DISCUSSION.md`, `application/`, `.idea/`. `gas-billing-memory` clean (HEAD `dcc4f67`).
