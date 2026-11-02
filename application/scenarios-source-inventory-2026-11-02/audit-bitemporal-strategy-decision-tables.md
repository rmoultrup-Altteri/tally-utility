# Audit C: older scenario material against the rulings since 2026-10-13

Read-only audit, 2026-11-02. Sources audited, all in `gas-billing-memory/application/`:

1. `bi-temporal-scenarios.md` (26 scenarios, written 2026-05-14)
2. `configurable-rules-scenario-strategy.md` (the strategy, written 2026-05-15)
3. `configurable-rules/decision-tables/` (60 tables, written 2026-07-05 to 2026-09-09), plus a note on the other files in `configurable-rules/`

Measured against `scratchpad/rulings-digest.md` and the standing rules. Short codes in brackets after a sentence point to the source (digest section, ruling id); the sentence carries the meaning on its own.

Verdict scale: **keep** (still true; at most a dated note), **revise light** (a few facts or names to fix), **revise heavy** (the rule content is still useful but several rows or numbers are now wrong), **rewrite** (the shape is wrong; reuse only as a source inventory), **obsolete** (the subject is now out of scope).

---

## Part 1. `bi-temporal-scenarios.md`

### What it is

26 short stories, each in two halves: "with bi-temporality" and "without". They were written to justify keeping two time axes (when a fact was true, and when the system knew it) on reference data, and a frozen calculation snapshot on each bill. They are a design argument, not test scenarios: none states inputs and an expected bill. They name tables (`rate_item_history`, `wna_zones`, `wna_monthly_adjustments`, `invoice_calculation_snapshots`) and columns (`tt`, `vt`, `valid_from`).

**Worked numbers:** only partial. Rates, factors and account counts are given (for example $0.3820 vs $0.3280 a therm, a BTU factor of 1.023 vs 1.031, 4,200 accounts × 6 cycles). No scenario computes a bill, a line, a tax or a credit to the cent. None could be handed to Kyle to check the dollars (the 10-29 plan wants Kyle to check dollar figures on worked bills).

**The core argument still stands.** Every ruling since 10-13 has pushed the same way: rate history is dated and add-only (Kyle 10-15, a customer's rate assignment is a dated history with no overlaps), every historical gas-cost factor is kept so a rebill uses the one in effect then (Kyle 10-14), each bill line carries its own arithmetic at issue (Ryan 10-14 / Kyle 10-15), readings are superseded rather than edited (Kyle 10-15), and setup rows retire rather than delete (Kyle 10-15). So the "with" halves are broadly right in spirit.

### What has changed under it, across the whole document

- **Look-back caps are invented numbers.** Five scenarios state a cap as fact: "for this state, 12 months" (rate items 2), "commonly 12 months residential, up to 36 months commercial" (multiplier 1), "the 12-month backbilling cap" (WNA 3), "24 months" (tax 2), and "enforced automatically" (factors 3). Texas gas law caps a meter-error back-bill at the shorter of 6 months or the time since the last meter test, and unregistered usage at 3 months (the backbilling decision table, citing §7.45). City-owned gas systems are not bound by §7.45 at all; their cap is whatever their own tariff says, and a city with no tariff row has no rule (Kyle K-07, standing). A scenario must read the cap from the place's own rule row, never state one.
- **"The rebill engine credits each account automatically."** Still fine as an outcome, but three rulings now shape what that means. A correction is a reversal plus new rows; nothing is edited (Kyle 10-15). A corrected bill must name the bill it replaces, and that bill must be void (Ryan 10-14). Corrections post into an open accounting period, never a closed one (10-15 drafting). The resulting credit joins the customer's single credit pot (Kyle 10-30).
- **"The PSC/PUC orders" framing.** City councils set rates for city-owned gas systems; the state commission does not (standing rule on city systems). Fine as a generic story, but a Texas-city version of each regulator-driven scenario should say "the city council adopts a corrected tariff".
- **Gas cost reconciliation is not ours.** Any sentence that says the platform reconciles gas cost, keeps the deferred balance or computes the true-up is now wrong. The platform keeps the approved factors and exports billed gas-cost revenue and volumes per period (Kyle 10-14, Q6).
- **Tax remittance.** The platform holds only the liability (billed and collected by jurisdiction and period, plus an optional filing reference). Paying the city or the Comptroller, and getting money back from them, happens in the utility's own accounting system (Kyle 10-14, Q4).
- **Places.** A service location never changes. Zone, tax-jurisdiction and occupancy links are separate dated records (Kyle 10-15, R-10; Kyle 10-14, Q1). Scenarios that "update the service location record" should say "add a dated link".
- **Scenarios describe rules, not tables.** The table and column names should go.

### Per scenario

| # | Scenario | Digest contradicts or narrows | Texas-only conflict | Verdict |
|---|---|---|---|---|
| RS-1 | Regulator orders a retroactive $2.15 customer-charge refund, 6 months | Correction = void + replacement naming it, posted in an open period (Ryan 10-14; 10-15). Credit goes to the one pot (Kyle 10-30). | "PUC orders" does not fit a city system; city council does. | revise light |
| RS-2 | Base charge typo $18.50 → $8.50 found after bills mail | Same correction mechanics. A save is refused if the record changed since load (Kyle K-01) — irrelevant here but the "close the erroneous record" step is now "a new dated version"; frozen rows are never edited. | none | revise light |
| RS-3 | Tariff changes Nov 15, mid-cycle split | Consistent. Rate versions also flag bills that went out at a rate other than the one in effect on the 1st (Kyle R-09). Base-charge lines carry coverage dates and days (Ryan 10-14). | none | keep (add the line-arithmetic detail when worked) |
| RI-1 | Gas-cost factor transposed $0.3820 vs $0.3280, 7,200 accounts | Platform keeps the factor and every historical one; the factor is the utility's own value (Kyle 10-14 Q6; standing rule that the utility owns regulated values). "PSC requires corrected filing in 10 business days" is a filing duty, not ours. A gas-cost rider line carries no commodity rate (Ryan 10-14). | "state PSC" filing assumption | revise light |
| RI-2 | Tier breakpoint 500 vs 50, 4 months undercollected | Cap "12 months for this state" is invented; the cap comes from the place's rule row, and Texas gas treats rate misapplication as a 6-month collectability limit (backbilling table). City system: its tariff. | yes — a stated universal cap | revise heavy |
| GF-1 | Supplier corrects BTU factor for Zone A | Zones are tenant-defined, one dated zone set per factor (Kyle K-02). Usage lines carry factor, CCF and therms (Ryan 10-14). | none | revise light |
| GF-2 | Pressure factor wrong for East Industrial zone | Separate pressure zone set (Kyle K-02). | none | revise light |
| GF-3 | Meter wrongly flagged temperature-compensated, 14 months | Meters have a dated install history per location (Kyle R-10). "Cap enforced automatically" needs the place's rule row. | implicit cap | revise light |
| Z-1 | Annexation moves 340 premises to "City" zone (5.5% franchise fee, city tax) | Locations are immutable; zone and tax links are dated records (R-10, Q1). A location links to **every** jurisdiction it sits in. New tax rates go live only after an operator signs off the staged Comptroller file (Kyle 10-14 Q1). Franchise fee is a percentage of all billed lines except excluded ones (pipeline safety fee) and is **not** in the sales-tax base (Kyle 10-14 Q2). | none, but the franchise fee is assumed for a city system — a city-owned utility may not charge itself one | revise heavy |
| Z-2 | Weather station decommissioned; 1,800 premises remapped | Weather zone set per factor (K-02). No other ruling. | none | revise light |
| Z-3 | BTU zone redrawn March 1 | "Utility's gas cost reconciliation is clean" — reconciliation is the utility's (Q6). | none | revise light |
| RC-1 | Home business reclassified residential, 18 months back | Rate assignment is a dated, add-only history (R-09). "Refunded if above the minimum refund threshold" — credits are one pot; refunds come from the net position (Kyle 10-30; Ryan 11-01: the core nets across payments before refunding). | "regulatory notice in states with refund timelines" — fine as generic | revise light |
| RC-2 | Auto-migration to high-use schedule failed for 8 months | R-09 add-only history. Consistent with the rate-class migration table. | none | keep |
| M-1 | Multiplier 1.0 should be 1.5, 14 months | Cap stated as "12 months residential / 36 commercial"; Texas gas meter error is shorter of 6 months or time since last test; city system: tariff. Meter test fee depends on test outcome, with tolerance and fee as rule data (Kyle K-06). | yes — invented cap; the worked delta would be wrong for Texas | revise heavy |
| M-2 | Multiplier entered 3 months early at meter swap | Swap is a new install row in the meter's dated history (R-10). Conclusion (no bill changes) still holds. | none | revise light |
| W-1 | NOAA restates HDDs; WNA under-credited | Fine. Table names go. | none | revise light |
| W-2 | 30-year WNA normals updated | "State PSC requires gas distributors update every 10 years" — the normals are the utility's tariff values (utility owns regulated values). | assumes a state-commission WNA regime | revise light |
| W-3 | WNA deadband 5% vs 10% for 2 years | "12-month cap" invented. Also a clawback of credits is an undercharge back-bill: the place's rule row decides. | yes | revise light |
| T-1 | City tax 3.5% should be 3.0% | Remittance correction and "refund due from the city" are outside the platform; it holds only billed/collected liability (Kyle 10-14 Q4). Rates go live only with sign-off (Q1). Rounding: half-up to the cent, 4-decimal intermediate math (Kyle K-06). Every charge declares its tax status; tax applies only when item and customer are both taxable for that service type (Q5). | none | revise heavy |
| T-2 | County special district fee added, 3 months retroactive | Jurisdiction is a place; location links to every one it sits in (Q1). "Backbilling cap 24 months" invented. | invented cap | revise light |
| F-1 | Franchise fee 4% → 3.5% retroactive | Fee base is all billed lines except excluded ones; base type picked per jurisdiction with no default (Q2, Q3). Remittance is liability only (Q4). | none | revise light |
| F-2 | Annexing city adds 3% franchise fee | Same. "Utility remits in February" is outside the platform. | none | revise light |
| PGA-1 | Regulator finds non-recoverable cost in the gas-cost factor | Factor is the utility's; a correction is a new dated factor and a rebill using it (Q6). Unaccounted-for gas cap is out of scope (Kyle 10-14 Q7). | "PSC" framing | revise light |
| PGA-2 | Deferred account true-up needs historical rates | **Out of scope.** Gas purchases, the deferred balance, carrying cost and the annual true-up are not platform records (Kyle 10-14 Q6). What survives: export billed gas-cost revenue and volumes per period, at the factor billed. | — | obsolete (salvage the export as a new, smaller scenario) |
| S-1 | Attorney General subpoena for 47 bills' inputs | Strengthened: each line carries its own arithmetic at issue (Ryan 10-14). | none | keep |
| S-2 | Dry-run rebill in "original world" vs "corrected world" | Consistent. Correction invoice names the void (Ryan 10-14). | none | keep |

### Document verdict

**Revise heavy if reused as scenario material; keep as design rationale.** As an argument for two time axes it is settled and can stay with a dated note pointing to the rulings above. As scenarios it lacks inputs and expected outputs, states five invented look-back caps, and assumes a state commission behind every rate. Best reuse: treat the 26 situations as a seed list for the cancel-rebill and correction family, and write each one fresh with a named place, the place's rule row, and a bill worked to the cent. Drop PGA-2 except for the export.

---

## Part 2. `configurable-rules-scenario-strategy.md`

### The plan

The strategy covers everything that is not an invariant: tenant-configurable rules, multi-step workflows, and fixed feature behaviour (treated as a rule with one allowed value). It runs alongside the invariant strategy (`scenario-mapping-strategy.md`); a final pass merges duplicates between them.

**Four layers, each feeding the next:**

1. **Configuration catalog.** Every configurable knob at every level (tenant, customer, account, location, meter, rate schedule, customer class, jurisdiction), with allowed values, default, whether it is regulated, and whether it needs dating. Expected 300–500 entries.
2. **Decision tables.** One markdown table per rule-heavy area, in the DMN style: named inputs and outputs, an explicit "hit policy" (what happens when more than one row matches), one row per case, open questions, a test note. Each table also carries dates on both time axes. The reason given: overlap behaviour is itself the rule, the format suits expert review, it would import into a rules engine (Drools, Camunda) later, and each row is a test case.
3. **Workflow specifications.** Use-case style (main flow, alternative flows, exception flows); decision points point to the tables.
4. **Scenario derivation.** One scenario per catalog value (plus a "rejected value" scenario), one per table row, one per workflow flow, then parametric children across five axes: Texas sub-jurisdiction (incorporated city, environs, special rate area), customer class, rate schedule type, meter type, read source. Each scenario gets an `SCN-NNNN` id and uses named fixtures from `test-fixtures/`.

**Sessions:** Session 1 the catalog (with a mid-point recon file); Session 2 the cluster and workflow inventory; a fixture-catalog session; then Sessions 3A–3M, one rule domain each, producing tables, workflows and that domain's scenarios; then unification with the invariant strategy; then a combined coverage audit. `execution-kickoff.md` orders these as work units 1–12.

### What was done and what was not

| Step | Status | Evidence |
|---|---|---|
| Catalog (Session 1) | done, 125 entries (not 300–500); Kyle reviewed 2026-06-12 | `configuration-catalog.md`, `de-review-answers.md` |
| Cluster and workflow inventory (Session 2) | done: 42 clusters in 13 domains, 80 workflows; Kyle reviewed 2026-06-19 | `cluster-and-workflow-inventory.md`, `de-review-answers-8-11.md` |
| Fixture catalog | done, 14 files, Texas only | `test-fixtures/` |
| Sessions 3A–3M, decision tables | done, 60 tables (some clusters split) | `decision-tables/` |
| Sessions 3A–3M, workflows | done, 80 workflows | `workflows/` (audited by someone else); coda brief says "80 named, 80 produced" |
| Sessions 3A–3M, derived scenarios (Layer 4) | **not done.** No table or workflow has a Scenarios section, and no `SCN-` id exists anywhere in GBM. Tables end with a "Test note" that sketches the first few fixtures. | grep |
| Invariant strategy methods 2–5 (state machines, exception paths, persona matrix, parametric expansion) | not done; the output folders do not exist | `ls` |
| Unification and combined coverage audit | not done | — |

In practice the tables turned into **schema-gap audits**. Most open questions say "this column does not exist" or "this default is wrong", and many were later fixed by the v5.4.x patches (the deposits table, line-level payment application, tax jurisdictions, reading supersession, the invoice-exception routing columns). So many open questions are now stale in either direction.

### What the digest and standing rules change in the strategy

- **"Launch scope: Texas only… the four-layer architecture supports multi-state expansion without restructuring; v1 just doesn't exercise it."** This conflicts with the standing rule (Kyle 10-15: build for Texas first, never hard-code Texas). The 2026-09-28 Texas-only architecture audit found that 13 of the 60 tables carry Texas values in their rows and none takes a state as input, and it asked that every regulated table get a (state, service) input. The parametric axis "Texas sub-jurisdiction" should become "place (state, city overlay, inside/outside city limits) and owner type". (Kyle K-07: city-owned systems are outside the state gas-utility law, so owner type is a key.)
- **The example "deposit at 50% of annual billing is rejected because Texas caps deposits at 1/6"** treats a Texas figure as a platform rule and applies §7.45 to every tenant. For a city system the cap is its tariff row, or nothing.
- **Decision tables as the rule's home.** Superseded by the rule-terms convention (Ryan 2026-10-06): a law or tariff row has a typed key, dates, a citation and validated `terms`; the logic is a named strategy in the C# core; **golden scenarios sit beside each law row** as its executable meaning. The strategy's "every row is a test case" idea survives as those golden scenarios. Its "import into Drools/Camunda later" idea does not: the core's strategies are the engine.
- **"Decision tables are bi-temporal files with Valid from / Recorded at headers."** Superseded: law and tariff rows are dated and frozen for ever in the database; the table files are not the versioned artefact.
- **Catalog entries built on tenant columns.** Several are now retired or reversed: payment allocation order beyond oldest-first, "apply overpayment to specific invoices" (Kyle K-05), stored payment/credit counters (10-15), stored running balance (Ryan 10-13), stored late-fee flags (10-18 design), the tax default of "not taxable" (Kyle Q5), early-pay discounts (Kyle K-06).
- **Fixed behaviour vs "schema represents, core evaluates".** The strategy expects scenarios to assert system outcomes; under the standing rule the expected result is a core output plus what the database records.
- **Scenario timing.** Ryan (10-29) put scenarios beside the schema, but families still changing (cash, disputes, collections, tax, gas cost, zones, reads) are written after their patches mirror.

### Verdict

**Rewrite** the plan; keep it as history. Reusable: the Level-2 specificity standard (name the values), the "hit policy is the rule" insight (now a property of each core strategy), the coverage dimensions (pipeline stage, failure mode, persona), and the catalog and inventory as source lists. Replace: Texas-only scope, files as the versioned rule store, rules-engine import, tenant-column catalog entries, and the per-row scenario factory, with "golden scenarios per law/tariff row, plus workflow scenarios written after each family's patch mirrors".

---

## Part 3. `configurable-rules/decision-tables/` (60 tables)

### Does the decision-table form still fit?

Partly. **The form is superseded as the home of a rule; its content survives as input to golden scenarios.**

- What still fits: the input/output lists map onto a strategy's parameters and a law row's `terms`; the explicit overlap policy (priority, first-match, collect, unique) is exactly what a core strategy must state; the "unevaluable blocks" rows (collections bypass rank 9, disconnect rank 10, cold-weather rows 3–4, write-off rank 8) match the 10-18 design where a missing input never yields "eligible". Each row is a natural golden scenario once it names a place's row and real values.
- What does not fit: (1) the tables mix three things the convention separates — statutory values (Texas figures written into rows), the utility's tariff choices, and the platform's mechanism. Under rule-terms, the values go into dated law/tariff rows keyed by place and owner type, the mechanism into a named core strategy, and the table rows into golden scenarios beside each row. (2) Inputs are mostly schema columns ("`tenants.payment_allocation_strategy`", "`customers.deposit_amount`"), many since retired; scenarios should describe rules, not tables. (3) None takes a state, place or owner type as input (Texas audit 09-28), and 13 carry Texas values in their rows. (4) Many are first-match lists over a tenant enum; the convention picks a strategy by name in `terms`, never a branch on state.
- Practical answer: do not maintain them as tables. When a family's rule rows are written, mine the matching tables for cases, boundary values and failure stories, then write golden scenarios against the row and strategy.

**Cross-cutting staleness:** most open questions are schema-gap findings dated July–September. Several gaps have since been closed by patches (the deposits table and its single representation, per the decision log entry that cites tables #53–#55; line-level payment application; tax jurisdictions as places; reading supersession; invoice-exception routing columns for table #35; tamper and pressure-class columns). Others were reversed by rulings. Treat every open question as unverified until checked against `tu.sql`.

**Worked numbers:** almost none. Rows hold conditions and formulas. A few test notes give fixture amounts (payment allocation: $150 regulated arrears, $100 appliance plan, $100 pledge; payment allocation: $200 agency check vs $200 customer check). Kyle's dollar check (10-29) has nothing to check yet.

### By cluster

#### A. Payments and cash (4 tables): `payment-posting-allocation`, `overpayment-and-credit-disposition`, `nsf-and-ach-return-handling`, `autopay-eligibility-and-failure`

Covers how a payment is spread over open charges, what happens to what is left, how a bank return is handled, and when an auto-pay draft runs.

- **Payment posting allocation.** Contradicted: the tenant orders `newest_first`, `largest_first` and `manual_only` are retired; payments go oldest bill first; a customer may designate a payment only as a deposit or a bill, never for a charge (Kyle K-05, 10-15). Application is stored per bill line, and a wrong one is undone by a negative application naming it (10-15 drafting) — this answers its open question 2. Regulated lines are paid before unregulated as a fixed term no tariff can turn off; the order within a bill is a tariff row, and Texas has no law row for it (10-16). The table *takes a position* that the regulated-first floor beats an agency pledge's restriction; that conflict is **not ruled** and scenarios must not assume an answer (10-16 open item for Kyle). Unmatched cash (suspense) and agency pledges come in a later patch (-24) and are never applied to a guessed account (Ryan 10-16). Texas-only: cites a "Texas oldest-first convention" that DE-2 found does not exist. **Verdict: rewrite** (after the cash patches mirror).
- **Overpayment and credit disposition.** Contradicted on almost every row. `apply_to_specific_invoices` is retired (K-05). A leftover becomes a credit **only if the customer approves** at payment time, recorded as an add-only approval; otherwise it is not taken (Kyle R-06, 10-15). "Donated" and "refunded" are not stored statuses; they are read from positions (Ryan 10-21). `applied_amount`/`remaining_amount` are dropped; they are sums of application rows (10-15). All of a customer's credits are one pot shown as one net balance; a positive credit never shows as refundable while the customer owes (Kyle K-11, 10-30), and the database nets only within a payment, the core nets across payments before refunding or escheating (Ryan 11-01). A refund that comes back after escheat becomes a new credit (Ryan 10-21). Texas-only: escheat dormancy and the $250 due-diligence threshold are Texas unclaimed-property values written into rows. **Verdict: rewrite.**
- **NSF and ACH returns.** The NACHA return-code routing (do not re-debit unauthorised codes; notice-of-change is not a failure; unknown codes go to an operator) is still sound and is federal, not Texas. Narrowed: a bounce is refused while a refund of that payment is pending, until an operator cancels the refund (Kyle K-10, 10-21); a bounce is capped at the payment less earlier reversals, refunds do not reduce that cap (K-10 caps; worked: $50 paid, $30 refunded, $50 bounce, customer owes $30); what an overpayment credit already paid out stands and what it held goes with the bounce (10-21 r4); the shortfall uses up the customer's total credit (K-11). A bounce names the ledger reversal behind it and status only moves forward (Ryan W2-Q1). A refund hold during the return window is tenant policy, off by default (K-10 Q3). Missing from the table entirely: refund-then-bounce. **Verdict: revise heavy.**
- **Autopay eligibility and failure.** No ruling touches it. Open questions are schema gaps (disable threshold, authorisation record, misnamed status) that may or may not be closed. **Verdict: keep** (re-check open questions against `tu.sql`).

Form fit: allocation order and the regulated-first floor are a tariff row plus a fixed core term; disposition is core strategy over add-only rows. Tables superseded.

#### B. Deposits (3 tables): `deposit-eligibility-and-waiver`, `deposit-refund-and-interest`, `deposit-alternatives-and-triggers`

Covers who must pay a deposit, the mandatory waivers, the cap, refund triggers and interest, and non-cash instruments and extra-deposit triggers.

- Contradicted / superseded: these rows write §7.45 duties as mandatory for every tenant (family-violence waiver, 65-plus waiver, good-payment waiver, 1/6 annual billing cap, 12-clean-bills automatic refund, 30-day interest threshold). City-owned systems are outside §7.45 (Kyle K-07); their policy is their tariff, with no assumed defaults. Whether the 65-plus waiver is mandatory or tariff by tariff is still open (Texas audit 09-28). Deposits were rebuilt under the rule-terms convention (the -15 rewrite): the deposit rule is a terms family with law and tariff rows, the boundary cases in `tally-utility-scenarios/application/deposits-rules-for-the-core.md` are the first golden scenarios, and the utility's own interest rate stays the utility's (Florida per-customer-type ruling; standing rule on regulated values). Open questions about "no deposits table" and "six representations" were closed by patch (decision log cites tables #53–#55). A deposit or reconnect fee is a one-off charge with a reason code (Kyle R-01). A customer may designate a payment as a deposit (K-05).
- Still useful: the bankruptcy §366 adequate-assurance basis (federal), "a deposit's basis decides its refund rule", and "a mandatory refund must not be routed into the small-balance disposition".
- **Verdict: obsolete as tables** (superseded by the deposits terms family and `deposits-rules-for-the-core.md`); mine the §366 and basis points into that file if missing.

#### C. Collections, disconnection and protections (8 tables): `collections-bypass-evaluation`, `dunning-step-routing`, `disconnect-eligibility`, `cold-weather-moratorium`, `reconnect-eligibility-and-fees`, `write-off-eligibility`, `customer-credit-scoring`, `dpa-eligibility-and-breach`

Covers what blocks a collection step, the dunning ladder, whether a disconnect may be ordered and executed, the extreme-weather moratorium, reconnection and fees, write-off bases, the credit test, and deferred payment agreements.

- Anticipated correctly: "unevaluable blocks" rows; "execution needs its own determination, not the one made at issue" (disconnect rank 0) matches the 10-18 design where executing a disconnect cites its own decision; "dispute protects the disputed amount" (bypass rank 6, disconnect rank 9) matches 10-18.
- Contradicted / narrowed:
  - The core writes a **collections decision** each time it decides an act may happen (notice, late fee, disconnect order, disconnect execution, referral), outcome eligible / blocked / unevaluable, one row per change of answer, and every act cites one (10-18 design; standing rule on storing decisions on change). The tables' "boolean nothing maintains" findings are superseded.
  - Death is a dated customer status with a hold that blocks shutoff and collections, and an exception after a month (Kyle R-08) — **missing** from the bypass and disconnect tables.
  - Program enrollments keep a dated status history; a lapse triggers a notice before protection ends (Kyle R-07).
  - Stored late-fee flags are dropped and the dunning stage moves only with an event behind it (10-18 design); the dunning table runs on `invoices.dunning_stage`.
  - Late-fee rate, base, cap, grace and exempt programs are dated law/tariff rows with a citation (Kyle R-11).
  - The "closed days" calendar is the utility's staffed days, not a holiday list; the 60-plus due-date delay (§182.002, 25 days, no late fee) **does** bind city systems; the extreme-weather trigger uses the forecast *high* (§7.460) — the cold-weather table uses prior-day high and forecast *low* (10-18, pending Kyle).
  - A disconnect order completes only after a matching field visit or a supervisor override with reason and evidence (10-18 design).
  - Write-off: a recovery must name its write-off and the net stays between 0 and the amount written off (10-15/16); aging is balance-forward from the ledger (10-15).
  - Texas-only: §7.45 notice windows, medical hold, elderly day-of-month protection, DPA obligation, §7.460 moratorium and §7.45 credit test are written as universal rows. For city systems these are tariff rows or nothing (K-07). The bankruptcy stay (federal) is fine as a platform rule.
- Collections is a family "still changing" (Ryan 10-29: write scenarios after its patch mirrors).
- **Verdicts:** bypass, dunning, disconnect, cold-weather, DPA: **rewrite** after the collections patch (-26) mirrors, using the tables as source inventory. Reconnect: **revise heavy** (fees as tariff rows with reason codes; wrongful-disconnect and safety holds still sound). Write-off: **revise heavy**. Credit scoring: **revise heavy** (the §7.45 credit test becomes a law row; the FCRA question remains).

#### D. Programs and levelised billing (2 tables): `program-enrollment-eligibility`, `budget-billing-eligibility-and-trueup`

- Program enrollment: dated add-only status history and lapse notice (R-07); death is a status, not a program (R-08); disputes become their own rows and the `pending_dispute` program stops being disconnect-protective (10-18) — row 7 is now wrong; medical, moratorium and pledge rows are §7.45/§7.460 values that do not bind city systems (K-07). **Verdict: revise heavy.**
- Budget billing: no ruling. Note only that its "running balance" means the levelised-billing difference, not the dropped ledger running balance (Ryan 10-13). **Verdict: keep** (re-check open questions).

#### E. Tax and franchise fees (4 tables): `adhoc-charge-taxation`, `tax-application-and-stacking`, `tax-exemption-eligibility`, `franchise-fee-application`

- One-off charge taxation: **reversed.** It resolves taxability through a three-level default chain ending in "Texas-shaped platform defaults" (taxable for service fees, not taxable for penalties). Kyle (10-14 Q5): every charge must declare its tax status; there is no default; tax applies only when item and customer are both taxable for that service type. **Verdict: rewrite.**
- Tax stacking: the four-stage order (settled charges → classify → compose base per jurisdiction → round) survives. Changed: no default of not-taxable (Q5, its open question 1 is now settled the other way); a jurisdiction is a place and a location links to every one it sits in (Q1, its open question 4 settled); franchise fee is not in the sales-tax base (Q2); rounding half-up to the cent with 4-decimal intermediates (K-06, settles open question 3); per-item taxable flags and the franchise rule's `applies_to` merge into one mechanism (Q3, settles open question 2). **Verdict: revise heavy.**
- Tax exemption: already per service type. Changed: an exempt customer still gets a **$0.00 tax line** (Q5) — the table produces an exemption determination but should state the $0 line. Texas residential-gas exemption reasoning belongs in a Texas row. **Verdict: revise light.**
- Franchise fee: changed — fee is a percentage of all billed lines except excluded ones (pipeline safety fee); base type chosen per jurisdiction from a fixed list with **no default** (Q2, Q3); `inside_city_limits` / `franchise_city` give way to dated place links (Q1). The "missing rule is an exception, not $0" rows still hold and match "no row means no rule, and the record says so". **Verdict: revise heavy.**
- Tax is a family still changing (10-29): write scenarios after its patch mirrors.

#### F. Gas cost and weather (3 tables): `pga-application`, `pga-deferred-account-and-trueup`, `wna-applicability-and-calculation`

- Gas-cost application: row 3 applies the unaccounted-for gas cap in billing — **reversed** (Kyle 10-14 Q7: out of scope; the utility applies it before filing its factor). Billing side is just "therms × the approved factor in effect"; transport has no commodity line (still true). **Verdict: revise heavy** (collapses to two rows).
- Deferred account and true-up: **out of scope** (Kyle 10-14 Q6). **Verdict: obsolete.**
- WNA: no ruling; class eligibility is drawn from Atmos/TGS tariffs, i.e. it is tariff-row content, not a platform rule. Weather zone set per factor (K-02). **Verdict: revise light.**

#### G. Corrections, voids and back-billing (4 tables): `correction-and-void-eligibility`, `cancel-rebill-bitemporal`, `backbilling-cap-enforcement`, `adjustment-authorization`

- Correction and void: changed — voiding a never-posted (held) bill posts nothing; voiding a posted bill reverses its charge entry and is refused if none exists (Ryan 10-14); a void reverses what is left of the charge after earlier reversals (10-15 drafting); every reversal names exactly what it undoes and a correction bill names the void it replaces (Ryan 10-14); a draft can be discarded, an issued bill never (Ryan 10-14); correction chains may run to 1,000 deep, past that a new unlinked entry (Ryan 10-17) — the table's "depth > 3 → elevated alert" is a different, still-possible rule. Texas-only: rows 3–5 branch on `service_type = gas` for the full-correction rule; the Texas audit asks that "correction rules keyed on gas" be re-keyed per jurisdiction. **Verdict: revise heavy.**
- Cancel-rebill rate date: still describes the rate-date modes. Narrowed: the gas-cost factor used is the historical one in effect (Q6); rate versions flag bills at a different rate (R-09). **Verdict: revise light.**
- Back-billing cap: the cause list (tampering uncapped, non-registering 3 months, meter error shorter of 6 months or since last test, rate misapplication as a 6-month collectability limit) is good Texas-gas content but is written as the platform rule. Per the Texas audit, the back-billing rule is being rebuilt as platform law rows keyed by place, causes as reference rows, windows as terms; city systems use their tariff (K-07). **Verdict: revise heavy** (becomes the Texas law row's golden scenarios plus a city tariff case and a fictional second state).
- Adjustment authorisation: money is add-only and a correction is a reversal plus a new row (R-05); one-off charges carry a reason code (R-01). The role model is still open. **Verdict: revise light.**

#### H. Rating and tariff engine (9 tables): `rate-item-calculation-dispatch`, `rate-item-dependency-ordering`, `rate-item-override-resolution`, `rate-schedule-applicability`, `rate-class-assignment-and-migration`, `tiered-usage-rating`, `seasonal-rider-scoping`, `mid-period-tariff-change-split`, `partial-period-proration`

Mostly mechanism, which under rule-terms is core strategy — so these fit best as strategy specs with golden cases.

- Override resolution: the `is_taxable` override falls back to `is_taxable_default` — no default is allowed (Q5). **Revise light.**
- Dependency ordering: tax last still holds; franchise fee is not in the sales-tax base (Q2). **Revise light.**
- Schedule applicability and class migration: a customer's rate assignment is a dated add-only history with no overlaps (R-09); neutral "sales"/"transportation" terms with per-jurisdiction labels (K-04, already used). **Revise light.**
- Partial-period proration: a partial base charge must carry coverage dates, days covered, days in period and the policy applied (Ryan 10-14) — add to outputs; the "Texas convention vs prorated default" note becomes a tariff-row question. **Revise light.**
- Calculation dispatch, tiered rating, seasonal riders, mid-period split: no ruling contradicts them; rounding is half-up to the cent, 4-decimal rates (K-06). **Keep.**

#### I. Reads, measurement and estimation (11 tables): `read-auto-approval`, `read-vee-validation`, `read-cycle-reader-routing`, `estimation-policy`, `consecutive-estimate-enforcement`, `statistical-anomaly-detection`, `tamper-detection-response`, `consumption-scaling-and-rollover`, `gas-conversion-and-energy`, `cross-month-factor-application`, `sewer-volume-derivation`

- A replacement reading points at the one it replaced, which is marked superseded with a required reason code (Kyle K-03) — affects any row that "corrects" a read. Estimation rules are dated rule data with a citation (R-11). Reads is a family still changing (10-29).
- Consecutive estimates: the Texas 6-month ceiling is a law row, and a city system's limit is its tariff (K-07). **Revise light.**
- Estimation policy: add the jurisdiction tier its own open question asks for (R-11). **Revise light.**
- Tamper response: "uncapped back-bill for tampering" is a law/tariff value, not platform. **Revise light.**
- Gas conversion: zone sets per factor (K-02); usage lines carry meter factor, CCF and therms (Ryan 10-14). **Revise light.**
- Read auto-approval, VEE validation, reader routing, rollover, cross-month factor, anomaly detection: **keep.**
- Sewer: explicitly deferred (Kyle D3B-3) and the first offer is gas-native (2026-10-02). **Obsolete for now.**

#### J. Pre-mail QA and exceptions (2 tables): `absolute-baseline-qa`, `exception-threshold-and-routing`

- Baseline QA: the revenue baseline is keyed to a Texas commission rate-case figure ("GUD requirement"), which a city system does not have; make it the utility's own expected revenue. **Revise light.**
- Exception routing: the routing outputs were built into the schema (decision log D-2026-08-28-31). **Keep.**

#### K. Billing run, consolidation, delivery and notices (5 tables): `billing-run-read-gating`, `invoice-consolidation`, `delivery-method-routing`, `notice-and-alert-triggering`, `communication-language-format`

- Consolidation: the customer's balance is a sum of ledger rows as of a date (Ryan 10-13), which answers "which side posts". **Revise light.**
- Language and format: row 1 branches on "Texas" for English-plus-Spanish notices; that is a law row keyed by place. Customers can prefer an accessible format, and the format actually sent is recorded (Kyle K-06), which answers its open question 3. **Revise light.**
- Notice triggering: add the lapse notice before a program's protection ends (R-07) and the death-hold exception (R-08). **Revise light.**
- Read gating, delivery routing: **keep.**

#### L. Account lifecycle and field orders (3 tables): `billing-responsibility-resolution`, `service-transition-charges`, `service-order-type-routing`

- Billing responsibility: **reversed at the base.** It resolves the payer from `service_locations.customer_id` and owner/landlord flags. Service locations never change; occupancy is a separate dated record with no overlaps; each premise in a transfer is vacant, held by the owner, or held by a customer (Kyle R-10). Its open questions 1 and 2 are now answered. **Verdict: rewrite.**
- Service transition charges: "vacancy days not computable" is answered by dated occupancy (R-10); base charge partial-period arithmetic (Ryan 10-14). **Revise heavy.**
- Service order routing: meters have a dated install history per location (R-10); otherwise schema-gap findings. **Revise light.**

#### M. Import and admin (2 tables): `import-column-mapping`, `import-error-handling-policy`

No ruling touches them. **Keep** (re-check open questions; setup-table delete blocking, Kyle R-03, may matter to rollback).

### Verdict tally (60 tables)

- **Keep (17):** autopay, budget billing, calculation dispatch, tiered rating, seasonal riders, mid-period split, read auto-approval, VEE validation, reader routing, rollover, cross-month factor, anomaly detection, exception routing, read gating, delivery routing, column mapping, import error policy.
- **Revise light (18):** WNA, cancel-rebill rate date, adjustment authorisation, override resolution, dependency ordering, schedule applicability, class migration, partial-period proration, consecutive estimates, estimation policy, tamper response, gas conversion, baseline QA, consolidation, language and format, notice triggering, tax exemption, service order routing.
- **Revise heavy (11):** NSF/ACH returns, reconnect, write-off, credit scoring, program enrollment, tax stacking, franchise fee, gas-cost application, correction and void, back-billing cap, service transition charges.
- **Rewrite (9):** payment allocation, overpayment and credit, collections bypass, dunning, disconnect eligibility, cold-weather moratorium, DPA, one-off charge taxation, billing responsibility.
- **Obsolete (5):** the three deposit tables (superseded by the deposits terms family), PGA deferred account and true-up (out of scope), sewer (deferred).

(17 + 18 + 11 + 9 + 5 = 60. Where a table sits on a boundary, the per-cluster text is authoritative.)

---

## Part 4. Other files in `configurable-rules/`

There are **no other subfolders** besides `decision-tables/` and `workflows/`. The top-level files are inputs and review records for the work above:

| File | What it is | Note |
|---|---|---|
| `_raw-schema-config-inventory.md` | Session 1 raw walk of 213 config columns and 56 JSON keys | stale: built on the June schema |
| `session-1-recon.md` | Session 1 mid-point recon | line 99 ("invariants, not configurable policies") is named by the Texas audit as the root of the Texas-only framing; needs a dated correction note |
| `configuration-catalog.md` | the Layer 1 catalog, 125 entries | many entries rest on retired tenant columns (allocation strategies, overpayment handling, tax default) |
| `catalog-review-brief.md`, `de-review-answers.md`, `de-review-answers-8-11.md` | Kyle's June reviews (DE-1…11) | historical record; DE-2 "no Texas posting-order mandate" still holds |
| `cluster-and-workflow-inventory.md` | Session 2 inventory | carries the "Texas-launch only; multi-state is a deferred parametric axis" scope guard, now in conflict with the standing rule |
| `cluster-workflow-review-brief.md`, `wu6-*-review-brief.md` (8 files), `d3-2-retraction-and-read-lock-brief.md`, `kyle-cover-note-d3-2.md` | review briefs for Kyle per session | historical; some items still unruled per the coda brief |

---

## Summary of what to do with this material

1. Do not edit any of it in place; add dated correction notes where the Texas audit already asked for them.
2. Use the 26 bi-temporal situations as a seed list for the correction and cancel-rebill family; write each fresh with a place, its rule row, and a bill worked to the cent.
3. Use the decision tables as a source inventory when each family's rule rows are written; their rows become golden scenarios beside law and tariff rows, each run for a Texas place, a city-owned system (its tariff, or no rule), and a fictional second state.
4. Hold cash, collections, tax, gas-cost and reads scenarios until those patches mirror (Ryan 10-29).
5. Unresolved items the scenarios must not assume: who wins when an agency payment's restriction conflicts with regulated-first; the extreme-weather forecast reading; whether the 65-plus deposit waiver is mandatory.
