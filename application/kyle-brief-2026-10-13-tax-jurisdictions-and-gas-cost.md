---
title: TallyUtility — tax jurisdictions (A-8) and the gas-cost ledger: questions for Kyle
type: brief
status: READY TO SEND (Ryan approved 2026-10-13). Not yet answered.
created: 2026-10-13
blocks: CI-044 and CI-045 (franchise fee traceability, tax stacking), the tax slice of CI-001/CI-004, CI-033 and CI-036 (PGA pass-through and the deferred gas-cost account)
---

# Tax jurisdictions and the gas-cost ledger — what we need from you

2026-10-13 · Ryan Moultrup

Kyle — two things are held waiting on you. Neither is a rule question about Texas law. Both are "what does the database have to hold?" questions. A one-line answer to each is enough, and where you tell us a question is a non-issue, that is a useful answer too.

## What we need from you

| # | Question | Answer with |
| --- | --- | --- |
| 1 | Is a tax jurisdiction just a *place* (a state, county, city, transit authority or special district), with its tax facts attached to it? | **Yes** or **No** (and what a separate table must hold that a place cannot) |
| 2 | Where does a jurisdiction's tax stack come from — which taxes it levies on a gas bill, on what base, in what order, and whether one tax can be charged on top of another? | **Law, per jurisdiction**, **utility's tariff**, or **both** (and who owns which part) |
| 3 | A franchise fee is set by city ordinance and, in the schema today, can be limited to a base ("applies to") *and* excluded line by line ("is taxable"). Which one governs, and can the fee base be "gross revenue minus the pipeline safety fee"? | **"Applies to" governs**, **line flags govern**, or **a new base rule** |
| 4 | With the platform a receivables subledger that exports (your D-2), what must we **hold** for taxes and franchise fees owed to each jurisdiction? | **Per-line amounts by jurisdiction only** (a report reconciles them), or **a remittance record** (what was remitted, when, to whom) |
| 5 | A charge with no tax classification currently defaults to *not taxable*, silently. Should a charge be impossible to create without an explicit tax classification? | **Require it** or **keep the default** |
| 6 | Must the platform hold the utility's gas purchases, a deferred gas-cost balance per rate class, its carrying cost and the annual true-up as records? | **Hold them**, or **no — we apply the factor and keep a monthly reconciliation snapshot; the utility's own books carry the balance** |
| 7 | Is there a cap on unaccounted-for gas that can be passed through, and where does its value live? | **A number per state** (which one), or **none that matters** |

Questions 1 to 5 are the tax side (the old "A-8"). Questions 6 and 7 are the gas-cost side, which we separated from the rest of the finance work because your D-2 ruling doesn't say whether it covers them.

## Where things stand

**A place is already a jurisdiction.** Since the places work landed (v5.4.2-16), a premise is placed in dated, cited places on two separate axes, *regulatory* and *tax*. The kinds of place are state, county, municipality, extraterritorial area, limited-purpose area, unincorporated area, special-purpose district and transit authority. A place can carry dated facts: its sales-tax rate (as a fraction, effective-dated as the authority publishes it), whether its sales tax reaches residential gas, a district's type, a city's census population (for the gross-receipts bands in Tax Code §182.022), whether a city kept original gas-rate jurisdiction. Every fact and every membership carries its source. Before this, the plan was a separate `tax_jurisdictions` table. We think that table is now mostly a duplicate of a place, but we don't want to decide that for you.

**Franchise fees are still keyed to a city *name* typed as text.** The franchise fee rule table has the fee percentage, what it applies to, the customer types, the ordinance reference and the remittance frequency, and it is bi-temporal. It has no link to a place and no link from a bill line back to the rule that produced it. There are no rows yet.

**What a bill's tax lines look like today.** The bill records, for every tax or percentage line, which lines it was computed on. That part is built and checked. What is missing is the *per-jurisdiction* stack: which taxes a jurisdiction levies, in what order, and whether a tax may be charged on another tax. Your tax stacking decision table says Texas has no tax on tax unless a jurisdiction declares it; nothing in the database can yet say "this jurisdiction declares it".

## Question 1 — Is a jurisdiction just a place?

**Our proposal.** Yes. No separate tax jurisdictions table. A premise's tax stack is the set of places it belongs to on the tax axis, on the bill date. Whatever else a jurisdiction needs (the taxes it levies, their order) becomes more dated facts on the place, or a law row keyed to it, like the deposit and backbilling law.

**What would make it a no.** Something a tax authority has that a place cannot carry: a separate filing identity, a remittance account, an authority that spans several places, or an effective date that differs from the place's own. If you know of one, tell us what it is.

## Question 2 — The tax stack

A premise can sit in a state, a county, a city, a transit authority and a special district at once. Each place carries its own rate and a fact for whether its tax reaches residential gas, so what is levied differs by place. We want to know where the *definition* of the stack lives: which taxes apply together, on what base, in what order.

| Option | Who owns it | Fits when |
| --- | --- | --- |
| Law, per jurisdiction | The platform holds it as a law row, like deposits | The stack is the same for every utility serving the place |
| The utility's tariff | Each utility records its own | Utilities differ in how they apply it |
| Both | Law sets what is levied; the tariff sets how the utility itemizes it | Both are true |

Our default, from your decision table, is "no tax on tax unless the jurisdiction declares it". We would keep it as the default and let a jurisdiction's row declare otherwise.

## Question 3 — Franchise fee: which base governs

Today two mechanisms describe one concept. The fee rule's "applies to" (four values) says what the fee is charged on. Separately, each charge on a bill has its own taxable flag. Your decision table surfaced that none of the four "applies to" values can say "gross revenue minus the pipeline safety fee", the carve-out 16 TAC §8.201 requires. We also want to link the rule to the city as a place (not typed text) and put the rule on the bill line, so every franchise line says which rule produced it.

Related, smaller: when a premise's city differs between the service location and the rate schedule, which one wins for the franchise fee? (This was open item 4 in your decision table session.)

## Question 4 — What we hold for remittances

The utility collects tax and franchise fees and remits them. Under D-2 we are the receivables subledger that exports. The question is how much of the remittance side lives with us.

| Option | We hold | Cost |
| --- | --- | --- |
| Lines only | Each bill line, tagged with the jurisdiction and rule that produced it; a report totals them per jurisdiction per period | Small. Reconciliation against what the utility actually remitted is done in its books |
| Remittance record | The above, plus a record of each remittance made and a check against what was collected | Larger. We become a second source of truth for remittance |

Our preference, as input only: **lines only**. It matches D-2's reasoning (the utility already runs an accounting system), and the remittance record can be added later without changing what we store on bills.

## Question 5 — The silent not-taxable default

A new charge with no explicit tax classification is treated as not taxable. Nothing distinguishes "decided: not taxable" from "never decided". That under-collects, which is the failure CI-045 names. We would make the classification a required choice with no default. The cost is a little more work when someone adds a charge. A smaller companion question: the old customer-level "tax exempt" flag still sits beside the dated exemption certificates, and nothing reads it. We propose to retire it. Say so if there is a reason not to.

## Question 6 — The gas-cost side

This is the part of the finance work Ryan asked us to bring to you separately. Gas purchases are what the utility pays its suppliers. The deferred balance is the difference between that cost and what the purchased-gas factor has recovered, per rate class; it carries interest, and there is an annual true-up.

What exists today: the monthly reconciliation snapshot (immutable input rows plus a threshold) and the factor applied to each bill. What does not: gas purchases, the deferred balance per class, carrying cost, the annual true-up.

| Option | We hold | The utility's own books hold |
| --- | --- | --- |
| A | The factor applied to bills and the monthly reconciliation snapshot | Purchases, the deferred balance, carrying cost, the true-up |
| B | All of the above in our schema | Nothing the PGA process needs |

Our preference, as input only: **A**, if the utility already runs gas cost in its own accounting. It follows D-2 (we are not the general ledger) and avoids us owning the utility's gas accounting. B is right if utilities expect the platform to run the whole PGA cycle.

## Question 7 — Unaccounted-for gas

CI-033 says a cap on the unaccounted-for gas that may be passed through is a per-state value, and the schema has nowhere to put it. If it exists in Texas, give us the figure and its source and we will record it as a law row. If it varies by tariff rather than by law, say so.

## Why these matter

Until Questions 1 to 5 are answered, the franchise fee records can't be tied to a place or a bill line, and the tax slice of the date-effective work stays open. Until 6 and 7 are answered, the PGA deferred account stays unbuilt. None of the other open work depends on these.

## Not asked here, queued for later

Other items waiting on you, held back so this is not a long list: the zone model for BTU, pressure and rate zones; which of three reading-supersede columns is canonical; transport versus sales schedule vocabulary and the pipeline safety fee cap figure ($1.00 or $0.50); earmarking versus tariff posting order for payments; the concurrent-assertion question (Q-1); and which deposit and disconnect protections apply to city-owned gas by tariff rather than by 16 TAC 7.45. We will send these as separate short briefs.
