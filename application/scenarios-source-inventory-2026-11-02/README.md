# Scenario source inventory (2026-11-02)

The scenarios stream's first step, done before any scenario is written: what the existing scenario material in GBM (`gas-billing-memory/application/`) covers, what rulings have changed underneath it since it was written, and which invariants have no scenario. All read-only; nothing in GBM was changed.

## Files here

| File | What it holds |
|---|---|
| `rulings-digest.md` | Every ruling from 2026-10-13 to 2026-11-01 that changes what a scenario should expect, grouped by family, each with date, who ruled and source |
| `audit-invariant-docs-a-to-m.md` | The first 14 per-family docs in `invariant-scenarios/`, one section each |
| `audit-invariant-docs-p-to-w.md` | The other 15 |
| `audit-bitemporal-strategy-decision-tables.md` | `bi-temporal-scenarios.md` (scenario by scenario), `configurable-rules-scenario-strategy.md`, the 60 decision tables |
| `audit-workflows-fixtures.md` | The 80 workflows, the 14 test-fixture files and their strategy doc |

## What the audit found

**1. There are no scenarios yet.** None of the 29 per-family docs contains a scenario. All stopped in July at the first step of their own method: a list of the ways scenarios would vary, awaiting Kyle's review. No `SCN-` ID exists anywhere in GBM; the scenario layer of the configurable-rules strategy was never started either. The only material with real numbers is `bi-temporal-scenarios.md` (26 stories with rates and account counts), and it argues for keeping two time axes rather than giving inputs and an expected bill. Nothing anywhere is worked to the cent, so Kyle has nothing to check yet.

**2. Most of the outline has moved under later rulings.** Counting every unit audited:

| Material | Keep | Revise light | Revise heavy | Rewrite | Obsolete / history |
|---|---|---|---|---|---|
| 29 per-family outlines | 1 (tenant isolation) | 7 | 16 | 4 (collections pipeline, Texas collections, Texas sub-jurisdiction and rate change, reversal lineage) | 1 (the July review brief, kept as history) |
| 26 date-tracking stories | 4 | 17 | 4 | — | 1 (gas-cost deferred account) |
| 60 decision tables | 17 | 18 | 11 | 9 | 5 |
| 80 workflows | 3 | 42 | 28 | 5 | 2 |
| 14 fixture files + strategy | 1 | 3 | 8 | 2 | 1 |

The changes that reach furthest:
- **Texas state rules written as universal.** The outlines, workflows and fixtures treat the Texas regulator's customer-service rules (16 TAC §7.45: deposits, backbilling, disconnect protections, bill format) as binding on every utility. They do not bind city-owned gas systems, our first customers; a city's policy is its own tariff row, or nothing. Invented look-back caps (12, 24, 36 months) appear in several date-tracking stories.
- **Cash.** Stored running balance and stored applied/remaining amounts dropped (Ryan 10-13); money add-only with forward-only status (Kyle 10-15); "refunded" and "donated" derived, not stored (Ryan 10-21); a refund is its own movement, not an undo (Kyle 10-21); all of a customer's credits are one balance (Kyle 10-30); oldest bill first, regulated lines first (Kyle 10-15).
- **Gas cost is billing side only** (Kyle 10-14): the deferred account, true-up and lost-gas cap are not platform records.
- **Tax**: every charge declares taxability with no default; an exempt customer still gets a $0.00 tax line; a location links to every jurisdiction it sits in (Kyle 10-14).
- **Collections and disputes**: each act cites a stored decision; a missing input blocks; a dispute protects the disputed amount only (Ryan 10-18).
- **Service locations never change**; who occupies them is a dated record (Kyle 10-15).

**3. The fixtures can't price a bill.** The named cast (tenants, cities, customers, rates) was never signed off, is Texas-only by design, and has no volumetric rates, gas-cost factors, pipeline safety fee or per-line tax status. The two small city-owned systems in it (Marfa, Brenham) have no customers, rates or meters. A small rebuilt cast is needed before worked bills: one or two city-owned systems with full tariffs, one regulated utility as contrast, and one non-Texas set of law rows to prove nothing is hard-coded.

**4. Coverage on paper.** 134 of 135 invariants are named in some outline. CI-028 (consumption computed once per read pair) is named nowhere. Named once or twice only: CI-002 (correction versus retraction), CI-007 (the rate a cancel-rebill uses is explicit), CI-027 (which meter and service point a read belongs to), CI-079 (no Texas disconnect before a day the utility is closed). Being named in an outline is not coverage; the real coverage audit comes last, against written scenarios (handoff step 6).

**5. What is worth keeping.** The axes lists as starting outlines once corrected; the four keepable date-tracking stories (subpoena, dry-run rebill, mid-period tariff split, automatic schedule migration); the workflows' main and failure paths and test ideas (not their schema-gap lists); the decision tables' rows as candidate golden examples beside each law row; the fixture ID scheme and customer personas.

## Questions the audit raised (not yet asked)

- Bankruptcy versus oldest-bill-first: could a post-petition payment land on pre-petition debt? (audit A-M, bankruptcy)
- Whether the bad-debt rider true-up is outside the platform like the gas-cost true-up. (audit A-M)
- Whether the Texas bilingual-notice rule (CI-088), rate-change filing rule (CI-087) and pipeline safety fee reach city-owned systems. (audits A-M, P-W)
- The schema still has a per-service cap on the pipeline safety fee; Kyle said there is no fixed cap. (audit P-W; rates stream)
- An agency pledge versus the regulated-first floor in payment posting is not ruled. (audit decision tables; -24)
- Pending Kyle already: the cold-weather test's forecast high, and the 60-and-over due-date delay for city systems.
