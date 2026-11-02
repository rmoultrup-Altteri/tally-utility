# Rulings digest: what changed since 2026-10-13 that a billing scenario could depend on

Built 2026-11-02 to audit the scenario docs written Jul–Sep 2026. Grouped by family. Each entry gives the date, who ruled, the rule, the invariants it touches, and the source.

**Marker:** **[REVERSES]** = an older assumption is now wrong. **[NARROWS]** = an older assumption still holds, but with less scope or a new limit. **[NEW]** = no earlier rule existed.

**Abbreviations for sources:**
- DL = `tally-utility-scenarios/application/DECISION-LOG.md`, followed by the entry heading.
- GBM-1014, GBM-1015, GBM-1021, GBM-1030 = `gas-billing-memory/application/kyle-decisions-2026-10-14-tax-jurisdictions-and-gas-cost.md`, `…-10-15-waves-1-to-7-and-texas-first.md`, `…-10-21-refund-then-bounce.md` (with `kyle-rulings-2026-10-21-…`), `…-10-30-credit-shortfall-after-bounce.md`.
- W2 = `application/wave2-build-2026-10-15/source-inventory-wave2.md`; W3 = `application/wave3-build-2026-10-18/source-inventory-wave3.md`.
- DJ = `application/roadmap/decisions.json`.

**R-01…R-11:** DJ lists them as Ryan's; Kyle's 10-15 file answers them (Ryan also took the defaults for CI-014/016/017 on 10-14).

---

## Standing rules (apply across every family)

| Rule | What it means for a scenario | Source |
|---|---|---|
| **Build for Texas first, never hard-code Texas** (Kyle 10-15; standing) | Each jurisdiction (state, regulator, city overlay) owns its own dated rule sets, each with a legal citation. Adding a state means adding data, not code. Where rules differ within a state (inside vs outside city limits), the rule set attaches per service location. A scenario must never treat a Texas figure as a universal constant. | GBM-1015 "Standing rule"; memory `launch-scope-is-not-architecture-scope` |
| **City-owned gas systems are outside GURA** (standing; Kyle K-07 10-15) | 16 TAC §7.45 and chapter 7 do not bind city-owned gas systems, which are our first customers. Their policy is the city's tariff rows, entered per utility with **no assumed defaults**. A city with no tariff row on a topic has no rule there, and the record says so. **[NARROWS]** any older scenario that applies §7.45 to a city system. | GBM-1015 K-07; memory `texas-muni-outside-gura` |
| **The utility owns regulated values** (standing) | A value the utility answers for (its rates, its factor, its fees) stays the utility's. The platform keeps the legal value as a reference and reports any discrepancy; it does not override. | memory `utility-owns-regulated-values` |
| **Schema represents, core evaluates** (standing) | The database stores rules, facts and the decisions made; the future C# core applies the rules. A scenario's expected result is a core output plus what the database records, not a trigger's result. | memory `schema-represents-core-evaluates`; W3 "Settled by rule" 3 |
| **Store a decision when it changes, never per check** (standing) | Decision records (dispute shelter, collections eligibility, deposit return) are one row per change of answer. | memory `design-permanent-record-on-change`; W3 E2 |
| **Rounding** (Kyle 10-15, K-06) | Money rounds to the cent, half-up at the midpoint. Rates and intermediate math carry four decimals. CI-109. | GBM-1015 "Wave 7", K-06 |

---

## 1. Cash, payments, credits

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-15 Kyle (R-05) | Payments, credits and one-off charges are **add-only**. A correction is a reversal plus a new row; nothing is edited in place. **[REVERSES]** any scenario that edits a payment amount or a credit. | CI-013 | GBM-1015 R-05 |
| 10-15 Ryan (wave 2, Q1; "W2-Q1") | Status stays a column but **only moves forward**, and every move names the money row behind it (a bounce names its reversing ledger entry; a charge's void names its reversal). | CI-013 | DL "2026-10-15 (wave 2, Q1)"; W2 "Q1"; DJ W2-Q1 |
| 10-15 W2 drafting (standing rule) | **Stored counters are dropped**: `payments.applied_amount`/`unapplied_amount`, `customer_credits.applied_amount`/`remaining_amount`. Each becomes a sum of application rows, read as of a date. Same reasoning as dropping the stored running balance. **[REVERSES]** | CI-013 | W2 M1 |
| 10-21 Ryan | **"Refunded" and "donated" are not stored statuses.** Payments: pending, posted, nsf, reversed, voided. Credits: active, escheated, voided. "Refunded" and "donated" are read from the positions (nothing left because of refunds or a donation). A refund that fails or a donation undone frees the money again. Escheated stays final. **[REVERSES]** the 10-15 wording (credit `active → refunded`) and older scenarios that show a "refunded" payment or credit status. UI Concepts still lists "refunded" as a status. | CI-013 | DL "2026-10-21 (-23 r3) — Ryan: refunded and donated…"; memory `refunded-donated-derived` |
| 10-15 Kyle (R-06) | Payments handle partials and overpayments. The amount goes to the **oldest bill first**; each line is capped at its open balance. A leftover is either not taken or held as a credit **only if the customer approves** applying it to future bills at payment time. The approval is an add-only record (amount, approver, when). **[NEW]** credit approval record. | CI-050 | GBM-1015 R-06; W2 A, C1 |
| 10-15 Kyle (K-05) | A customer may designate a payment **only as a deposit or as a bill**, never for a particular charge or bill. Within one bill, the order is the jurisdiction's/tariff's rule data, confirmed by the tenant at setup. Kyle found no statewide Texas order. **[REVERSES]** the tenant settings `newest_first`, `largest_first`, `manual_only` and `overpayment_handling = apply_to_specific_invoices` (retired). `refund_automatically` stays. | CI-049, CI-050 | GBM-1015 K-05; W2 A4, C2 |
| 10-15 W2 drafting | Application is stored **per bill line**; a wrong one is undone by a negative application naming it. Each records `oldest_first` or `operator_override` (reason, user). **[REVERSES]** per-invoice application. | CI-049, CI-050 | W2 A1–A4 |
| 10-16 standing rule (-23 triage) | Each bill line carries its own regulated/unregulated class. Within a bill, **regulated lines are paid before unregulated** as a fixed term that no tariff row can turn off. The order is a tariff row; Texas has no law row for it. | CI-050 | W2 "-23 triage" 1–2; DL "2026-10-16 (-23 triage)" |
| 10-16 open (for Kyle) | When an agency payment's restriction conflicts with the regulated-first floor, the schema records which won; **who wins is not ruled**. Scenarios should not assume an answer. | CI-050, CI-056 | W2 "-23 triage" 3 |
| 10-16 Ryan | **Unmatched cash (suspense)** and **agency pledges** come in -24. Suspense is never applied to a guessed account; it is resolved by a payment naming it, or a refund. | CI-053, CI-056 | W2 U, L |
| 10-21 Kyle (K-10 Q1) | **A refund is its own movement of money, not a reversal of the payment.** Both the refund and a later bounce are recorded as they happened. | CI-017, CI-055 | GBM-1021 |
| 10-21 Kyle (K-10 caps) | Two caps per payment. A **bounce or reversal** ≤ payment − earlier reversals (refunds do not reduce it). A **refund** ≤ payment − earlier refunds − earlier reversals. Worked example: $50 payment, $30 refund, $50 bounce, so the customer owes $30. | CI-017 | GBM-1021 "cap math" |
| 10-21 Kyle (K-10 Q2) | **A bounce is refused while a refund of that payment is pending**, until an operator cancels the refund. No automatic cancel; the bounce screen offers a one-click cancel. | CI-055 | GBM-1021 |
| 10-21 Kyle (K-10 Q3) | A hold on refunds during a check/ACH return window is **tenant policy, off by default**. The schema does not enforce it. | CI-058 | GBM-1021 |
| 10-21 r3 | Every draw on a payment (application, credit, donation, remittance, refund) is capped by the payment less what was taken back, at every date. A refunded-then-bounced payment reads **negative** remaining. Money counts from its arrival date (ACH dated the 5th, settled the 8th, counts from the 8th). | CI-013, CI-017 | DL "2026-10-21 (-23 r3) — Kyle's K-10 applied" |
| 10-21 r4 (K-10 through the credit) | A payment has at most **one live overpayment credit**. A bounce waits only while that credit is applied or has a refund pending. What the credit already paid out stands; what it still held goes with the bounced payment. | CI-013 | DL "2026-10-21 (-23 r4) — round 3" |
| 10-21 Ryan | **A refund that comes back after its credit was escheated becomes a new credit** (`refund_reissue`), at most the refund, with its own dormancy clock. Nothing ever returns onto an escheated credit. If the payment also bounced, nothing is carried; the customer owes the rest. | CI-013 | DL "2026-10-21 (-23 r4) — Ryan: a refund that comes back…"; "2026-10-28 (-23 r5)" |
| 10-28 r5 | A re-sent refund is a **new refund**, just as a re-presented check is a new payment. A reissue is dated on or after the row that returned its refund. | — | DL "2026-10-28 (-23 r5)" |
| 10-30 Kyle (K-11) | **All of a customer's credits are one pot**, shown as **one net credit balance** (not one line per payment or reissue). A bounce's shortfall uses up the total credit and the customer owes the rest. A positive credit never shows as refundable while the customer's net position is owed. Partial refunds of a credit are allowed up to the available credit; how much is utility policy. Internal tracking and ordering are ours. | CI-013 | GBM-1030 |
| 11-01 Ryan (option 1) | The netting **across payments** is the core's job, not the database's. In the database, payment Y's credit can still read as refundable (and run its own escheat clock) while payment X's bounce leaves the customer owing. App code must net before refunding or escheating (contract AC-44). **[NARROWS]** what the database guarantees compared with Kyle's one-pot view. | CI-013 | DL "2026-11-01 (-23 r7)" |
| 10-29 → 11-01 (r6–r8) | Within one payment a shortfall is covered by sibling credits (latest first), then the payment; the total is the same. **11-01 (option A):** no line reads more than it can pay, but per-line figures are attributions; only the net total is exact. **[NARROWS]** "each line pays exactly what it reads". | CI-013 | DL "2026-11-01 (-23 r8)", "2026-10-29 (-23 r6/r7)" |
| 10-29 Ryan | A reissue carrying a share of a take-back **cannot be voided** (known limit); its money stays on that line. Reissue chains max 999 deep. | — | DL "2026-10-29 (-23 r7)" |
| 10-14 Ryan (CI-017) | A **refund names exactly one source**: the payment it returns or the customer credit it pays out. A replacement for a bounced payment is a fresh receipt; its link to the original is optional. | CI-017 | DL "2026-10-14 (CI-017)" |

## 2. Deposits

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-15 Kyle (K-05) | A payment may be designated as a **deposit** (as opposed to a bill). This is the only designation a customer can make. | CI-049 | GBM-1015 K-05 |
| 10-15 Kyle (R-01) | A one-off charge such as a deposit or reconnect fee carries a **reason code**, not a rate or service period. | CI-016 | GBM-1015 R-01 |
| — | No new deposit rulings in the window. The deposit rewrite decisions (-15, Florida interest by customer type) predate 10-13. Deposit tariffs are the model for the tariff-row shape used in the new families. | — | memory `deposits-rewrite-decisions`; W2 "-23 triage" 2 |

## 3. Disputes

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-18 Ryan (wave 3, Q1; "W3-Q1") | **Dispute policies are rule entries**: one law table (Texas gas §7.45(6)(D) is one row) and one tariff table (each city's own row, e.g. Brenham, CPS Energy). The terms cover the grounds and excluded subjects, how much must still be paid, when the shelter starts and ends, the review stages and deadlines, and what the shelter blocks. Every dispute determination cites the row it applied. **A city with no tariff row has no dispute terms.** City policies differ: Brenham requires paying 100% with no cutoff during the investigation; CPS requires paying the undisputed charges and has a two-stage appeal. | CI-074 | DL "2026-10-18 (wave 3, Q1)"; W3 D6, Q1; DJ W3-Q1 |
| 10-18 standing rule (design, -25) | **A dispute protects the disputed amount, not the account.** The `pending_dispute` program stops being disconnect-protective. **[REVERSES]** the older idea of a whole-account shelter. | CI-074 | W3 D7 |
| 10-18 design | The disputed amount is a dated series; the shelter (amount, must-pay and basis, what it blocks) is a core-written determination that late fees and notices read as of a date. Reopen = new dispute. Read disputes become dispute rows; `meter_readings.dispute_*` retire. **[REVERSES]** | CI-074, CI-054 | W3 D1–D5, D8 |
| 10-18 for Kyle | City systems still owe due process (*Craft*): before a cutoff, a protest heard by someone with authority to cancel it. | CI-074 | W3 "For Kyle" 4 |

## 4. Collections, disconnects, protections

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-18 design (-26, settled by rule) | The core writes a **collections decision** each time it decides whether an act may happen (a notice, late fee, disconnect order, disconnect execution, or collections referral). The outcome is `eligible`, `blocked` or **`unevaluable`, and unevaluable blocks**: a missing input such as weather data or a staffed-days calendar never yields eligible. Every act cites an eligible decision covering its date. **Executing a disconnect cites its own separate decision**, not the one made when the order was issued. | CI-067, 069, 070, 075 | W3 E1–E5 |
| 10-18 design | A disconnect order completes only after a field visit whose meter and service point match, or after a **supervisor's override** with a reason and evidence. Abort reasons come from Pennsylvania (vocabulary only; Texas requires none). | CI-071 | W3 F1–F3 |
| 10-18 design | `invoices.late_fee_assessed`/`late_fee_amount` are dropped and derived from late-fee charges. `dunning_stage` moves only with an event behind it. **[REVERSES]** stored late-fee flags. | CI-075 | W3 E7 |
| 10-15 Kyle (R-07) | Program enrollments keep an add-only, dated status history with an optional end date per program type. **A lapse triggers a notice before protection ends** and never silently drops the customer. | CI-065, 082–084 | GBM-1015 R-07 |
| 10-15 Kyle (R-08) | **Death is a customer status with a date**, not a program. Ownership change needs proof (death certificate, obituary, plus a will, conservatorship or spouse documentation). The account carries a hold that **blocks shutoff and collections** until changed over. If there is no update within a month, a medium-priority exception is raised. **[NEW]** | CI-085 | GBM-1015 R-08 |
| 10-15 Kyle (R-11) | Estimation, late fees and program exclusions become **dated rule data with a citation** (late-fee rate, base, cap, grace and exempt programs are law/tariff rows). | CI-114, 054, 081 | GBM-1015 R-11 |
| 10-18 for Kyle | GBM's disconnect table misreads three points: the 60+ due-date delay (§182.002, 25 days after issue, no late fee) **binds city gas systems**; the extreme-weather forecast uses the forecast high (§7.460); closed days are the utility's staffed days. **[REVERSES, pending Kyle]** | CI-079–081 | W3 "For Kyle" 1–3 |

## 5. Tax and franchise fees

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-14 Kyle (Q1) | **A tax jurisdiction is a place** (city, county, transit or special district). Its taxes are separate dated rows, and a service location links to **every** jurisdiction it sits in. Rates come from the Comptroller's quarterly files through a staged job; **no rate goes live without an operator's sign-off**. | A-8 | GBM-1014 Q1; DL "2026-10-14 (A-8, CI-033, CI-036)" |
| 10-14 Kyle (Q2) | Each tax or fee line carries its source (statute, ordinance or tariff) and a citation, configured per tenant. **The franchise fee is a percentage of all billed lines except excluded ones (the pipeline safety fee, 16 TAC §8.201)**. **The franchise fee is not in the sales-tax base.** | — | GBM-1014 Q2 |
| 10-14 Kyle (Q3) | The franchise fee base type is picked per jurisdiction from a short fixed list, **with no default**. Per-item taxable flags and the franchise rule's `applies_to` merge into one mechanism; the customer-type size-tier defect is closed. | — | GBM-1014 Q3 |
| 10-14 Kyle (Q4) | For remittances the platform holds **only the liability**: billed and collected by jurisdiction and period, plus an optional filing reference. Payments to the Comptroller and cities stay in the utility's ERP. **[NARROWS]** | — | GBM-1014 Q4 |
| 10-14 Kyle (Q5) | **Every charge must declare its tax status; there is no default of non-taxable.** Tax applies only when **both** the item and the customer are taxable **for that service type**. An exempt customer still gets a **$0.00 tax line**. A taxable customer never makes a non-taxable item taxable. Taxability is per service type (e.g. taxable for gas, not for water). Water and sewer treatment awaits tax counsel. **[REVERSES]** `DEFAULT false` and per-customer (not per-service) taxability. | CI-046 | GBM-1014 Q5 |
| 10-15 Kyle (K-04) | The pipeline safety fee is a dated rule (amount, basis per customer or per service line, billing timing, citation, optional recovery-report deadline). **There is no fixed cap**; the amount is set by rule (§8.201). One 2024 tariff shows $1.22 per customer. Confirm against §8.201 before loading. | CI-037, 038 | GBM-1015 K-04 |

## 6. Gas cost (PGA)

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-14 Kyle (Q6) | **Billing side only.** The platform keeps the approved PGA factor (**every historical factor, so a rebill uses the one in effect then**), billed gas-cost revenue and volumes per period, exported for the utility's reconciliation. Gas purchases, the deferred gas-cost balance, carrying cost and the annual true-up are **not platform records**. **[NARROWS]** any scenario that computes the factor, the deferred balance or the true-up. | CI-033, CI-036 | GBM-1014 Q6; DL "2026-10-13 (finance gate)" carve-out, closed 10-14 |
| 10-14 Kyle (Q7) | **The unaccounted-for gas cap is out of scope.** The utility applies any cap before filing its factor. **[REVERSES]** any scenario that applies the cap in billing. | — | GBM-1014 Q7 |
| 10-14 Ryan (-21) | **A gas rider line carries no commodity rate**; the commodity rate is the usage line's figure. | CI-016 | DL "2026-10-14 (-21 review round 1)" |

## 7. Places and jurisdictions

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-15 Kyle (R-10) | **Service locations never change.** Occupancy is a separate dated record linking customer to location, with no overlaps at one location. Meters have a dated install history per location. During a transfer the account stays open; each premise is vacant, held by the owner, or held by a customer. **[REVERSES]** `service_locations.customer_id` as the occupant. | — | GBM-1015 R-10 |
| 10-15 Kyle (K-02) | Zones are tenant-defined, with **separate dated zone sets per factor** (heating value, pressure, rate), assigned to the location or meter. | CI-020, 026 | GBM-1015 K-02 |
| 10-15 Kyle (K-04) | Neutral internal terms, "sales service" and "transportation service", with a per-jurisdiction label table; the tenant supplies its tariff wording. | CI-037 | GBM-1015 K-04 |

## 8. Invoices, voids, cancel-rebill

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-14 Ryan (CI-017) | **Every reversal names exactly what it undoes.** A correction invoice must name the invoice it replaces, and that invoice must be void. A ledger void reversal names its entry and has a non-blank reason. | CI-017 | DL "2026-10-14 (CI-017)" |
| 10-14 Ryan (void) | **Posted vs never-posted bill.** Voiding a posted bill (first issued) reverses its charge entry; it is refused if no charge entry exists. Voiding a bill straight from `held` (never issued) **posts nothing**. **[REVERSES]** the old behaviour, which credited a held bill's void. The line is posting, not mailing: once posted, the customer owes, delivered or not. | CI-017 | DL "2026-10-14 (CI-017, void_invoice)" |
| 10-15 W2 drafting | **A void reverses what is left of the charge** after earlier reversals, not the full amount due. A charge already fully reversed voids with no ledger row. | CI-017 | W2 X3 |
| 10-14 Ryan (CI-016) / 10-15 Kyle (R-01) | At issue, each line carries its own arithmetic. **Usage**: quantity, unit and rate, plus for gas the meter factor, CCF used, therms billed and commodity rate. **Base charge**: rate, plus for a partial period the coverage dates, days covered, days in period and the policy applied. **Per-unit surcharge**: as for usage. **Tax**: its base rows. All other line types: amount only. One-off charges carry a reason code. | CI-016 | DL "2026-10-14 (CI-016)"; GBM-1015 R-01 |
| 10-14 Ryan (CI-014) | **The six bill tables keep their own guard**: a draft can be discarded, an issued bill never. | CI-012, CI-014 | DL "2026-10-14 (CI-014)" |
| 10-15 Kyle (K-06) | **No early-pay discounts** (gas is regulated); that rule type is dropped. **[REVERSES]** The meter test fee depends on the test outcome, with tolerance and fee as rule data. Customers can prefer an accessible notice format (large print, braille, language), and the format actually sent is recorded. | CI-089, 091, 097 | GBM-1015 K-06 |

## 9. Bi-temporal records, immutability, concurrency

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-15 Kyle (R-03) / 10-14 Ryan | **Setup tables block deletes**; rows retire with an end date. 17 more tables joined, including billing cycles, read routes, jurisdictions, communities, bill messages, auto-pay settings, numbering, rate dependencies and PGA settings. Rate dependencies are **retired, not deleted**. | CI-014 | GBM-1015 R-03; DL "2026-10-14 (CI-014)", "(CI-014 drafting)" |
| 10-15 Kyle (R-04) / 10-14 Ryan | A reference record's version number changes **only through one controlled, sealed function**; the void is sealed by its own role. | CI-011 | GBM-1015 R-04; DL "2026-10-14 (CI-011…)" |
| 10-15 Kyle (K-01) | **A save is refused if the record changed since it was loaded.** The user refreshes and re-enters the change; cached edits are never replayed (only memo and note text is kept). | CI-011 | GBM-1015 K-01 |
| 10-15 Kyle (R-09) | A customer's rate assignment is a **dated, add-only history with no overlaps**. Rate versions show the rate in effect on the 1st, and flag bills that went out at a different rate. | CI-120 | GBM-1015 R-09 |
| 10-17 Ryan | A correction chain (a charge, its correction, a correction of that…) is at most **1,000 deep**; past that, the correction posts as a new unlinked entry. | CI-017 | DL "2026-10-17 (-23 draft)" |

## 10. Ledger, GL, aging, periods

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-13 Ryan | **The ledger's stored running balance is dropped.** The balance is the sum of the customer's ledger rows as of a date and a recorded instant. A screen showing a running balance per line computes it. **[REVERSES]** any scenario that expects `running_balance` on a ledger row. | CI-019 | DL "2026-10-13 (CI-019)" |
| 10-13 Ryan (accepts Kyle's D-2) | The platform is a **customer receivables subledger that exports to the utility's accounting, not a general ledger**. Accounting periods are freeze boundaries; reports run over any date range; GL mapping is tenant configuration; **unbilled revenue is never a ledger row**. | CI-110, CI-048, CI-076 | DL "2026-10-13 (finance gate)" |
| 10-15 drafting (-22) | **A closed period never reopens**; corrections post into an open period. Money dated inside a closed period is refused; rows before any period are accepted. Closing is a supervisor's act, after the last day has ended at UTC-12. | CI-110 | W2 P1–P3, "-22 as drafted" |
| 10-15 drafting | **GL mapping**: dated, keyed by charge type, class, territory, tax jurisdiction (most specific wins); frozen inside a closed period; **an export refuses an unmapped line**. | CI-048 | W2 G1–G3 |
| 10-15 drafting | **Aging is balance-forward from the ledger.** Each entry is netted with its reversals; what is left is aged newest first. Bucket edges are a tenant setting (default 30/60/90/120). The customer's status on the aging is as recorded at the instant. | CI-076 | W2 W1–W2, "-22 as drafted" 5–6 |
| 10-15/16 drafting | A **write-off recovery** must name its write-off. The net of a write-off and everything under it stays between 0 and the amount written off, at every date. | CI-076 | DL "2026-10-15 (-22 r2)", "2026-10-16 (-22 r3)" |
| 10-15 Kyle (R-02) | Every reversal names its entry, and **reversals against an entry total at most the entry**, so partial reversals work and over-reversal is impossible. **[NARROWED 10-21]**: refunds are not reversals and do not count against this cap. | CI-017 | GBM-1015 R-02; GBM-1021 |

## 11. Rates

See R-01 (rate and service period on usage/recurring lines, section 8), R-09 (dated customer rate-assignment history, section 9), K-06 (4-decimal math, half-up cent rounding, standing rules) and Kyle 10-14 Q5 (taxable flag required, section 5). No other rate rulings in the window.

## 12. Reads and meters

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-15 Kyle (K-03) | **A replacement reading points at the reading it replaced.** The old one is marked superseded, not edited, and a reason code is required (estimate trued up, meter swap, misread). **[REVERSES]** editing a reading in place. | CI-030 | GBM-1015 K-03 |
| 10-15 Kyle (R-10) | Meters have a **dated install history per location**; replacing a meter does not touch the location. | — | GBM-1015 R-10 |
| 10-15 Kyle (R-11) | **Estimation rules are dated rule data** with a citation. | CI-114 | GBM-1015 R-11 |

## 13. Other

| Date / who | Rule | CI | Source |
|---|---|---|---|
| 10-29 Ryan (R-18) | Scenarios start now, beside the schema. Families still changing (cash, disputes, collections, tax, gas cost, zones, reads) are written **after their patches mirror**. Kyle checks the dollar figures on worked bills (K-08). | — | DL "2026-10-29 — Ryan: scenarios run beside the schema"; DJ R-18, K-08 |
| Open | Still unanswered and possibly affecting scenarios: every cross-table link proving same-tenant (R-12, CI-116); card-number masking (counsel, CI-051); a bill mailed to the wrong person (counsel, CI-135); test strategy (R-15). | — | DJ |

---

## Reversals and narrowings at a glance

1. Stored running balance dropped; balance is summed as of a date (10-13, CI-019).
2. Payment/credit counters (applied, unapplied, remaining) dropped; derived (10-15).
3. "Refunded"/"donated" are not statuses (10-21), reversing 10-15's `active → refunded`.
4. Money is add-only; status moves forward only, with a cause row (10-15).
5. A refund is not a reversal; two separate caps per payment (10-21).
6. Customers designate only bill vs deposit; oldest bill first; regulated lines first within a bill; three tenant ordering options and "apply to specific invoices" retired (10-15/16).
7. Credits are one net pot to the customer (10-30); the database nets only within a payment, across payments is the core's (11-01); per-line credit figures are attributions (11-01).
8. Voiding a never-posted bill posts nothing; a void reverses only what is left (10-14/15).
9. Gas cost is billing side only: no deferred balance, true-up or unaccounted-for gas cap (10-14).
10. Tax: no default classification; item and customer both taxable per service type; exempt customer gets a $0.00 line; franchise fee outside the sales-tax base (10-14).
11. No early-pay discounts (10-15).
12. A dispute shelters an amount, not the account; a city with no tariff row has no dispute terms (10-18).
13. Service locations are immutable; occupancy is a dated record (10-15).
14. Readings are superseded, not edited (10-15).
15. §7.45 does not bind city gas systems (standing); the 60+ due-date delay (§182.002) does (for Kyle, 10-18).
