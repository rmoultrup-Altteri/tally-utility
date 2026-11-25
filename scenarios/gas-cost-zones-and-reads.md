# Gas cost, zones and factors, and meter reads

What the gas costs on a bill, the factors that turn a meter's raw reading into billed volume, and the readings themselves: estimates, re-reads, rollovers, meter changes. Invariants: CI-033 – CI-035 (the gas cost on the bill), CI-020 – CI-022, CI-026, CI-029 (zones, factors, rollover), CI-024, CI-025, CI-027, CI-030, CI-031, CI-112 – CI-114 (reads, replacements, estimates). **Written ahead of its patches** (Ryan, 2026-11-25): the rates stream's gas cost billing side, zones and factor tables, and read ownership and replacement reads are on its list but not claimed. Each scenario is written to the rulings and says what is not built. The billing pipeline (`billing-pipeline-and-charge-composition.md`) already covers a gas cost credit and a pressure factor (SCN-0001, SCN-0055); dated factors are SCN-0078; keyed-wrong reads are `cancel-rebill.md` SCN-0002, 0027.

**Common to every scenario here.**
- **Gas cost is the billing side only.** The platform holds each approved gas cost figure, what was billed under it and the volumes. It keeps every past figure, so a rebill uses the figure the original bill used. The utility's gas purchases, its over- or under-recovered balance and any cap on lost gas stay in its own accounting (Kyle 10-14, answers 6 and 7). The utility does its reconciliation from the platform's billing-side record (SCN-0134).
- **One figure per billing month.** A gas cost figure applies to a whole billing month, is never split by days, and cannot be changed once locked (Kyle 11-03, answer 1). A bill's billing month is the month it is issued, at all three cast utilities (`cast.md` §6). Every other rate on a bill is read at its period's last day (the bill snapshot's rule). The gas cost figure is picked by the billing month instead, and the bill records the month and the figure.
- **A factor is stored with the raw quantity it multiplied** (Ryan 2026-11-04). A bill line shows the raw reading, each factor and the billed volume. All three utilities bill in Mcf, so no heating value or therm figures appear. No cast utility bills in an energy unit or has weather normalization; those wait for Gulf Plains' tariff and the weather family.
- **A reading is never overwritten once billed.** A re-read is a new reading that replaces the earlier one, names it, and states a reason from Kyle's list: re-read for high or low usage, re-read for a zero or missing read, re-read after an access problem, meter malfunction, estimate replaced by an actual, dispute recheck, tamper investigation, wrong meter, typo correction, other. Both readings stay (Kyle 08-18, D-5; Kyle 10-15, K-03). A reading's history stays with the meter and with the address (Kyle 08-18, D-3; Kyle 10-15, R-10).
- **Texas's meter-reading rule binds only Gulf Plains.** 16 TAC §7.45 sets standards for residential and small commercial gas service by a regulated utility. City systems such as Pecan Flat and Bluebonnet are not bound by it, even for customers outside the city limits; their tariffs say nothing about estimates, so their settings in `cast.md` §6 are invented.
- **Dates** are 2026 unless stated. Every value in `cast.md` §6 is **invented**. New customers: BB-17, BB-18, BB-19, GP-08 (`cast.md`). Each scenario stands alone unless it says it continues another.

---

## Gas cost

### SCN-0130 — The gas cost figure a bill uses is its billing month's, not the month the gas was used

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built:** a gas cost figure is a dated rate version today, with no billing month and no lock (the rates stream's gas cost billing side).
*Rule:* a bill uses the gas cost figure locked for its billing month, the month it is issued; the whole bill uses that one figure; the bill records the month and the figure. Sources: Kyle 11-03, answer 1; `cast.md` §2 and §6 (the figure locked at a month's end applies to bills issued in the next).

**Given** Bluebonnet. The figure for bills issued in November is $0.42; for December, $0.58. (a) BB-01 (R-U, inside the city): period Oct 15 – Nov 14, 6.0 Mcf, issued Nov 16 (the reference bill). (b) BB-17 (R-U, inside the city): period Nov 1 – 30, read Nov 30, 7.0 Mcf, issued Wed Dec 2.

**When** both bills are computed.

**Then**

| Line | (a) BB-01, November billing month | (b) BB-17, December billing month |
|---|---|---|
| Customer charge | $12.80 | $12.80 |
| Distribution | 6.0 × $2.96 = $17.76 | 7.0 × $2.96 = $20.72 |
| Commodity charge | 6.0 × $5.35 = $32.10 | 7.0 × $5.35 = $37.45 |
| Gas cost adjustment | 6.0 × $0.42 = $2.52 | 7.0 × **$0.58** = $4.06 |
| City sales tax 1% | on $65.18: $0.65 | on $75.03: $0.75 |
| **Total** | **$65.83** | **$75.78** |

- BB-17's gas was all used in November, but its bill is issued in December, so it takes December's figure. Read at its period's last day, as every other rate is, it would take $0.42 and total $74.65. The test checks that the gas cost figure is picked by the billing month and the other rates by the period.
- Each bill records its billing month and the figure. A later read of the bill, or a rebill of it, gets the same figure (SCN-0133).
- **Open (Kyle):** is "the month the bill is issued" what a city means by a billing month? Should each utility state it at onboarding, with no default, as it states its method for a rate change? The alternative is the month of the period's last day or the read date, which would give BB-17 $0.42.

---

### SCN-0131 — No figure locked for the month: the bills wait, and last month's figure is never used

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built** (as SCN-0130). The refusal is SCN-0001's, on Pecan Flat's facts.
*Rule:* a bill is issued only with a locked figure for its billing month. Until one is locked, the bills that need it wait, with the reason shown. The run never falls back to the previous month's figure. A figure is locked when a supervisor approves it (this stream's reading). Sources: Kyle 11-03, answer 1; SCN-0001; Kyle 08-26, R-11 (a weather adjustment locks when approved: the same pattern).

**Given** Pecan Flat. December's bills use November's purchase price. The supplier's invoice is late, so on Sun Dec 20 no figure is entered for December. November's bills used $6.10. PF-01 used 8.0 Mcf.

**When** (a) the December run starts on Dec 20; (b) on Dec 21 the clerk enters $6.85, not yet approved; (c) on Tue Dec 22 the supervisor approves it.

**Then**
- **(a)** Every Pecan Flat bill is held with the reason "no locked gas cost figure for December". No bill is issued at $6.10. The other lines are computed, but nothing is issued: a bill is issued whole or not at all.
- **(b)** Still held: an entered figure is not a locked one.
- **(c)** The bills are issued Dec 22. PF-01: 8.0 Mcf × $9.00 = $72.00, plus gas cost 8.0 Mcf × $6.85 = $54.80: **$126.80**, due Jan 1, 2027 as always. At $6.10 the gas cost would have been $48.80, and the bill $120.80.
- The figure's record shows who entered it, who approved it and when, and the supplier invoice it came from (an attached document).
- **Open (Kyle):** Kyle's ruling says the figure is set at month end. Pecan Flat sets its figure mid-month, from an invoice. Is a mid-month figure for the month's bills acceptable? Is the lock the supervisor's approval, or the start of the first run that uses it? And should a late bill keep the usual due date (Jan 1, ten days after issue here), or get the usual time to pay?

---

### SCN-0132 — A gas cost figure keyed wrong: replaced before it is locked, corrected with a record after

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built** (as SCN-0130). Parts (b) and (c) are this stream's reading of "fixed once locked" beside Kyle's earlier rule that a wrong figure is rebilled.
*Rule:* before it is locked, a figure keyed wrong is replaced, and both records stay. Once locked it cannot be edited or replaced in the ordinary way. A locked figure that is itself wrong is corrected only by a supervisor's recorded correction that names the error. Every bill issued at the wrong figure is voided and rebilled at the corrected one. Sources: Kyle 11-03, answer 1; Kyle 07-10, T-1 (a stale or wrongly loaded figure is corrected by cancel and rebill at the figure that should have applied); SCN-0069 (a rate keyed wrong is corrected by a new record).

**Given** Bluebonnet. The adjustment for December bills should be $0.58; on Mon Nov 30 the clerk keys **$5.80**.

**When** (a) the supervisor's review catches it on Nov 30, before approving; (b) it is approved at $5.80, and caught on Tue Dec 1, before any December bill is issued; (c) it is caught on Fri Dec 4, after the Dec 2 run issued BB-17's bill (SCN-0130 (b)) at $5.80.

**Then**
- **(a)** The clerk enters $0.58 as a replacement of the $5.80 record. The supervisor approves $0.58, which is locked. The $5.80 record stays readable, marked replaced before approval.
- **(b)** An ordinary edit or replacement of the locked $5.80 is refused. The supervisor records a correction, giving the error ("keyed $5.80 for $0.58"), the right figure and the evidence (the city's worksheet). December's figure becomes $0.58. The $5.80 record stays, marked corrected, with the correction naming it. No bill used it.
- **(c)** As (b), and BB-17's Dec 2 bill is voided and rebilled at $0.58:

| | Issued Dec 2 at $5.80 | Rebill at $0.58 |
|---|---|---|
| Gas cost adjustment | 7.0 × $5.80 = $40.60 | 7.0 × $0.58 = $4.06 |
| City sales tax 1% | on $111.57: $1.12 | on $75.03: $0.75 |
| **Total** | **$112.69** | **$75.78** |

  BB-17's balance falls by **$36.91**. If BB-17 had already paid $112.69, the $36.91 is an overpayment credit (`cash.md` SCN-0082). An overcharge is refunded in full, with no backbilling limit (SCN-0015). The run lists every bill issued at $5.80, and each is rebilled; none is left at the wrong figure.
- **Open (Kyle):** is a supervisor's recorded correction the right reading of "fixed once locked", or should a wrong locked figure stand, with the difference carried into the next month's figure (the utility's reconciliation)? And if the wrong figure undercharged, is the rebill a price fix that passes (SCN-0027 (a)), or held to the backbilling limit?

---

### SCN-0133 — A rebill months later uses the original bill's gas cost figure, not today's

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built** (as SCN-0130); the rate basis is built (CI-007).
*Rule:* a correction of a gas bill uses the original bill's world, and its gas cost figure is the one for the voided bill's billing month, whenever the correction is issued. Sources: Kyle 10-14, answer 6 ("rebills use the factor in effect at the time"); Kyle 11-05, answer 17, and SCN-0006 (a gas correction always uses the original period's rates).

**Given** SCN-0002's facts: BB-01's November bill ($65.83, issued Nov 16, the $0.42 November figure) is unpaid. The read was transposed: 4.5 Mcf, not 6.0. This time the error is found on Tue Dec 8, when December's figure is $0.58.

**When** the operator voids the November bill and issues the correction on Dec 8, basis historical.

**Then**
- The correction is SCN-0002's: gas cost adjustment 4.5 × **$0.42** = $1.89; total **$52.61**. The correction names November as its billing month for the gas cost.
- At December's figure it would be 4.5 × $0.58 = $2.61 and total $53.34. Issuing it so is refused, as a "current" basis is refused for gas (SCN-0006).
- The billing-side record counts the change against November's figure (SCN-0134).

---

### SCN-0134 — What the utility gets for its reconciliation: gas cost billed and volumes, by billing month

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built:** the billing-side record is not drafted; today's monthly reconciliation table holds the utility's gas purchases and its running balance, which the platform no longer keeps (CI-036 not applicable; Kyle 10-14).
*Rule:* for each billing month, the platform reports each gas cost figure, the volume billed under it and the gas cost revenue billed. A correction of an earlier bill is reported against the figure it used and the month it posted. The platform does not hold the utility's gas purchases or its over- or under-recovered balance. Sources: Kyle 10-14, answers 6 and 7; CI-033.

**Given** Bluebonnet. For the example, three of December's bills (the city has about 5,000): BB-17 7.0 Mcf (SCN-0130 (b)), BB-08 41.6 Mcf billed at elevated pressure (SCN-0144), BB-02 6.6 Mcf estimated (SCN-0141). All are at $0.58. SCN-0133's correction of a November bill is issued on Dec 8. BB-17's December bill is found misread on Jan 6 (5.0 Mcf, not 7.0), voided and rebilled.

**When** the December and January billing-side records are read on Feb 1, 2027.

**Then**

| Billing month of the figure | Figure | Volume | Gas cost billed | Posted in |
|---|---|---|---|---|
| November | $0.42 | −1.5 Mcf | −$0.63 | December (SCN-0133: $1.89 less $2.52) |
| December | $0.58 | 55.2 Mcf | $32.02 | December (BB-17 $4.06, BB-08 $24.13, BB-02 $3.83) |
| December | $0.58 | −2.0 Mcf | −$1.16 | January (BB-17's rebill: $2.90 less $4.06) |

- Each row gives the figure, the volume, the revenue and the month posted, so the utility can total by either month. A rebill never moves revenue to a figure it was not billed at.
- Nothing here is a gas purchase or a balance. Billed revenue against the utility's cost is the utility's reconciliation, outside the platform.
- **Open (Kyle):** does a city's reconciliation count a correction in the month of the figure, or in the month it posts? The record carries both, so the report can show either.

---

### SCN-0135 — Pecan Flat's minimum bill when the gas cost is billed on top of the rate

*Status:* draft (2026-11-25), not yet sent to Kyle. The minimum bill is a rate item (built); what it covers is the tariff's, unstated.
*Rule:* a minimum bill raises the bill to its floor with a line of its own. Whether the gas cost counts toward the floor is the utility's to state. The gas cost billed is always the volume times the figure, whatever the minimum adds. Sources: Pecan Flat's tariff (`cast.md` §1: minimum $20.00 a month; $9.00 per Mcf plus the gas cost).

**Given** Pecan Flat, December's bills at $6.85. PF-02 used 0.8 Mcf in a mild month (**invented**).

**When** the bill is computed (a) with the gas cost counting toward the $20.00 minimum; (b) with the minimum applying to the $9.00 rate only.

**Then**

| Line | (a) | (b) |
|---|---|---|
| Gas, 0.8 Mcf × $9.00 | $7.20 | $7.20 |
| Gas cost, 0.8 Mcf × $6.85 | $5.48 | $5.48 |
| Minimum bill adjustment | $20.00 − $12.68 = $7.32 | $20.00 − $7.20 = $12.80 |
| **Total** | **$20.00** | **$25.48** |

- In both, the gas cost billed is $5.48, and the billing-side record (SCN-0134) counts $5.48 and 0.8 Mcf. The adjustment is not gas cost revenue.
- Pecan Flat must state which reading it uses; a minimum bill with no stated base is refused at setup (this stream's reading, as for the rate-change method).
- **Open (Kyle):** in practice, does a city's minimum bill include the gas cost?

---

## Zones and factors

### SCN-0136 — A meter's pressure zone is confirmed when it is activated; a bill waits while a meter has none

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built:** no zone model exists (CI-020 PARTIAL); the confirmation stamp at activation is Kyle's D3B-2.
*Rule:* each utility defines its own zones, a separate set for each factor. Every meter is assigned a zone of each set it bills by, with dates. The assignment is confirmed by a named person at activation, never filled in by default. A meter with no confirmed zone for its billing date is not billed. Sources: Kyle 10-15, K-02; Kyle 07-10, D3B-2 ("measurement-critical attributes must be affirmed, never defaulted"); CI-020.

**Given** Bluebonnet's pressure zones (`cast.md` §6). BB-18, a machine shop, opens in the Industrial Park on Nov 20, schedule LC-R. Its meter is set Nov 20 and activated with no pressure zone confirmed. The Dec 15 read is 30.0 Mcf (**invented**).

**When** (a) the December run reaches BB-18 on Dec 16; (b) on Dec 17 the field supervisor confirms the Industrial Park zone, dated from Nov 20.

**Then**
- **(a)** BB-18's bill is held with the reason "no confirmed pressure zone". The run goes on for every other meter. Neither the Standard zone (1.0000) nor the zone of the meter's neighbours is assumed.
- **(b)** The bill is issued at 30.0 × 1.0400 = 31.2000 Mcf, and the line shows 30.0, 1.0400 and 31.2. The assignment records who confirmed it and when.
- A meter in the Standard zone is confirmed the same way: a factor of 1.0000 is a confirmed fact, not a blank.

---

### SCN-0137 — A zone's factor changes partway through a billing period

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built** (zones and dated factors, CI-020, CI-026). No ruling covers a factor change mid-period. Kyle's "never split" covers the gas cost figure only, so the expected result is this stream's reading.
*Rule (provisional):* a factor change is handled like a rate change. The utility states, when it enters the change, whether it is split by days, applied by read date, or applied by cycle, with no default. Sources: Kyle 11-03, answer 1 (the method for a rate change); GBM's cross-month factor table (a factor that changes inside a period is weighted by days); Kyle 10-15, K-02.

**Given** BB-08 (LC-R, outside the city; $82.90 a month, $2.31 per Mcf), in the Industrial Park zone. The factor is 1.0400 until Feb 28, 2027, and 1.0600 from Mar 1. The period is Feb 15 – Mar 14, 2027 (28 days), with a raw reading of 40.0 Mcf, issued Mar 16 in the March billing month ($0.49). The state's 6.25% and the county's 0.5% apply (not residential; `tax.md` SCN-0106).

**When** the bill is computed by each method.

**Then**

| | Split by days | By read date | By cycle |
|---|---|---|---|
| Billed volume | 20.0 × 1.0400 + 20.0 × 1.0600 = 42.0000 | 40.0 × 1.0600 = 42.4000 | 40.0 × 1.0400 = 41.6000 |
| Distribution | $97.02 | $97.94 | $96.10 |
| Commodity | $224.70 | $226.84 | $222.56 |
| Gas cost adjustment | $20.58 | $20.78 | $20.38 |
| State 6.25%, county 0.5% | $26.58, $2.13 | $26.78, $2.14 | $26.37, $2.11 |
| **Total** (with the $82.90 charge) | **$453.91** | **$457.38** | **$450.42** |

- The 40.0 Mcf splits 20.0 and 20.0 (14 days each). The line shows each part's raw volume and factor.
- The gas cost figure is still one for the whole bill ($0.49). Only the factor is split.
- A factor change entered with no method is refused when it is entered, not at billing.
- **Open (Kyle):** should a factor change follow the rate-change rule, or is a pressure or heating value factor always split by days (the industry table), or always the factor at the read date?

---

### SCN-0138 — A meter set up with the wrong multiplier: three months rebilled, each at its own month's figures

*Status:* draft (2026-11-25), not yet sent to Kyle. The backbilling cause "billing constant error" is a law row (built); a meter's multiplier is a current value with no history (CI-004 PARTIAL), and Bluebonnet's backbilling rule is SCN-0019's default (not built).
*Rule:* a correct reading converted wrong (multiplier, pressure factor, dial count) is a billing constant error. The meter's record is corrected from the day it was set, keeping the wrong value as history. Every bill in reach is voided and rebilled at its own billing month's figures. At a city with no backbilling rule, a charge reaches back six months from the discovery. Sources: Kyle 09-23 (the cause "billing constant error": "a correct reading converted wrong"); Kyle 11-05, answers 10 – 13 (a field check is a finding; the six-month default); SCN-0019; SCN-0133.

**Given** BB-19, a laundry inside the city, west of Main (LC-U: $72.10 a month, $2.01 per Mcf; the state's 6.25%, the county's 0.5% and the city's 1% apply). A new meter set Sep 15 reads in units of 10 Mcf, but is set up with a multiplier of 1. Three bills issued at the raw index difference: Oct 16 (3.1), Nov 16 (3.4), Dec 16 (4.0). On Mon Jan 4, 2027 a documented field check finds the multiplier.

**When** the correction is made on Jan 4.

**Then**

| Bill | Billed (multiplier 1) | Corrected (multiplier 10) | Charged |
|---|---|---|---|
| Oct 16 (figure $0.42) | 3.1 Mcf: $103.67 | 31.0 Mcf: $337.56 | $233.89 |
| Nov 16 ($0.42) | 3.4 Mcf: $106.19 | 34.0 Mcf: $362.71 | $256.52 |
| Dec 16 ($0.58) | 4.0 Mcf: $111.91 | 40.0 Mcf: $419.91 | $308.00 |
| **Total** | | | **$798.41** |

  For example, the corrected October bill is $72.10, plus 31.0 × $2.01 = $62.31, 31.0 × $5.35 = $165.85 and 31.0 × $0.42 = $13.02 (that is $313.28), plus taxes of $19.58, $1.57 and $3.13.
- The meter's multiplier is corrected to 10 from Sep 15, and the record of 1 stays. Each corrected line shows the raw index difference, the multiplier and the billed volume.
- The six months reach back to Jul 4, 2026, so all three bills are within it. The correction records the cause, the field check that found it and the six-month default it applied.
- Each bill keeps its own billing month's figure: December's is $0.58, not January's $0.71.
- **Open (Kyle):** $798.41 billed to a business at once. Does a city usually offer to spread it over several bills, or is that left to the operator?

---

## Reads

### SCN-0139 — A high read is re-read before billing: the re-read replaces it, both are kept

*Status:* draft (2026-11-25), not yet sent to Kyle. **Not built:** the replacement reason and the single pointer to the replaced reading (Kyle 08-18, D-5, D-6; CI-030 PARTIAL); the purpose "re-read" is not yet allowed.
*Rule:* a reading that fails validation is held from billing. A re-read is a new reading that replaces it, names it and states its reason, and the bill uses the re-read. A typo caught before billing may be fixed in place, with the change recorded. After billing, a reading is never edited. Sources: Kyle 08-18, D-5 (a re-read supersedes; edit in place only for typo fixes on un-billed reads); Kyle 07-10, D3A-2 (high and low checks are utility settings); CI-025, CI-031.

**Given** Pecan Flat; PF-01's Nov 15 reading 1,204.0 Mcf. In the same month last year it used 7.6 Mcf. Pecan Flat flags a read over 150% of that (the platform's starting setting). December's bills are at $6.85. This scenario uses Mcf, as PF-01's meter reads in Mcf (**invented**; most of Pecan Flat's meters read in Ccf, SCN-0143).

**When** (a) the reader keys 1,222.0 on Dec 15 (18.0 Mcf); the read is flagged, and the re-read on Dec 16 finds 1,212.0; (b) instead, the reader keys 1,221.2 and the meter photo shows 1,212.2, caught at review on Dec 15 before billing.

**Then**
- **(a)** The 1,222.0 reading is held and marked replaced. The Dec 16 reading names it, with the reason "re-read for high usage" and the purpose "re-read", not "dispute recheck". The bill uses 8.0 Mcf: $72.00 + $54.80 = **$126.80** (on the keyed read it would have been $285.30). There is no re-read fee: the city asked for it. The next bill starts from 1,212.0.
- **(b)** The reading is corrected in place to 1,212.2, because it has not been billed. The change history keeps 1,221.2, who changed it, why ("typo correction", with the photo) and when.
- After the bill is issued, editing the Dec 16 reading is refused. A later correction is a replacement reading and a rebill or catch-up (SCN-0027).

---

### SCN-0140 — A customer asks for a re-read: free once a year, $5 after, nothing if the city's read was wrong

*Status:* draft (2026-11-25), not yet sent to Kyle. The fee is a rate item (built); the count of requests per calendar year is the core's.
*Rule:* Pecan Flat re-reads a meter at the customer's request free once a calendar year, otherwise for $5.00, and waives the fee whenever the city's read was wrong. Sources: Pecan Flat's tariff (`cast.md` §1, from Stinnett).

**Given** PF-06, 2027. No re-read requests in 2026 count. The fee is not taxed (**invented**).

**When** PF-06 asks for a re-read (a) on Mar 3; the read is confirmed right; (b) on Aug 9; it is confirmed right; (c) on Oct 12; the re-read shows the Oct 15 read was keyed wrong (keyed 1,530 Ccf, actual 1,503 Ccf, on a bill already issued).

**Then**
- **(a)** No fee: the first of 2027. The re-read is a reading for "dispute recheck" that matches the one billed; it replaces nothing.
- **(b)** A **$5.00** re-read fee on the next bill, naming the request.
- **(c)** No fee: the city's read was wrong. The re-read replaces the keyed reading ("dispute recheck"), and the bill is corrected as a keying error, by the operator's choice of rebill or catch-up (SCN-0027 (b)).
- Each request is recorded with its date, its result and whether a fee was charged or why not.
- **Open (Kyle):** does a request that finds the city wrong (c) use up the free one for the year? Here (a) had already used it, so it doesn't matter; if (c) had come first, would (a) then cost $5?

---

### SCN-0141 — An estimated read, and the next actual read catching it up

*Status:* draft (2026-11-25), not yet sent to Kyle. The estimate, its reason and its marking are built (CI-090, CI-112, CI-113). The method by which the next actual read corrects an estimate has nowhere to live (CI-114 GAP).
*Rule:* when a meter can't be read, the bill is estimated by the utility's stated method and is marked as an estimate. The next actual reading bills the difference from the estimated reading, so the gas is billed once in all (this stream's reading of the usual practice). The estimated reading stays as billed. Sources: Kyle 07-10, D11-2 (an estimated read uses the estimated-bill form); CI-114; `cast.md` §6 (the estimate method).

**Given** Bluebonnet; BB-02 (R-R, outside the city: $14.75 a month, $3.41 per Mcf; no tax, residential outside the city). The Nov 15 actual reading is 2,310.0. BB-02's last three billed months averaged 6.6 Mcf. On Dec 15 the gate is locked. December's figure is $0.58, January's $0.71.

**When** (a) the December bill is estimated; (b) on Jan 15, 2027 the actual reading is 2,325.9; (b′) instead, it is 2,314.6.

**Then**
- **(a)** The estimated reading is 2,316.6 (2,310.0 + 6.6), reason "access issue: locked gate", method "average of last three months". The bill is marked "Estimated", on the form with the estimate notice. It totals **$76.40**: customer charge $14.75, distribution 6.6 × $3.41 = $22.51, commodity 6.6 × $5.35 = $35.31, gas cost 6.6 × $0.58 = $3.83.
- **(b)** January bills 2,325.9 − 2,316.6 = **9.3 Mcf** at January's rates: $14.75, distribution $31.71, commodity $49.76, gas cost 9.3 × $0.71 = $6.60, for **$102.82**. In all, 15.9 Mcf billed over the two months: the true usage.
- **(b′)** The actual is below the estimate: 2,314.6 − 2,316.6 = −2.0 Mcf. January bills the customer charge, $14.75, and a credit for 2.0 Mcf: distribution −$6.82, commodity −$10.70, gas cost 2.0 × −$0.71 = −$1.42. The bill is **−$4.19**, a credit. The read pair is flagged for review. December's overbilled gas cost was at $0.58 and is credited at $0.71, a 26¢ difference.
- The December estimate is never deleted or replaced: it was billed. The January actual is the meter's next reading, and the estimate streak ends with it.
- **Open (Kyle):** (1) at a city, is catch-up on the next read the usual method, or is the estimated bill voided and rebilled? Should the utility state its method (CI-114)? (2) In (b′), should the credit be priced at the estimated month's rates instead? (3) A bill with a credit line reads open after it is paid (the money stream's note on negative lines), so (b′) needs that rule.

---

### SCN-0142 — Gulf Plains: two months without access, the self-read card, the estimate limit, and a cut-off on an estimated bill

*Status:* draft (2026-11-25), not yet sent to Kyle. The cap on estimates in a row is built (AC-20, AC-21); sending the card needs the communication log (CI-095); the disconnection check is the collections rules' (-26, not mirrored).
*Rule:* where 16 TAC §7.45 binds, an estimated bill is allowed if an actual reading is taken at least every six months. In the second straight month the reader cannot get in, the utility sends a card asking the customer to read the meter. An estimated bill is marked as one. An unpaid estimated bill cannot ground a cut-off unless the utility could not read the meter for reasons beyond its control. The utility's own cap on estimates in a row applies within that limit. Sources: 16 TAC §7.45(6)(C), (6)(B)(viii), (4)(E)(vii) (read 2026-11-25, Cornell LII; last amended 2004); Kyle 07-10, D14-1 (the count is per meter, and only a validated actual reading resets it); Kyle 09-02, R-30 (what is beyond the utility's control: a locked gate, an aggressive dog, unsafe conditions, no permission, weather; not an offline meter, a malfunction or a new install).

**Given** Gulf Plains; GP-08, residential. The last actual reading was Jan 1, 2027. From Feb 1 an aggressive dog keeps the reader out. Gulf Plains estimates from the same month last year, capped at 3 in a row (`cast.md` §6). February 2026's usage was 9.0 Mcf. Gas cost $3.40.

**When** (a) the Feb 1 read fails; (b) the Mar 1 read fails; (c) Apr 1 fails; (d) May 1 fails; (e) GP-08 does not pay the April bill (issued Apr 5, due Apr 25), and the cut-off check runs.

**Then**
- **(a)** Estimated: 9.0 Mcf; reason "aggressive dog". The Feb 5 bill is marked "Estimated": $15.00, delivery 9.0 × $4.10 = $36.90, gas cost 9.0 × $3.40 = $30.60, for **$82.50**. Estimates in a row: 1.
- **(b)** The second straight month without access: a self-read card goes to GP-08, recorded with its date. If the card is back before the Mar 5 bill, its reading is used (method "customer reported"). If not, the bill is estimated. Estimates in a row: 2.
- **(c)** Estimated. Estimates in a row: 3.
- **(d)** A fourth estimate would pass Gulf Plains' cap. The read gate raises an exception, and the bill is not issued on an estimate until a supervisor resolves it, by an actual reading or a recorded decision. Texas's limit is the outer bound in any case: an actual reading by Jul 1, six months after Jan 1.
- **(e)** The April bill is estimated, but the reason (a dog) is beyond the utility's control, so §7.45(4)(E)(vii) does not bar a cut-off for it. Had the reason been "network meter offline", the April bill could not ground a cut-off. The check reads the reason recorded on each estimated reading behind the bill, and the stricter reading wins.
- **Open (Kyle):** (1) A card the customer returns is a customer reading. Does it end the run of estimates, and does it count as the actual reading Texas requires every six months? (Kyle 07-10 said "no customer-initiated reads in v1"; this one the utility asked for.) (2) Two of Kyle's questions from August are still open: should an actual reading dated earlier than estimates already entered raise its own review? Should a utility be able to set a cap above Texas's six months at all?

---

### SCN-0143 — A dial that rolls over, and a lower read that is not a rollover

*Status:* draft (2026-11-25), not yet sent to Kyle. The meter's rollover point is a column (built); computing usage across it is the core's (CI-022).
*Rule:* when a reading is lower than the last, the core counts it as a rollover only on a meter with a recorded rollover point. The usage is then what remains to the rollover plus the new reading, and it passes the same high and low checks as any read. A lower reading the checks reject is held for a re-read. The usage is never negative and never guessed. Sources: CI-022; Kyle 07-10, D3-1 (the rollover point a column); `cast.md` §6 (a four-dial Ccf index, rolling over after 9,999).

**Given** Pecan Flat; PF-07, December's bills at $6.85. The Nov 15 reading is 9,962 Ccf. Same month last year: 8.2 Mcf.

**When** the Dec 15 reading is (a) 0,041; (b) 9,950.

**Then**
- **(a)** A rollover: (10,000 − 9,962) + 41 = 79 Ccf = **7.9 Mcf**. The bill is 7.9 × $9.00 = $71.10, plus 7.9 × $6.85 = 54.1150, so $54.12: **$125.22**. The line records the raw readings, the rollover and the 7.9.
- **(b)** Read as a rollover, the usage would be 9,988 Ccf (998.8 Mcf), far over 150% of last year. The read is held, and a re-read is sent ("re-read for high or low usage"). It is not billed as zero, as a negative, or as a rollover.

---

### SCN-0144 — A meter changed partway through a period, at an elevated-pressure premise

*Status:* draft (2026-11-25), not yet sent to Kyle. The removal and installation readings and their lineage are built (CI-024, CI-032); the pressure check at a meter swap is Kyle's D3B-1 (not built; zones are not built, SCN-0136).
*Rule:* when a meter is changed during a period, the bill adds the old meter's use up to its removal reading and the new meter's use from its installation reading, under one customer charge. Before the new meter is billed, its pressure class is checked against the factor last known at the premise, after the pressure test. A mismatch needs an operator's confirmation with a reason. Sources: CI-024; Kyle 07-10, D3B-1, D3B-2; Kyle 10-15, R-10 (a dated install history per location).

**Given** BB-08 (LC-R, Industrial Park zone, 1.0400; December's figure $0.58). The Nov 15 reading on meter M-1 is 5,120.0. On Dec 1 M-1 is removed at 5,141.5 and meter M-2 is set at 0.0. M-2 arrives set up as standard pressure. The Dec 15 reading on M-2 is 18.5.

**When** (a) M-2 is activated on Dec 1; (b) the December bill is computed on Dec 16.

**Then**
- **(a)** M-2's standard pressure does not match the premise's Industrial Park factor of 1.0400. The pressure test is recorded, and the operator confirms the Industrial Park zone, with the test as the reason. Until then M-2's readings are not billed.
- **(b)** M-1 21.5 + M-2 18.5 = 40.0 Mcf raw × 1.0400 = 41.6000 Mcf billed: $82.90 (once), distribution $96.10, commodity $222.56, gas cost 41.6 × $0.58 = $24.13, state $26.61, county $2.13: **$454.43**. The line shows both meters' readings.
- M-1's readings stay with M-1 and with BB-08's address. M-1's history shows its removal on Dec 1.

---

### SCN-0145 — A meter moved to another house keeps its history; each house keeps the readings taken there

*Status:* draft (2026-11-25), not yet sent to Kyle. Installations by location are built (CI-032); moving a meter by editing its premise directly, rather than by a removal and an installation, is not blocked (CI-027 PARTIAL; AC-7).
*Rule:* a reading belongs to the meter and to the address where it was taken. A meter changes address only by a removal and an installation, each with a reading. A correction later found for that meter follows it at the address and in the months it was there. Sources: Kyle 08-18, D-3 ("complete meter read history must stay with the meter and the service address"); Kyle 10-15, R-10; SCN-0037 (a correction follows the meter).

**Given** Pecan Flat. Meter M-7 served PF-06's house from 2024. It is removed on Mar 15, 2027 for a test, refurbished, and set at PF-07's house on May 15, 2027.

**When** (a) M-7's history is read; (b) PF-06's house's history is read; (c) a later test finds M-7 was slow before its removal; (d) a clerk changes M-7's premise directly to PF-07's house, with no removal or installation.

**Then**
- **(a)** M-7's readings run in order: at PF-06's house until its Mar 15 removal reading, then at PF-07's from its May 15 installation reading.
- **(b)** PF-06's house shows M-7's readings until Mar 15, then its new meter's. It never shows a reading M-7 took at PF-07's house.
- **(c)** The correction reaches only the months M-7 was at PF-06's house, and goes to whoever was billed for each (SCN-0037), never to PF-07.
- **(d)** Refused (this stream's reading): a change of address is a removal and an installation, each with a reading.
- **Open (Ryan, for the rates stream):** a meter recorded at the wrong address from the start is a correction, not a move. How is it told apart from a move, and what happens to the readings already taken (CI-027)?
