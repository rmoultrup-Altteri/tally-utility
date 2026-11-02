# Audit B: the last 15 scenario docs, checked against the rulings since 2026-10-13

Built 2026-11-02, read-only. Docs: `gas-billing-memory/application/invariant-scenarios/`. Rulings: `rulings-digest.md` (same scratchpad). Grades quoted from `tally-utility-scenarios/application/invariant-parity-measurement-2026-10-13.md` where they explain a change.

## The finding that applies to all 15

**None of these docs contains a scenario.** Every one stops at "axes of variation": the dimensions a scenario would vary along, waiting for Kyle's review (Method 1, step 1 of 6). There are no worked bills, no account histories, and no dollar amounts a domain expert could check. A few axes quote statutory figures ($15 meter-test fee, 32 °F, 35 days, a $1.00 cap), and several of those figures have since changed or turned out to be per-jurisdiction rule values. In the sections below, "scenarios" means axes (A1, A2, …).

Kyle reviewed the axes on 2026-07-10, and those answers are folded in (the D-numbers). Everything below is about what changed **after** 2026-10-13.

Three standing rules reach almost every Texas-titled doc:
- **City-owned gas systems are outside the Texas gas utility law.** 16 TAC ch. 7, §7.45, §7.460 and Utilities Code ch. 104 do not bind them, and they are our first customers. Their policy is whatever the city's tariff says, entered per utility with no assumed defaults. If a city has no tariff row on a topic, it has no rule there.
- **Texas is data, not code.** Every Texas figure becomes a dated law row with a citation, keyed by jurisdiction, and attached per service location where the rules differ inside and outside city limits.
- **The utility owns its regulated values.** The platform stores the utility's rate, factor or fee. It keeps the legal value only as a reference and reports any discrepancy.

---

## 1. payment-allocation-and-posting

**Covers:** CI-049 (allocation follows a rule), CI-050 (regulated charges paid first), CI-054 (late fees and their exemptions), CI-058 (a payment's effective date). 13 axes, 0 scenarios, abstract.

**What has changed under it:**
- **A1, base posting order.** It offers "oldest-first (Texas per 16 TAC), current-first, specific-priority/hybrid" as alternatives. Kyle (K-05, 10-15) fixed **oldest bill first** across bills. Order *within* one bill is the jurisdiction's or tariff's rule data, and Kyle found no statewide Texas order, so "Texas per 16 TAC" is wrong. The tenant ordering options `newest_first`, `largest_first`, `manual_only` and "apply to specific invoices" are retired. **Reversed.**
- **A2, payment class.** It rests on the 07-10 ruling (D7-1): customers can never designate a payment, and a "for deposit" memo is left to the operator's judgment. K-05 (10-15) now lets a customer designate a payment **as a deposit or as a bill**, and nothing finer. Agency payments that carry a restriction come in -24. When such a restriction conflicts with the regulated-first floor, the database records which won, but **who should win is not ruled** (10-16, open for Kyle). **Narrowed, with one part still open.**
- **A3, disputed and program-protected amounts "skipped" in allocation.** Since 10-18 a dispute protects the disputed *amount* through a determination the core writes, not through the allocation order. No ruling says allocation skips disputed lines; the rule is oldest bill first, each line capped at its open balance (R-06). The scenario needs re-deriving against -25. **Narrowed or unsettled.**
- **A4, manual override.** Confirmed and made concrete: every application records `oldest_first` or `operator_override` with a reason and a user, and a wrong application is undone by a negative application that names it (wave 2, 10-15). It is stored **per bill line**, not per invoice. **Narrowed.**
- **A5 and A6, regulated versus unregulated.** The doc puts the class on charge definitions (the 07-10 ruling, D7-2) and drafts both a "gap state" and a "target state". Since 10-16 **each bill line carries its own class**, and regulated-first is a fixed term that no tariff row can turn off. The A5 case "customer earmarks the payment to unregulated charges" no longer exists, because customers cannot earmark (K-05). The gap-state framing in A6 is obsolete. **Reversed in part.**
- **CI-054 and A8 to A10, late fees.** The doc names `invoices.late_fee_assessed` and `late_fee_amount` as the place late fees are recorded. Both are **dropped** and derived from late-fee charges (wave 3, E7). The late-fee rate, base, cap, grace period and exempt programs are **dated law or tariff rows with a citation** (Kyle R-11, 10-15). A late fee must cite a collections decision of "eligible" covering its date, and a missing input yields "unevaluable", which blocks the fee (wave 3, E1 to E5). A city with no late-fee tariff row charges no late fee. The 60-and-over due-date delay (§182.002: due date 25 days after issue, no late fee) **binds city systems**. It is pending Kyle and is missing from A8 and A9. **Reversed or narrowed.**
- **CI-058 and A9, A11 to A13, effective date.** Money counts from its arrival date (an ACH dated the 5th and settled the 8th counts from the 8th) for what can be drawn from a payment (10-21, round 3). A hold on refunds during a check or ACH return window is **tenant policy, off by default** (Kyle K-10 Q3, 10-21). Patch -19 added a write-once `effective_date` and `effective_date_method`. Postmark versus receipt per jurisdiction is still unruled. **Narrowed.**

**Texas-only assumptions:** A1's "Texas per 16 TAC" order; the CI-049 jurisdiction line "Texas applies oldest-first per 16 TAC".

**Verdict:** **revise (heavy).** 9 of 13 axes are affected. Families still changing: **cash (-23, -27, -24 for suspense and pledges)**, **collections (-26)** for late fees, and **disputes (-25)** for A3 and A8.

**Open questions the rulings have answered (close these):**
- Next step 3 (draft A8's exemption sources jointly with Family 8): exemptions are dated rule rows (R-11), and enrollments keep a dated status history (R-07).
- The CI-049 status note that "the rule that produced the allocation isn't recorded": each application now records `oldest_first` or `operator_override`.
- Q-5 / D7-1 is superseded by K-05 (deposit-or-bill designation only).

---

## 2. payment-intake-channels-and-reversal-handling

**Covers:** CI-051 (no card numbers stored), CI-052 (bank-return codes), CI-053 (unmatched cash), CI-055 (no duplicate postings), CI-056 (pledge and suspense deadlines), CI-057 (bank-detail change notices). 16 axes, 0 scenarios, abstract.

**What has changed under it:**
- **A3 and A4, bank-return handling.** "Re-debit" is a **new payment**: a re-presented check or re-sent draft is a new receipt, and its link to the original is optional (Ryan, 10-14 and 10-28). A bounce names its reversing ledger entry, and status only moves forward (wave 2 Q1, 10-15). Payment statuses are pending, posted, nsf, reversed and voided; there is no "refunded" (Ryan, 10-21). A bounce is capped at the payment less earlier reversals, and refunds do not reduce that cap (Kyle K-10). A bounce is **refused while a refund of that payment is pending**, until an operator cancels the refund (K-10 Q2). A bounce's shortfall uses up the customer's whole credit balance, and the customer owes the rest (Kyle K-11, 10-30). **Narrowed. New cases are needed: refund-then-bounce, and bounce-with-credit.**
- **A5, returned-payment fee.** The fee is a one-off charge with a reason code (R-01), and it is allowed only where a tariff row allows it. There is no default. **Narrowed.**
- **A6 and A7, suspense.** Consistent with the rulings, but it moved to patch -24 (Ryan, 10-16). Suspense is resolved by a payment that names it, or by a refund. The "payments.account_id NOT NULL" gap the doc describes is what -24 changes. **Narrowed in timing.**
- **A10 to A12, pledge deadlines and pausing disconnects.** Pledges come in -24. The "pause" is now a collections decision recording "blocked", or "unevaluable" when an input is missing, and an unevaluable decision blocks (wave 3, E1). **Narrowed.**
- **A16, superseding bank details.** Consistent with the add-only rule (R-05), though not ruled directly.
- **CI-051, card numbers.** Masking is still open with counsel. Not answered.

**Texas-only assumptions:** none. The doc is NACHA-based and universal. The pledge deadline (CI-056) already varies by jurisdiction.

**Verdict:** **revise (light to heavy; about 6 of 16 axes).** I would call it heavy for A3 to A5, because the refund and bounce rules are the most worked-out cash rules there are. Family still changing: **cash (-23, -27, -24)**.

**Open questions answered:**
- Next step 4 (draft A6 and A7 against the target design now, or wait?): wait. Suspense comes in -24 with the rule above.
- A3 (R01 "one re-presentment"): a re-presentment is a new payment.
- A12 (how the disconnect pause is represented): a collections decision.

---

## 3. pga-and-commodity-pass-through

**Covers:** CI-033 to CI-037 and CI-133 (the gas-cost factor, its proration, future dating, the deferred account, exempting transportation customers, transport eligibility). 17 axes, 0 scenarios, abstract.

**What has changed under it:**
- **The doc's "defining property" is reversed.** It says gas-cost corrections flow through the deferred account, never through cancel-rebill. Kyle (Q6, 10-14) ruled the platform is **billing side only**. It keeps every approved factor, so a rebill uses the factor in effect then, plus billed gas-cost revenue and volumes per period for export. Gas purchases, the deferred balance, carrying cost and the annual true-up are **not platform records**.
- **A1, unaccounted-for gas against the cap.** The cap is **out of scope**; the utility applies it before filing its factor (Kyle Q7, 10-14). **Reversed.**
- **A2, margin hidden in the factor.** The factor is the utility's own value, and the platform cannot see gas cost. Only the "downstream rounding adds margin" leg survives, and it is governed by the rounding rule (Kyle K-06: four decimals, half-up to the cent). **Narrowed.**
- **A6, the Texas Railroad Commission's monthly filing cadence.** It is presented as Texas's rule. City systems set their own factor, with no Commission filing; the cadence is per-utility data. **Narrowed.**
- **A7 and A8, deferred balance direction and carrying cost; per-class true-up.** Not platform records. **Reversed.**
- **A9, "cancel-rebill to fix gas cost is rejected".** Wrong framing now. A rebill replays the historical factor, and over- or under-collection is reconciled in the utility's accounting. **Reversed.**
- **A10, A11 and A16, transportation customers.** Internal terms are "sales service" and "transportation service", with a per-jurisdiction label table; FT, IT and NGVFT are labels (Kyle K-04). A gas rider line carries **no commodity rate**; the commodity rate lives on the usage line (Ryan, 10-14). **Narrowed.**
- **A14, A15 and A17, moving a customer onto or off a transport schedule.** A customer's rate assignment is a **dated, add-only history with no overlaps** (Kyle R-09), so the "silent field flip" failure in A15 is replaced by a structural rule. **Narrowed.**
- **A3 to A5, proration and future-dated factors.** Not contradicted. Each usage line now carries its own rate and service period (R-01).

**Texas-only assumptions:** CI-035's "Texas RRC: monthly, filed by last business day"; A1's state cap. For a city-owned system the city council sets the gas-cost factor, and nothing in the Railroad Commission's process applies.

**Verdict:** **revise (heavy), close to a rewrite for CI-033 and CI-036.** 11 of 17 axes are affected, and the opening framing is reversed. Family still changing: **gas cost (rates, -28)**. The measurement grades CI-033 and CI-036 as BLOCKED, and the register text needs rewriting.

**Open questions answered:**
- Next step 2 (A9 stated jointly with cancel-rebill): answered by Q6.
- The CI-036 "deferred account gap": out of scope (the platform keeps billing records only).
- Next step 3 (the A12 transport-schedule gap): terms answered by K-04 and the assignment history by R-09. The structural check is still a gap (CI-037 graded GAP).

---

## 4. read-exception-handling-and-estimation

**Covers:** CI-112 to CI-115 and CI-134 (read validation gate, the cap on consecutive estimates, the true-up method, the pre-mail gate, the batch-level baseline gate). 21 axes, 0 scenarios, abstract.

**What has changed under it:**
- **A8, "the universal default cap value".** There are no assumed defaults: the cap is dated rule data with a citation (R-11, Kyle 10-15), and a city with no row has no cap. **Reversed.**
- **A9 and A10, the true-up method per jurisdiction.** It becomes a rule row with a citation (R-11). A replacement reading carries a reason code such as "estimate trued up" (Kyle K-03). The A9 question (the method in force at true-up time, or when the estimate was made?) is still open. **Narrowed.**
- **A2, resolution reason codes.** These now come with K-03's required reason on a replacement read. **Narrowed.**
- **A7, cross-reference to the Texas six-month read cadence.** That rule is §7.45, which does not bind city systems (see doc 10). **Narrowed.**
- **A13 and A14, the pre-mail gate.** Ryan (10-14) drew the line at **posting, not mailing**: once a bill is posted the customer owes, delivered or not. Voiding a held, never-issued bill posts nothing. So a gate that holds a bill *after* posting does not stop the debt, and the scenarios must hold bills before issue. **Narrowed.**
- **A18, comparing the batch to "the commission-approved revenue requirement".** City systems have no commission revenue requirement; their council sets rates. The baseline has to be per-utility data. **Narrowed.**

**Texas-only assumptions:** A7's Texas cadence; A18's commission baseline (investor-owned utilities only).

**Verdict:** **revise (light; about 6 of 21 axes, on the 25% line).** Family still changing: **reads and meters (-28)**. The rulings (R-18) list reads as written after mirror.

**Open questions answered:**
- A8: no default; it is rule data.
- Next step 2 (wait until the Texas cadence framing is stable): it changed, because cities are outside §7.45.
- Still open: A6 (who may grant an over-cap override) and A9 (which method's timing applies).

---

## 5. read-pipeline-and-supersede

**Covers:** CI-025 (read type), CI-030 (superseding a read), CI-031 (a read locked to a billing period). 8 axes, 0 scenarios, abstract.

**What has changed under it:**
- **A3, why a read is superseded.** A reason code is **required** (estimate trued up, meter swap, misread) and the old read is marked superseded, not edited (Kyle K-03, 10-15). The A3 reason "customer disputes the read" now belongs to a **dispute record**: read disputes become dispute rows, and `meter_readings.dispute_*` retire (wave 3, D8, 10-18). **Narrowed or reversed.**
- **A2, the void_released bypass ("nothing objects").** Closed by schema patches -19 and -20: a read's values are frozen whenever `billing_period_locked` is true, `void_released` included, and the void carve-out is narrowed and sealed (measurement, CI-025 and CI-031). Before the lock a read is still editable (-19, R3). This is a schema fact, not a ruling, but the axis now describes a closed hole. **Stale.**
- **A6.** It still says D3-2's v5.4 trigger extension is pending; the doc's own 08-13 correction struck it. It is internally inconsistent. **Stale.**
- **A7, a locked-read correction leading to cancel-rebill.** The correction invoice must name the invoice it replaces, and that invoice must be void (Ryan, 10-14). Voiding a posted bill reverses only what is left of its charge (wave 2, X3). **Narrowed.**
- **A8.** It says the work is "gated by open Q-10", but Q-10 was answered 07-10 (D14-1: counted per meter, reset only by a validated actual read). **Stale.**
- Related: meters have a **dated install history per location** (Kyle R-10), so "meter swap" as a supersede reason sits on that history.

**Texas-only assumptions:** none.

**Verdict:** **revise (heavy by count, 5 of 8 axes, but mostly mechanical).** Family still changing: **reads (-28 and later)**.

**Open questions answered:**
- Next step 1 (flag the `read_type` lock gap as a schema finding): withdrawn, and the remaining hole is closed by -19 and -20.
- A8 (estimate streak): answered by D14-1.
- Still open: Next step 3 (fold this doc into meter-and-premise?).

---

## 6. regulatory-cost-recovery-surcharges-texas

**Covers:** CI-038 (the pipeline safety fee). 7 axes, 0 scenarios, abstract.

**What has changed under it:**
- **CI-038's "$1.00 per service" cap, and A1, the cumulative cap.** Kyle (K-04, 10-15): **there is no fixed cap.** The current §121.211 limits total fees to program cost, and the Commission sets the amount by rule (§8.201). The fee is a dated rule with an amount, a basis (per customer or per service line), billing timing, a citation and an optional recovery-report deadline. One 2024 tariff shows **$1.22 per customer**, and the amount must be confirmed against §8.201 before loading. **Reversed.** The schema still has `regulatory_surcharge_rules.cap_per_service` (-07, -08); check that against K-04.
- **A2 and A3, billing timing.** D4-1 (07-10) said "no timing machinery, operator guidance only". K-04 makes **billing timing a field of the rule**, and adds a recovery-report deadline (one tariff: within 90 days of the last cycle billed). **Narrowed.**
- **A5, keeping the fee out of tax bases.** Confirmed for the franchise fee: the franchise fee is a percentage of all billed lines **except** the pipeline safety fee (Kyle Q2, 10-14). Every charge must **declare** its tax status, with no default (Q5). So the fee's exclusion from sales tax and gas-utility tax is a declared status on the charge, not an implied exemption. **Narrowed.**
- **A6, the "gap state is permanent" framing.** The cap is no longer a candidate for enforcement. **Reversed.**
- **A7, a placeholder for the general pattern.** K-04's rule shape is that general pattern. **Answered.**
- **A4, the state-agency exemption.** No ruling. The column `exempts_state_agencies` exists.

**Texas-only assumptions:** the title and "jurisdiction: texas". Under the standing rule this is a per-jurisdiction surcharge rule whose first row is Texas §8.201. **Check before writing:** whether §121.211 and §8.201 reach city-owned systems. Pipeline-safety law is federal-derived and may cover all distribution operators, unlike chapter 7; the digest does not say.

**Verdict:** **revise (heavy; 6 of 7 axes).** Family still changing: **rates and tax (-28)**.

**Open questions answered:**
- Next step 4 ($1.00 or $0.50 cap?): neither; there is no fixed cap (K-04).
- A1 (does the cap follow the service or the customer?): the basis is per customer or per service line, as rule data.
- A3 (multi-year late recovery): partly answered by the optional recovery-report deadline.

---

## 7. reversal-lineage-and-chain-discipline

**Covers:** CI-017 (every reversal names what it undoes), CI-018 (reversal chains), CI-019 (the ledger's running balance). 7 axes, 0 scenarios, abstract.

**What has changed under it:**
- **CI-019 as a whole, and A5 and A6.** The stored running balance is **dropped** (Ryan, 10-13). The balance is the sum of the customer's ledger rows as of a date and a recorded instant (`account_balance_as_of(customer, on, recorded)`, -19). A6's "caller reads `running_balance` directly" and A5's stamp-at-insert stress cases are moot. A back-dated insert is now governed by period rules: a closed period never reopens, and money dated inside a closed period is refused (-22 drafting, 10-15). **Reversed.**
- **CI-018, "unbounded", and A3.** A correction chain is capped at **1,000 deep**; past that, the correction posts as a new unlinked entry (Ryan, 10-17). Reissue chains are capped at 999 (10-29). The 07-10 "depth over 3 raises an event" (D1-3) survives only as monitoring. **Reversed.**
- **A1, the kinds of reversal.** It lists "refund (`refunds_payment_id`)" as a payment reversal. A **refund is not a reversal**: it is its own movement of money, with its own cap (Kyle K-10, 10-21). It names exactly one source, the payment or the customer credit (Ryan, 10-14). A meter-read void becomes a read supersede with a reason (Kyle K-03). Voiding a **never-posted** bill posts nothing (Ryan, 10-14). **Reversed in part.**
- **A4, reversing something already reversed.** Answered: reversals against an entry total **at most the entry** (Kyle R-02), so a partial second reversal is allowed and over-reversal is impossible. A void reverses only what is left, and a charge already fully reversed voids with no ledger row (wave 2, X3). **Answered.**
- **A7, a back-dated insert across a bankruptcy split.** No ruling.

**Texas-only assumptions:** none.

**Verdict:** **rewrite.** 6 of 7 axes are affected, and one of its three invariants (CI-019) is gone as framed. Family still changing: **cash (-23, -27)** for refund and bounce lineage.

**Open questions answered:**
- A4 (is a second reversal rejected, redirected, or a parallel link?): R-02 with wave 2 X3.
- Next step 3 (draft A6 first): moot.
- Next step 2 (which doc owns chain depth): the depth cap is now 1,000. Ownership is still open.

---

## 8. taxes-franchise-fees-and-gl-posting

**Covers:** CI-044 to CI-048 (franchise fee traced to its city, the tax stack and its bases, exemption certificates, assigning a premise to jurisdictions, mapping charges to GL accounts). 16 axes, 0 scenarios, abstract.

**What has changed under it:**
- **A1 to A3, assigning jurisdictions.** A tax jurisdiction is a **place**, and a service location links to **every** jurisdiction it sits in (Kyle Q1, 10-14). Service locations never change (R-10), and memberships are dated, with evidence required. Rates come from the Comptroller's quarterly files through a staged job, and **none goes live without an operator's sign-off** (Q1). The flags `service_locations.inside_city_limits` and `franchise_city` are superseded. **Narrowed.**
- **A4 to A6, tax types and bases.** The franchise fee is a percentage of all billed lines except excluded ones, and it is **not in the sales-tax base** (Q2). The base type is picked per jurisdiction from a short fixed list with **no default** (Q3). Each tax or fee line carries its source and citation (Q2). A5's "new charge type with no classification": **every charge must declare its tax status, with no default** (Q5), so the silent failure is now refused. A6's tax-on-tax question has a concrete Texas answer for that pair. **Narrowed or answered.**
- **A7, being able to reproduce the base later.** Each tax line carries its base rows (Ryan, CI-016, 10-14), which replaces `invoices.tax_breakdown` as the evidence. **Narrowed.**
- **A8 to A11, exemptions.** Tax applies only when **both** the item and the customer are taxable **for that service type**. An exempt customer still gets a **$0.00 tax line**. A taxable customer never makes a non-taxable item taxable (Q5). **Narrowed.**
- **A12, reconciling the franchise fee with what is remitted.** The platform holds **only the liability**: billed and collected by jurisdiction and period, plus an optional filing reference. Paying the city happens in the utility's own accounting system (Q4). **Narrowed.**
- **A14 to A16, GL mapping.** The platform is a receivables subledger that **exports** to the utility's accounting, not a general ledger (Ryan, 10-13). GL mapping is dated, keyed by charge type, class, territory and tax jurisdiction, **most specific wins**, frozen inside a closed period, and **an export refuses an unmapped line** (wave 2, G1 to G3). The doc's "posting cannot proceed" and "exactly one entry" are both wrong: posting to the subledger proceeds, the export refuses, and several entries can match. FERC and NARUC account codes and cost centers are tenant configuration. **Reversed in part.**

**Texas-only assumptions:** CI-044's franchise-fee premise (a city franchise fee on in-city customers). For a city-owned system, whether any franchise-like fee exists is the city's tariff row; there is no default (Q3).

**Verdict:** **revise (heavy; about 12 of 16 axes).** Family still changing: **tax (-28)**, with CI-044 BLOCKED (`franchise_fee_rules` still keys on a city name, not a place).

**Open questions answered:**
- A5 (charge with no classification): Q5.
- A6 (tax-on-tax for the Texas pair): Q2.
- A14 and A16 (the GL mapping's shape): wave 2 G1 to G3, plus the 10-13 subledger ruling.
- Next step 4 (annexation drafted jointly with premise zones): places and memberships (Q1, R-10).
- The remittance reconciliation's scope: Q4.

---

## 9. tenant-isolation-and-structural-integrity

**Covers:** CI-116 to CI-119 (tenant isolation, identifiers unique per tenant, imports not duplicated, a meter once per billing run). 16 axes, 0 scenarios, abstract.

**What has changed under it:**
- No ruling contradicts it.
- The schema facts are stale: the doc says 58 tables have row-level security. The measurement shows 100 of 130 with RLS on and forced, and two archive tables without a tenant FK.
- The open question **R-12** (must every cross-table link prove both rows belong to the same tenant?) is unanswered and would add an axis. Lineage links are single-column today; the measurement notes this under CI-052.
- Setup tables block deletes (R-03, 10-15). That touches A13's "re-run is a new row" framing only in passing.

**Texas-only assumptions:** none.

**Verdict:** **keep as is.** Refresh the schema counts, and add a cross-tenant link axis once R-12 is ruled. No family dependency.

**Open questions answered:** none. R-12 is still open.

---

## 10. texas-bill-format-read-cadence-and-meter-rules

**Covers:** CI-088 (bilingual notices), CI-089 (required bill elements), CI-090 (six-month actual reads), CI-091 (meter-test fee), CI-092 (limits on rebilling after a meter error). 21 axes, 0 scenarios, abstract.

**What has changed under it:**
- **The premise of the whole doc.** Each invariant is a §7.45 / chapter 7 rule, and none binds city-owned systems. For our first customers each is a tariff row, entered per city with no defaults (standing rule; K-07). **Narrowed throughout.**
- **A1 to A5, bilingual notices.** The Q-8 design ("two-language enum plus an exemption flag") is narrowed. Customers can prefer an **accessible format** (large print, braille, language), and the **format actually sent is recorded** (Kyle K-06, 10-15). "English-only without a Commission exemption is not served" holds only where §7.45 binds. **Narrowed.**
- **A9, the prompt-payment discount date.** **No early-pay discounts**, because gas is regulated; the rule type is dropped (K-06). CI-089's statement still lists "prompt-payment discount date" and "total due before and after discount". **Reversed.**
- **A6 to A8, bill elements.** The per-line arithmetic is now fixed at issue (Ryan, CI-016, 10-14; Kyle R-01): usage, base charge, surcharge and tax lines each carry their figures. **Narrowed in a helpful way.**
- **A10 to A13, read cadence and estimation.** Estimation rules are dated rule data with a citation (R-11). An estimate replaced by an actual read is a supersede with the reason "estimate trued up" (K-03). **Narrowed.**
- **A14 to A16, the meter-test fee.** "$15, 4 years, 2.0%" are no longer constants: **the fee depends on the test outcome, with tolerance and fee as rule data, confirmed with the tenant** (K-06). **Narrowed.**
- **A17, "collections suspended during a dispute-triggered test".** A dispute shelters the **disputed amount, not the account** (wave 3, D7, 10-18). **Reversed.**
- **A18 to A21, rebill limits.** These are `backbilling_rules` law rows (meter error, non-registering meter). A meter-error backbill cannot drive a disconnect (Kyle F-1, pre-window). Not contradicted, but they are Texas law rows only. **Narrowed.**

**Texas-only assumptions:** the doc's title and all five invariants are tagged "jurisdiction: texas" and treated as binding. CI-088's "statewide, preempts counties" holds only for utilities §7.45 binds.

**Verdict:** **revise (heavy), close to a rewrite.** About 17 of 21 axes are affected. Families still changing: **rates and meters (-28 includes CI-089 and CI-091)** and **disputes (-25)** for A17.

**Open questions answered:**
- A9: dropped (K-06).
- A14 ($15 cap): rule data (K-06).
- The Q-8 design: superseded by accessible formats (K-06), with cities outside §7.45.
- Next step 4 (one meter-test-history gap or two?): `meter_tests` now exists (measurement, CI-091 PARTIAL).
- Still open: Next step 6 (group the bill elements into fewer scenarios?).

---

## 11. texas-collections-overlay

**Covers:** CI-078 to CI-081 (grounds that can't drive a disconnect, no disconnect before a closed day, the extreme-weather ban, the medical hold with an installment agreement). 12 axes, 0 scenarios, abstract.

**What has changed under it:**
- **The premise.** §7.45, §7.460 and §104.258 bind investor-owned utilities and unincorporated areas, not city-owned systems. For cities, each protection is a tariff row or does not exist (standing rule; wave 3 source TX-GAS). The doc treats all of them as binding on "a Texas residential customer". **Narrowed throughout.**
- **All axes, how decisions are made.** The core writes a **collections decision** for each act (notice, late fee, disconnect order, disconnect execution, referral): eligible, blocked, or **unevaluable, and unevaluable blocks**. Executing a disconnect cites **its own** decision (wave 3, E1 to E5, 10-18).
  - A6 (a delayed weather feed lets disconnects proceed) is reversed: a missing input yields "unevaluable", which blocks.
  - A7 (a weather emergency begins mid-cycle) is now "re-decide at execution".
- **A4, closed days.** The closed day is the utility's **own staffed days**, not a fixed weekend and holiday list (§7.45(4)(F), §104.258(b); pending Kyle, 10-18). **Narrowed.**
- **A5, the extreme-weather test.** The forecast leg should use the **forecast high** ("predicted to remain at or below" 32 °F), not the low. GBM's table uses Georgia's rule (pending Kyle, 10-18). **Reversed, pending.**
- **A2, mixed arrears.** Now consistent with the dispute ruling: a shelter covers an amount, not the account (wave 3, D7).
- **A9 to A12, medical hold.** Enrollments keep an add-only dated history, and **a lapse triggers a notice before protection ends** (Kyle R-07). **Narrowed.**
- **Missing protections.**
  - Death is a dated customer status, and its hold **blocks shutoff and collections** until the account is changed over, with a one-month exception if nothing changes (Kyle R-08).
  - The **60-and-over due-date delay (§182.002) binds city systems** (pending Kyle).
  - City systems still owe **due process before a cutoff** (*Craft*).

**Texas-only assumptions:** the whole doc. Every rule is written as binding on Texas residential customers, but our first customers are city systems that only §182.002 and *Craft* reach.

**Verdict:** **rewrite.** It needs reframing as Texas law rows (investor-owned utilities and unincorporated areas) plus city tariff rows, with decisions. 12 of 12 axes are affected. Family still changing: **collections (-26)**, and write it after -26 mirrors (R-18).

**Open questions answered:**
- A4 (multi-day closures): the staffed-days calendar.
- A6 (feed delay): unevaluable blocks.
- "A tenant tariff could extend protection, check at onboarding": now tariff rows with no defaults (K-07).
- A5: the threshold of "at or below 32 °F" stands, but the forecast leg uses the high (pending Kyle).

---

## 12. texas-sub-jurisdiction-and-rate-change-workflow

**Covers:** CI-086 (an inside/outside city limits flag per account), CI-087 (the Texas rate-increase filing, notice and waiting period). 11 axes, 0 scenarios, abstract.

**What has changed under it:**
- **CI-086, the flag itself, and A1, A3 and A4.** A single "Incorporated or Environs" flag is replaced by **dated place memberships** (on the regulatory axis, no overlaps, evidence required) on a service location that never changes (R-10; Q1; places work 10-06; measurement CI-086 REP+PROT). The rule set attaches per service location where rules differ inside and outside city limits (standing rule, 10-15). **Reversed in mechanism**; annexation stays dated, as the doc says.
- **A1, A2 and A5, what the flag drives: "Env means the Railroad Commission's tariff, no franchise fee".** For a **city-owned system the city council sets rates inside and outside the city**. Outside customers can *appeal* to the Commission (§103.053), but the Commission does not set their tariff. The franchise fee base and whether it applies are per jurisdiction with no default (Q3). **Reversed for city systems.**
- **CI-087 and A6 to A9, the rate-increase filing, newspaper notice and 35-day wait.** This is the Utilities Code ch. 104 process for investor-owned utilities. A city system changes rates by council ordinance. It stays valid only as a law row for Commission or city-regulated investor-owned utilities. The 07-10 ruling on a missed notice week (D11-1) stands for those. **Narrowed.**
- **A10, a shared activation gate with the gas-cost factor.** The gas-cost side is now billing-side factor history only (Q6). Rate versions show the rate in effect on the 1st and flag bills that went out at a different rate (R-09). **Narrowed.**
- **A11, rebill replay.** Consistent.
- The utility owns its rates; the platform keeps the legal value as a reference and reports discrepancies (standing rule).

**Texas-only assumptions:** the whole doc. The title, both invariants tagged Texas, and a boolean modelled as if all Texas customers sat under either a city's regulator or the Commission.

**Verdict:** **rewrite.** About 10 of 11 axes are affected. Family: **rates (-28)**. CI-087 has no schema yet (GAP) and needs a per-jurisdiction rate-change filing record.

**Open questions answered:**
- A4 (inside city limits but under the Commission): handled by place memberships.
- Next step 5 ("both CI-086 and CI-087 are unbuilt gaps"): CI-086 is now represented and protected.
- Still open: A10 (one activation gate or two), in a narrowed form.

---

## 13. volume-to-energy-correctness

**Covers:** CI-021 (the volume-to-energy formula), CI-022 (meter rollover), CI-024 (a meter swap mid-period), CI-029 (pressure factor only on elevated-pressure meters). 9 axes, 0 scenarios, abstract.

**What has changed under it:**
- **A1 and A3, the factors and reference conditions.** Zones are tenant-defined, with **separate dated zone sets per factor** (heating value, pressure, rate), assigned to the location or the meter (Kyle K-02, 10-15). "Texas: 60 °F / 14.65 psia" is presented as a Texas constant, but it is the utility's tariff value (the utility owns it) and has to be a per-jurisdiction or per-utility row. **Narrowed.**
- **A2, factors written out explicitly.** Strengthened: a usage line carries the meter factor, CCF used, therms billed and commodity rate at issue (Ryan, CI-016; Kyle R-01). Intermediate math carries four decimals, and money rounds half-up to the cent (K-06). **Narrowed.**
- **A6 and A7, meter swaps.** Meters have a **dated install history per location**, and a swap does not touch the location (R-10). A replacement read names its reason, such as "meter swap" (K-03). **Narrowed.**
- **A9, where the pressure class comes from.** Pressure gets its own zone set (K-02); that is a place for it, though not yet a meter-level pressure class.
- **A4, A5 and A8.** Not contradicted.

**Texas-only assumptions:** A3's Texas reference conditions, "out of Texas-only launch scope". Under the standing rule a second state is a data row, not out of scope.

**Verdict:** **revise (heavy by count, 5 of 9 axes, but the changes are additive).** Family still changing: **zones and meters (-28)**.

**Open questions answered:**
- A3 (multi-state reference conditions): per-jurisdiction rows.
- Partly Next step 3 (gap-state sourcing): K-02 gives pressure a home.

---

## 14. weather-normalization

**Covers:** CI-039 to CI-043 (what the weather adjustment applies to, its season, its deadband, recording its inputs on the bill, program exclusions). 13 axes, 0 scenarios, abstract.

**What has changed under it:**
- **A12 and A13 and CI-043, program exclusions.** "Program exclusions become dated rule data with a citation" (R-11, 10-15). That settles the doc's question: a configurable rule, not a Texas-confirmed exclusion and not a hard-coded list. **Answered.**
- **The weather-adjustment factor and deadband.** These are the utility's own tariff values (the utility owns them). A city system has a weather adjustment only if its tariff has a rider; there is no default (K-07). **Narrowed.**
- **The contrast with gas cost in the preamble.** "PGA settles annually through a deferred account" is still true of the utility, but the deferred account is **not a platform record** (Q6). The contrast should say so. **Narrowed.**
- **A9 and A10, the inputs recorded on the bill.** Consistent with lines carrying their own arithmetic (CI-016), and with four-decimal math (K-06).
- **A7, deadband per rate schedule and weather zone.** Fits K-02's per-factor zone sets; no conflict.

**Texas-only assumptions:** mild. The Atmos and TGS class-scoping examples are investor-owned tariffs. City systems need their own rows.

**Verdict:** **revise (light; about 3 of 13 axes).** Family: **rates (-28)**, and zones.

**Open questions answered:**
- Next step 4 (is CI-043's program exclusion real for Texas?): it is rule data with a citation (R-11), loaded only where a tariff has it.

---

## 15. wu5-axes-review-brief

**Covers:** the July review brief for Kyle across all 17 families. It is a historical record ("ANSWERED"), with no scenarios.

**What has changed under it:** these answers it points to have been superseded since 10-13.
- **Q-5 / D7-1 (no customer designation)** is superseded by K-05: deposit or bill only.
- **D1-3 (no depth cap)** is superseded by the 1,000-deep cap (Ryan, 10-17).
- **D4-1 (PSF has no timing machinery; the cap question)** is superseded by K-04: no fixed cap, and billing timing is a rule field.
- **Q-8 (bilingual design)** is superseded by K-06 accessible formats, and cities are outside §7.45.
- **Q-6 and the EWE answers** are narrowed: they bind only where §7.45 and §7.460 apply, and the forecast leg is pending Kyle.
- **D7-2 (class on charge definitions)** is superseded: the class is on each bill line (10-16).
- **D5-1's PGA contrast** is narrowed by Q6.
- **Family 16's "Texas deposit mechanics read clean from statute"** is narrowed: city deposits are the city's own policy (LGC §552.0025(c)) and tariff rows.
- **Q-1 (concurrent edits)** is answered by Kyle K-01: a save is refused if the record changed since it was loaded.

**Texas-only assumptions:** Family 11's and Family 16's statutory framing.

**Verdict:** **keep as is (historical).** Add a banner pointing to the rulings digest for answers superseded since 10-13. No family dependency.

**Open questions answered:** Q-1 (K-01). Still open: Q-4, Q-7, Q-9 and Q-12, none of which appear in the digest.

---

## Summary table

| Doc | Axes | Affected | Verdict | Family still changing |
|---|---|---|---|---|
| payment-allocation-and-posting | 13 | 9 | revise (heavy) | cash -23/-27/-24, collections -26, disputes -25 |
| payment-intake-channels-and-reversal-handling | 16 | ~6 | revise (heavy for A3–A5, light elsewhere) | cash -23/-27/-24 |
| pga-and-commodity-pass-through | 17 | 11 | revise (heavy), close to a rewrite | gas cost -28 |
| read-exception-handling-and-estimation | 21 | ~6 | revise (light) | reads/meters -28 |
| read-pipeline-and-supersede | 8 | 5 | revise (heavy, mostly mechanical) | reads -28 |
| regulatory-cost-recovery-surcharges-texas | 7 | 6 | revise (heavy) | rates/tax -28 |
| reversal-lineage-and-chain-discipline | 7 | 6 | rewrite | cash -23/-27 |
| taxes-franchise-fees-and-gl-posting | 16 | ~12 | revise (heavy) | tax -28 |
| tenant-isolation-and-structural-integrity | 16 | 0 | keep (refresh counts; R-12 open) | — |
| texas-bill-format-read-cadence-and-meter-rules | 21 | ~17 | revise (heavy), close to a rewrite | rates/meters -28, disputes -25 |
| texas-collections-overlay | 12 | 12 | rewrite | collections -26 |
| texas-sub-jurisdiction-and-rate-change-workflow | 11 | ~10 | rewrite | rates -28 |
| volume-to-energy-correctness | 9 | 5 | revise (heavy by count, additive) | zones/meters -28 |
| weather-normalization | 13 | 3 | revise (light) | rates -28 |
| wu5-axes-review-brief | — | — | keep (historical; add a banner) | — |
