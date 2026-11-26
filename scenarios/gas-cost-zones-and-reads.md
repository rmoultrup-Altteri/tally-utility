# Gas cost, zones and factors, and meter reads

What the gas costs on a bill, the factors that turn a meter's raw reading into billed volume, and the readings themselves: estimates, re-reads, rollovers, meter changes. Invariants: CI-033 – CI-035 (the gas cost on the bill), CI-020 – CI-023, CI-026, CI-029 (zones, factors, rollover), CI-024, CI-025, CI-027, CI-030, CI-031, CI-090, CI-112 – CI-114 (reads, replacements, estimates). CI-034's text, a gas cost change inside a period prorated by days, is superseded by Kyle's ruling that the figure is never split (noted for the parity record). **Written ahead of its patches** (Ryan, 2026-11-25, DECISION-LOG): the rates stream's gas cost billing side, zones and factor tables, and read ownership and replacement reads are on its list but not claimed. Each scenario is written to the rulings and says what is built and what is not. The billing pipeline (`billing-pipeline-and-charge-composition.md`) already covers a gas cost credit and a pressure factor (SCN-0001, SCN-0055); dated factors are SCN-0078; keyed-wrong reads are `cancel-rebill.md` SCN-0002, 0027. Reviewed in round 7 (`review/2026-11-25-gas/`).

**Common to every scenario here.**
- **Gas cost is the billing side only.** The platform holds each approved gas cost figure, what was billed under it and the volumes. It keeps every past figure, so a rebill uses the figure the original bill used (except when that figure is itself corrected, SCN-0132). The utility's gas purchases, its over- or under-recovered balance and any cap on lost gas stay in its own accounting (Kyle 10-14, answers 6 and 7). The utility does its reconciliation from the platform's billing-side record (SCN-0134).
- **One figure per billing month.** A gas cost figure applies to a whole billing month, is never split by days, and cannot be changed in the ordinary way once locked (Kyle 11-03, answer 1). A bill's billing month is the month it is issued, at all three cast utilities (`cast.md` §6), and a figure is named by its billing month here ("December's figure" is the one on bills issued in December; SCN-0001 names the same figure by the month it was locked). The other rates follow the period, by the method stated for any rate change inside it (SCN-0001). The gas cost figure follows the billing month instead, and the bill records the month and the figure. The bill snapshot reads everything at one date, the period's last day, so how it records a figure picked by billing month is the rates stream's to solve.
- **A factor is stored with the raw quantity it multiplied** (Ryan 2026-11-04). A bill line shows the raw reading, each factor and the billed volume. All three utilities bill in Mcf, so no heating value or therm figures appear. No cast utility bills in an energy unit or has weather normalization; those wait for Gulf Plains' tariff and the weather family. **Today a bill line in Mcf without therm figures is refused at issue.** The money stream's patch carrying Ryan's 2026-11-04 decision is not drafted, so every worked bill here waits on it.
- **A reading is never overwritten once billed.** A re-read is a new reading that replaces the earlier one, names it, and states a reason from Kyle's list: re-read for high or low usage, re-read for a zero or missing read, re-read after an access problem, meter malfunction, estimate replaced by an actual, dispute recheck, tamper investigation, wrong meter, typo correction, other. Both readings stay (Kyle 08-18, D-5; Kyle 10-15, K-03). A reading's history stays with the meter and with the address (Kyle 08-18, D-3; Kyle 10-15, R-10).
- **Texas's meter-reading rule binds only Gulf Plains.** 16 TAC §7.45 sets standards for residential and small commercial gas service by a regulated utility, of its own force in unincorporated areas, and inside a city only where they don't conflict with the city's standards. GP-08 is in an unincorporated area. City systems such as Pecan Flat and Bluebonnet are not bound by it, even for customers outside the city limits. Their tariffs say nothing about estimates, so their settings in `cast.md` §6 are invented.
- **Dates** are 2026 unless stated. Every value in `cast.md` §6 is **invented**. New customers: BB-17, BB-18, BB-19, GP-08 (`cast.md`). Each scenario stands alone unless it says it continues another.

---

## Gas cost

### SCN-0130 — The gas cost figure a bill uses is its billing month's, not the month the gas was used

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built:** a gas cost figure is a dated rate version today, with no billing month and no lock (the rates stream's gas cost billing side).
*Rule:* a bill uses the gas cost figure locked for its billing month, the month it is issued. The whole bill uses that one figure, and the bill records the month and the figure. Sources: Kyle 11-03, answer 1; `cast.md` §2 and §6 (the figure locked at a month's end applies to bills issued in the next).

**Given** Bluebonnet. November's figure is $0.42 and December's is $0.58. No other rate changes in either period.
- (a) BB-01 (R-U, inside the city): period Oct 15 – Nov 13, 6.0 Mcf, issued Nov 16 (the reference bill).
- (b) BB-17 (R-U, inside the city): period Nov 1 – 30, read Nov 30, 7.0 Mcf, issued Wed Dec 2.
- (c) BB-01's bill as in (a), but held by a read exception from Nov 16 until it is cleared on Tue Dec 1, and issued that day.

**When** the bills are computed.

**Then**

| Line | (a) BB-01, November | (b) BB-17, December | (c) BB-01, December |
|---|---|---|---|
| Customer charge | $12.80 | $12.80 | $12.80 |
| Distribution | 6.0 × $2.96 = $17.76 | 7.0 × $2.96 = $20.72 | $17.76 |
| Commodity charge | 6.0 × $5.35 = $32.10 | 7.0 × $5.35 = $37.45 | $32.10 |
| Gas cost adjustment | 6.0 × $0.42 = $2.52 | 7.0 × **$0.58** = $4.06 | 6.0 × **$0.58** = $3.48 |
| City sales tax 1% | on $65.18: $0.65 | on $75.03: $0.75 | on $66.14: $0.66 |
| **Total** | **$65.83** | **$75.78** | **$66.80** |

- BB-17's gas was all used in November, but its bill is issued in December, so it takes December's figure. Had the figure followed the month the gas was used, it would be $0.42 and the bill $74.65.
- (c) is the same gas and the same period as (a), but it costs $0.97 more because the bill was issued late. That follows from the billing month being the issue month.
- Each bill records its billing month and the figure. A later read of the bill, or a rebill of it, gets the same figure (SCN-0133).
- **Open (Kyle):** is "the month the bill is issued" what a city means by a billing month, given (c)? Should each utility state it at onboarding, with no default, as it states its method for a rate change? The alternative is the month of the period's last day or the read date, which gives BB-17 $0.42 and leaves (c) at $65.83.

---

### SCN-0131 — No figure locked for the month: the bills wait, and last month's figure is never used

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built** (as SCN-0130). The refusal is SCN-0001's, on Pecan Flat's facts, and the core's.
*Rule:* a bill is issued only with a locked figure for its billing month. Until one is locked, the bills that need it wait, with the reason shown. The run never falls back to the previous month's figure. A figure is locked when a supervisor approves it (this stream's reading). Sources: Kyle 11-03, answer 1; SCN-0001; Kyle 08-26, R-11 (a weather adjustment locks when approved: the same pattern, by analogy).

**Given** Pecan Flat. December's bills use November's purchase price. The supplier's invoice is late, so on Sun Dec 20 no figure is entered for December. November's bills used $6.10. PF-01 used 8.0 Mcf.

**When** (a) the December run starts on Dec 20; (b) on Dec 21 the clerk enters $6.85, not yet approved; (c) on Tue Dec 22 the supervisor approves it.

**Then**
- **(a)** Every Pecan Flat bill is held with the reason "no locked gas cost figure for December". No bill is issued at $6.10. The other lines are computed, but nothing is issued: a bill is issued whole or not at all.
- **(b)** Still held: an entered figure is not a locked one.
- **(c)** The bills are issued Dec 22. PF-01: 8.0 Mcf × $9.00 = $72.00, plus gas cost 8.0 Mcf × $6.85 = $54.80: **$126.80**, due Jan 1, 2027 as always. At $6.10 the gas cost would have been $48.80, and the bill $120.80.
- The figure's record shows who entered it, who approved it and when, and the supplier invoice it came from (an attached document).
- **Open (Kyle):** Kyle's ruling says the figure is set at month end. Pecan Flat sets its figure mid-month, from an invoice: is that acceptable for the month's bills? Is the lock the supervisor's approval, or the start of the first run that uses it? Should a late bill keep the usual due date (Jan 1, ten days after issue here, and a holiday), or get the usual time to pay? Pecan Flat's tariff doesn't say whether a due date on a holiday moves.

---

### SCN-0132 — A gas cost figure keyed wrong: replaced before it is locked, corrected with a record after

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built** (as SCN-0130). Parts (b) and (c) are this stream's reading of "fixed once locked" beside Kyle's earlier rule that a bill on a stale or missed figure is rebilled.
*Rule:* before it is locked, a figure keyed wrong is replaced, and both records stay. Once locked it cannot be edited or replaced in the ordinary way. A locked figure that is itself wrong is corrected only by a supervisor's recorded correction that names the error. Every bill issued at the wrong figure is corrected at the right one. Sources: Kyle 11-03, answer 1; Kyle 07-10, T-1 (a bill on a stale or missed figure is cancelled and rebilled at the figure that should have applied; a figure keyed wrong is this stream's extension); SCN-0069 (a rate keyed wrong is corrected by a new record).

**Given** Bluebonnet. December's figure should be $0.58; on Mon Nov 30 the clerk keys **$5.80**.

**When** (a) the supervisor's review catches it on Nov 30, before approving; (b) it is approved at $5.80, and caught on Tue Dec 1, before any December bill is issued; (c) it is caught on Fri Dec 4, after the Dec 2 run issued BB-17's bill (SCN-0130 (b)) at $5.80, unpaid.

**Then**
- **(a)** The clerk enters $0.58 as a replacement of the $5.80 record. The supervisor approves $0.58, which is locked. The $5.80 record stays readable, marked replaced before approval.
- **(b)** An ordinary edit or replacement of the locked $5.80 is refused. The supervisor records a correction, giving the error ("keyed $5.80 for $0.58"), the right figure and the evidence (the city's worksheet). December's figure becomes $0.58. The $5.80 record stays, marked corrected, with the correction naming it. No bill used it.
- **(c)** As (b), and BB-17's Dec 2 bill is voided and rebilled at $0.58:

| | Issued Dec 2 at $5.80 | Rebill at $0.58 |
|---|---|---|
| Gas cost adjustment | 7.0 × $5.80 = $40.60 | 7.0 × $0.58 = $4.06 |
| City sales tax 1% | on $111.57: $1.12 | on $75.03: $0.75 |
| **Total** | **$112.69** | **$75.78** |

  BB-17's balance falls by **$36.91**. Had BB-17 already paid $112.69, the bill would be credited and rebilled and the payment moved to the corrected bill (`cash.md` SCN-0089, whose Open asks what happens to the excess). At a city, an overcharge is refunded as far back as the records show (Kyle 11-03, answer 8; SCN-0019). The run lists every bill issued at $5.80, and each is corrected; none is left at the wrong figure.
- Had the wrong figure undercharged, the correction would be an upward rate correction, passing under Bluebonnet's six-month default with the cause "rate misapplication", as for a rate keyed too low (SCN-0069, SCN-0028).
- **Open (Kyle):** is a supervisor's recorded correction the right reading of "fixed once locked"? Or should a wrong locked figure stand, with the difference carried into the next month's figure (the utility's reconciliation)?

---

### SCN-0133 — A rebill months later uses the original bill's gas cost figure, not today's

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built:** nothing ties a correction to the voided bill's billing month (as SCN-0130). The rate basis is recorded (CI-007); refusing a "current" basis for gas is the core's (SCN-0006).
*Rule:* a correction of a gas bill uses the original bill's world, and its gas cost figure is the one for the voided bill's billing month, whenever the correction is issued. Sources: Kyle 10-14, answer 6 ("rebills use the factor in effect at the time"); Kyle 11-05, answer 17, and SCN-0006 (a gas correction always uses the original period's rates).

**Given** SCN-0002's facts: BB-01's November bill ($65.83, issued Nov 16, November's $0.42) is unpaid. The read was transposed: 4.5 Mcf, not 6.0. This time the error is found on Tue Dec 8, when December's figure is $0.58.

**When** the operator voids the November bill and issues the correction on Dec 8, basis historical.

**Then**
- The correction is SCN-0002's: gas cost adjustment 4.5 × **$0.42** = $1.89; total **$52.61**. The correction names November as its billing month for the gas cost.
- At December's figure it would be 4.5 × $0.58 = $2.61 and total $53.34. Issuing it so is refused, as a "current" basis is refused for gas (SCN-0006), by the core.
- The billing-side record counts the change against November's figure (SCN-0134).

---

### SCN-0134 — What the utility gets for its reconciliation: gas cost billed and volumes, by billing month

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built.** Today's monthly reconciliation table holds one total of gas cost revenue billed per month. Beside it, it requires the utility's gas purchases and a running balance on every row, which the platform no longer keeps (Kyle 10-14, answer 6; CI-036 not applicable). So no row can be written for a city that doesn't hand over its purchases. It has no volume, no row per figure, and no month posted. The record this scenario needs is not drafted, and CI-033's grade (represented, on that table) is generous: noted for the parity record.
*Rule:* for each billing month, the platform reports each gas cost figure, the volume billed under it and the gas cost revenue billed. A correction of an earlier bill is reported against the figure it used and the month it posted. The platform does not hold the utility's gas purchases or its over- or under-recovered balance. Sources: Kyle 10-14, answers 6 and 7; CI-033.

**Given** Bluebonnet. For the example, three of December's bills (the city has about 5,000): BB-17 7.0 Mcf (SCN-0130 (b)), BB-08 41.6 Mcf billed at elevated pressure (SCN-0144), and BB-02 6.6 Mcf estimated (SCN-0141). All are at $0.58. SCN-0133's correction of a November bill is issued on Dec 8. BB-17's December bill is found misread on Wed Jan 6, 2027 (5.0 Mcf, not 7.0), then voided and rebilled.

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

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. The minimum is one amount on the rate schedule, compared with the bill's subtotal before tax (built: reading (a)). CI-103 says the floor is checked after the whole bill, taxes included. That difference is noted for the rates stream. Reading (b) has nowhere to live.
*Rule:* a minimum bill raises the bill to its floor with a line of its own. The gas cost billed is always the volume times the figure, whatever the minimum adds. Sources: Pecan Flat's tariff (`cast.md` §1: minimum $20.00 a month; $9.00 per Mcf plus the gas cost); CI-103 (the floor checked against the assembled bill).

**Given** Pecan Flat, December's figure $6.85. PF-02 used 0.8 Mcf in a mild month (**invented**).

**When** the bill is computed (a) with the gas cost counting toward the $20.00 minimum (the invariant's and the schema's reading); (b) with the minimum applying to the $9.00 rate only.

**Then**

| Line | (a) | (b) |
|---|---|---|
| Gas, 0.8 Mcf × $9.00 | $7.20 | $7.20 |
| Gas cost, 0.8 Mcf × $6.85 | $5.48 | $5.48 |
| Minimum bill adjustment | $20.00 − $12.68 = $7.32 | $20.00 − $7.20 = $12.80 |
| **Total** | **$20.00** | **$25.48** |

- In both, the gas cost billed is $5.48, and the billing-side record (SCN-0134) counts $5.48 and 0.8 Mcf. The adjustment is not gas cost revenue.
- The expected result is (a). Pecan Flat bills no tax, so the difference between the invariant and the schema does not show here.
- **Open (Kyle):** does any city's minimum bill floor the rate only, leaving the gas cost on top (b)? If so, the platform needs a way to say so.

---

## Zones and factors

### SCN-0136 — A meter's pressure zone is confirmed before it is activated; a bill waits while a meter has none

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** a meter carries one stamp confirming its zone and one confirming its pressure class, each with who and when, and a run refuses to bill a gas meter with no pressure class, or an elevated one with no factor (CI-023, v5.4.2-05). **Not built:** zones themselves, a zone per factor set (CI-020, CI-026), and the activation check, which is the core's.
*Rule:* each utility defines its own zones, a separate set for each factor. Each premise is assigned a zone of each set it bills by, with dates. A meter set at the premise is confirmed against it by a named person before it is activated, never filled in by default. A meter with no confirmed zone for its billing date is not billed, as a second line of defence. Sources: Kyle 10-15, K-02 (a zone is assigned to the location or the meter; here, the premise); Kyle 07-10, D3B-2 ("measurement-critical attributes must be affirmed, never defaulted", at activation); CI-020.

**Given** Bluebonnet's pressure zones (`cast.md` §6). BB-18, a machine shop, opens in the Industrial Park on Nov 20, schedule LC-R. Its new meter is set Nov 20 at 0.0. The Dec 15 reading is 30.0.

**When** (a) the clerk activates the meter on Nov 20 with no zone confirmed; (b) the field supervisor confirms the Industrial Park zone and activates it on Nov 20; (c) instead, the meter was activated before the check existed (migrated as active, unconfirmed), and the December run reaches it on Dec 16.

**Then**
- **(a)** Refused: the meter's zone is not confirmed. Neither the Standard zone (1.0000) nor the zone of the meter's neighbours is assumed.
- **(b)** Activated. The billed volume for December is 30.0 × 1.0400 = 31.2000 Mcf, and the line shows 30.0, 1.0400 and 31.2. The confirmation records who confirmed it and when. (The bill's dollar amount is not under test here: whether a first partial month's customer charge is prorated is not stated.)
- **(c)** BB-18's bill is held with the reason "no confirmed pressure zone", and the run goes on for every other meter.
- A meter in the Standard zone is confirmed the same way: a factor of 1.0000 is a confirmed fact, not a blank.

---

### SCN-0137 — A zone's factor changes partway through a billing period

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built** (zones and dated factors, CI-020, CI-026). No ruling covers a factor change mid-period. Kyle's "never split" covers the gas cost figure only, so the expected result is this stream's reading, and so is refusing a change entered with no method.
*Rule (provisional):* a factor change is handled like a rate change. When the utility enters the change, it states whether it is split by days, applied by read date, or applied by cycle, with no default. "By cycle" means what it means in SCN-0001: a period that straddles the change is billed wholly at the new factor. Sources: Kyle 11-03, answer 1 (the method for a rate change); SCN-0001; GBM's cross-month factor table (design, not a ruling: a factor that changes inside a period is weighted by days); Kyle 10-15, K-02.

**Given** BB-08 (LC-R, outside the city; $82.90 a month, $2.31 per Mcf), in the Industrial Park zone. The factor is 1.0400 until Feb 28, 2027, and 1.0600 from Mar 1. The period is Feb 15 – Mar 14, 2027 (28 days), with a raw reading of 40.0 Mcf, issued Mar 16 in the March billing month ($0.49). The state's 6.25% and the county's 0.5% apply (not residential; `tax.md` SCN-0106). The March bill carries Bluebonnet's pipeline safety fee, $1.00 for BB-08's one service line, outside every tax base (SCN-0054).

**When** the bill is computed by each method.

**Then**

| | Split by days | By read date, or by cycle |
|---|---|---|
| Billed volume | 20.0 × 1.0400 + 20.0 × 1.0600 = 42.0000 | 40.0 × 1.0600 = 42.4000 |
| Customer charge | $82.90 | $82.90 |
| Distribution | $97.02 | $97.94 |
| Commodity | $224.70 | $226.84 |
| Gas cost adjustment | $20.58 | $20.78 |
| State 6.25%, county 0.5% | $26.58, $2.13 | $26.78, $2.14 |
| Pipeline safety fee | $1.00 | $1.00 |
| **Total** | **$454.91** | **$458.38** |

- The 40.0 Mcf splits 20.0 and 20.0 (14 days each). The line shows each part's raw volume and factor.
- By read date and by cycle agree here, as in SCN-0001. Had the old factor stayed for the whole period, the bill would be 41.6000 Mcf and $451.42.
- The gas cost figure is still one for the whole bill ($0.49). Only the factor is split.
- A factor change entered with no method is refused when it is entered, not at billing.
- **Open (Kyle):** should a factor change follow the rate-change rule? Or is a pressure or heating value factor always split by days (the industry table), or always the factor at the read date?

---

### SCN-0138 — A meter set up with the wrong multiplier: three months corrected, each at its own month's figures

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. The backbilling cause "billing constant error" exists only in the Texas law rows, which bind regulated utilities; for Bluebonnet, only the city's six-month default applies (SCN-0019, not built). A meter's multiplier is a current value with no history (CI-004 PARTIAL). How such a correction reaches the customer is unruled, so voiding and rebilling the three bills is this stream's reading.
*Rule:* a correct reading converted wrong (multiplier, pressure factor, dial count) is a billing constant error. The meter's record is corrected from the day it was set, keeping the wrong value as history. Every bill in reach is corrected at its own billing month's figures. At a city with no backbilling rule, a charge reaches back six months from the discovery. The amount the error hid is due with the next regular bill. Sources: Kyle 09-23 (the cause "billing constant error": "a correct reading converted wrong"); Kyle 11-05, answers 2 (what an error hid goes on the next regular bill, with its due date), 10 – 12 (the six-month default) and 13 (a documented field check is a finding, ruled for a meter that stopped registering and used here by extension); Kyle 11-03, answer 10 (an increase ages from the correction); Ryan 2026-11-22 (one charge, part of it due later); SCN-0019; SCN-0133.

**Given** BB-19, a laundry inside the city, west of Main (LC-U: $72.10 a month, $2.01 per Mcf, unchanged on Oct 1; the state's 6.25%, the county's 0.5% and the city's 1% apply). A new meter set Sep 15 reads in units of 10 Mcf, but is set up with a multiplier of 1. Three bills were issued on the raw index difference, each paid on time: Oct 16 (3.1), Nov 16 (3.4) and Dec 16 (4.0). On Mon Jan 4, 2027 a documented field check finds the multiplier.

**When** the correction is made on Jan 4.

**Then**

| Bill | Billed (multiplier 1) | Corrected (multiplier 10) | Hidden by the error |
|---|---|---|---|
| Oct 16 (figure $0.42) | 3.1 Mcf: $103.67 | 31.0 Mcf: $337.56 | $233.89 |
| Nov 16 ($0.42) | 3.4 Mcf: $106.19 | 34.0 Mcf: $362.71 | $256.52 |
| Dec 16 ($0.58) | 4.0 Mcf: $111.91 | 40.0 Mcf: $419.91 | $308.00 |
| **Total** | | | **$798.41** |

  For example, the corrected October bill is $72.10, plus 31.0 × $2.01 = $62.31, 31.0 × $5.35 = $165.85 and 31.0 × $0.42 = $13.02 (that is $313.28), plus taxes of $19.58, $1.57 and $3.13.
- Each paid bill is credited and rebilled, and its payment moves to the corrected bill (SCN-0089). The $798.41 is due with the next regular bill, Jan 16, and ages from Jan 4.
- The corrected bills carry 2026's taxes, the taxes of the periods they bill: no crime-control district, though they are issued in 2027.
- The meter's multiplier is corrected to 10 from Sep 15, and the record of 1 stays. Each corrected line shows the raw index difference, the multiplier and the billed volume.
- The six months reach back to Jul 4, 2026, so all three bills are within it. The correction records the cause, the field check that found it and the six-month default it applied.
- Each bill keeps its own billing month's figure: December's is $0.58, not January's $0.71.
- **Open (Kyle):** (1) is voiding and rebilling right for a billing constant error at a city, or does it go on the next bill as one prior-period line? (2) $798.41 billed to a business at once: does a city usually offer to spread it over several bills, or is that left to the operator?

---

## Reads

### SCN-0139 — A high read is re-read before billing: the re-read replaces it, both are kept

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** a billed reading's values cannot be changed (CI-025, CI-031). **Not built:** the replacement reason and the single pointer to the replaced reading (Kyle 08-18, D-5, D-6; CI-030 PARTIAL); the purpose "re-read" is not yet allowed.
*Rule:* a reading that fails validation is held from billing. A re-read is a new reading that replaces it, names it and states its reason, and the bill uses the re-read. A typo caught before billing may be fixed in place, with the change recorded. After billing, a reading is never edited. Sources: Kyle 08-18, D-5 (a re-read supersedes; edit in place only for typo fixes on un-billed reads); Kyle 07-10, D3A-2 (high and low checks are utility settings); CI-025, CI-031.

**Given** Pecan Flat; PF-01, whose meter reads in Mcf to a tenth (`cast.md` §6). The Nov 15 reading is 1,204.0. In the same month last year PF-01 used 7.6 Mcf. Pecan Flat flags a read over 150% of that (the platform's starting setting). December's figure is $6.85.

**When** (a) the reader keys 1,222.0 on Dec 15 (18.0 Mcf); the read is flagged, and the re-read on Dec 16 finds 1,212.0; (b) instead, the reader keys 1,221.2 and the meter photo shows 1,212.2, caught at review on Dec 15 before billing.

**Then**
- **(a)** The 1,222.0 reading is held and marked replaced. The Dec 16 reading names it, with the reason "re-read for high or low usage" and the purpose "re-read", not "dispute recheck". It closes the period in place of the Dec 15 reading. The bill uses 8.0 Mcf: $72.00 + $54.80 = **$126.80** (on the keyed read it would have been $285.30). There is no re-read fee: the city asked for it. The next bill starts from 1,212.0.
- **(b)** The reading is corrected in place to 1,212.2, because it has not been billed. The change history keeps 1,221.2, who changed it, why ("typo correction", with the photo) and when. The bill uses 8.2 Mcf: $73.80 + $56.17 = **$129.97**.
- After the bill is issued, editing the reading is refused. A later correction is a replacement reading and a rebill or catch-up (SCN-0027).

---

### SCN-0140 — A customer asks for a re-read: free once a year, $5 after, nothing if the city's read was wrong

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. The fee is a one-off charge the tariff allows (as in `cash.md` SCN-0084); counting requests per calendar year is the core's.
*Rule:* Pecan Flat re-reads a meter at the customer's request free once a calendar year, otherwise for $5.00, and waives the fee whenever the city's read was wrong. Sources: Pecan Flat's tariff (`cast.md` §1, from Stinnett).

**Given** PF-06, 2027. No re-read requests in 2026 count. The fee is not taxed (**invented**).

**When** PF-06 asks for a re-read (a) on Mar 3, and the read is confirmed right; (b) on Aug 9, and it is confirmed right; (c) on Fri Oct 22, after the Oct 20 bill, and the re-read shows the Oct 15 reading was keyed too high (1,530 Ccf keyed, 1,503 Ccf actual).

**Then**
- **(a)** No fee: the first request of 2027. The re-read is a reading for "dispute recheck" that matches the one billed; it replaces nothing.
- **(b)** A **$5.00** re-read fee on the next bill, naming the request.
- **(c)** No fee: the city's read was wrong. The re-read replaces the keyed reading ("dispute recheck"). The bill overcharged 2.7 Mcf, so it is voided and rebilled, or credited and rebilled if paid (SCN-0002). It is not left to catch up on the next read, since a refund is never held back (Kyle 11-03, answer 8; this stream's reading). Only the fee is under test here.
- Each request is recorded with its date, its result and whether a fee was charged or why not.
- **Open (Kyle):** does a request that finds the city wrong (c) use up the free one for the year? Here (a) had already used it, so it doesn't matter; if (c) had come first, would (a) then cost $5? And may a keyed-too-high read ever catch up on the next read instead of a rebill?

---

### SCN-0141 — An estimated read, and the next actual read catching it up

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. The estimate, its reason and its marking are built (CI-090, CI-112, CI-113). Where a utility's method for correcting an estimate lives is not (CI-114 GAP).
*Rule:* when a meter can't be read, the bill is estimated by the utility's stated method and is marked as an estimate. The next actual reading bills the difference from the estimated reading, so the gas is billed once in all. The utility states this method, catch-up or rebill (CI-114; Kyle 10-15, R-11: estimation is dated rule data); catch-up is this stream's reading of the usual practice, set for Bluebonnet. A billed estimate stays as billed. Sources: Kyle 07-10, D11-2 (an estimated read uses the estimated-bill form); CI-114; `cast.md` §6 (the estimate method).

**Given** Bluebonnet; BB-02 (R-R, outside the city: $14.75 a month, $3.41 per Mcf; no tax, residential outside the city). Bluebonnet's minimum bill is the customer charge, always billed, with no floor amount set. The Nov 15 actual reading is 2,310.0. BB-02's last three billed months averaged 6.6 Mcf. On Dec 15 the gate is locked. December's figure is $0.58, January's $0.71.

**When** (a) the December bill is estimated; (b) on Jan 15, 2027 the actual reading is 2,325.9; (b′) instead, it is 2,314.6.

**Then**
- **(a)** The estimated reading is 2,316.6 (2,310.0 + 6.6), reason "access issue: locked gate", method "average of last three months". The bill is marked "Estimated", on the form with the estimate notice. It totals **$76.40**: customer charge $14.75, distribution 6.6 × $3.41 = $22.51, commodity 6.6 × $5.35 = $35.31, gas cost 6.6 × $0.58 = $3.83.
- **(b)** January bills 2,325.9 − 2,316.6 = **9.3 Mcf** at January's rates: $14.75, distribution $31.71, commodity $49.76, gas cost 9.3 × $0.71 = $6.60, for **$102.82**. In all, 15.9 Mcf billed over the two months: the true usage.
- **(b′)** The actual is below the estimate: December was over-estimated by 2.0 Mcf. This is a credit, never a rollover (SCN-0143). The read pair raises a review exception, and January's bill waits until a reviewer confirms the reading. It then bills the customer charge, $14.75, and a credit for 2.0 Mcf: distribution −$6.82, commodity −$10.70, gas cost 2.0 × −$0.71 = −$1.42. The bill is **−$4.19**, a credit. December's overbilled gas cost was at $0.58 and is credited at $0.71, a 26¢ difference.
- The billed December estimate is never deleted or replaced. The January actual is the meter's next reading, and the run of estimates ends with it. ("Estimate replaced by an actual", Kyle's reason, is for an estimate not yet billed: an actual for the same date that arrives before the bill.)
- **Open (Kyle):** (1) at a city, is catch-up on the next read the usual method, or is the estimated bill voided and rebilled? (2) In (b′), is a credit for usage below the estimate allowed at all (whether usage can ever be negative is not ruled), and should it be priced at the estimated month's rates? (3) A bill with a credit line reads open after it is paid (the money stream's note on negative lines), so (b′) needs that rule too.

---

### SCN-0142 — Gulf Plains: two months without access, the self-read card, the estimate limit, and a cut-off on an estimated bill

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** the cap on estimates in a row and its exception, which a supervisor resolves by an override or a field order (AC-20, AC-21), and the reading method "customer reported". **Not built:** sending the card needs the communication log (CI-095); the six-month check is the core's (CI-090); the disconnection check is the collections rules' (-26, not mirrored).
*Rule:* where 16 TAC §7.45 binds, an estimated bill is allowed "where there is good reason", provided an actual reading is taken at least every six months. In the second straight month the reader cannot get in, the utility sends a card asking the customer to read the meter, if the customer can read it without significant inconvenience or special tools. An estimated bill is marked as one. An unpaid estimated bill cannot ground a cut-off, unless it was rendered under an approved meter-reading plan or the utility could not read the meter for reasons beyond its control. Whether a reason is beyond its control is judged from the reason recorded on the reading at the time, and where none is recorded, the customer is protected. The utility's own cap on estimates in a row applies within the six months. Sources: 16 TAC §7.45(6)(C), (6)(B)(viii), (4)(E)(vii) (read 2026-11-25, Cornell LII; last amended 2004); Kyle 07-10, D14-1 (the count is per meter, and only a validated actual reading resets it); Kyle 09-14, R-30 (the mechanism and the protective default; which reasons fall on which side is an engineering proposal, not Kyle's ruling); Kyle DE-1 (Texas's six months is the ceiling on a utility's cap).

**Given** Gulf Plains, which has no approved meter-reading plan; GP-08, residential, in an unincorporated area, with a meter the customer can read. Gulf Plains reads on the 1st for the month before, weekends included, and bills on the 5th. The last actual reading was Mon Mar 1, 2027. From Apr 1 an aggressive dog keeps the reader out. Gulf Plains estimates from the same month last year, with a cap of 3 (`cast.md` §6): the third estimate in a row is approved only after a supervisor resolves the exception it raises. Last year GP-08 used 9.0 Mcf in March 2026, 7.2 in April, 4.8 in May and 3.1 in June. Gas cost $3.40.

**When** (a) the Apr 1 read fails; (b) the May 1 read fails, and no card comes back before May 5; (c) the Jun 1 read fails; (d) the Jul 1 read fails; (e) GP-08 does not pay the June bill (issued Jun 5, due Fri Jun 25), and the cut-off check runs.

**Then**
- **(a)** Estimated: 9.0 Mcf (March 2026), reason "aggressive dog". The Apr 5 bill is marked "Estimated": $15.00, delivery 9.0 × $4.10 = $36.90, gas cost 9.0 × $3.40 = $30.60, for **$82.50**. Estimates in a row: 1.
- **(b)** The second straight month without access, so a self-read card goes to GP-08, recorded with its date. No card is back before the May 5 bill, so it is estimated: 7.2 Mcf, **$69.00**. Estimates in a row: 2.
- **(c)** A third estimate (4.8 Mcf) would reach Gulf Plains' cap. The read gate raises an exception, and the estimate is not approved until a supervisor resolves it. Here the supervisor records an override ("dog; customer contacted; appointment set for Jun 8"). The Jun 5 bill is then estimated: **$51.00**. Estimates in a row: 3.
- **(d)** A fourth estimate raises the exception again. The supervisor dispatches a field order, and the bill waits for its result. Texas's limit is the outer bound in any case: an actual reading by Sep 1, six months after Mar 1.
- **(e)** The June bill is estimated. The recorded reason, a dog, is beyond the utility's control under the engineering proposal, so §7.45(4)(E)(vii) would not bar a cut-off for it (provisional, pending the Open). Had the reason been "network meter offline", within the utility's control, the June bill could not ground a cut-off. The check reads the reason recorded on each estimated reading behind the bill, and the more protective reading wins.
- **Open (Kyle, or tariff counsel):** (1) is an aggressive dog beyond a utility's control? The sorting of reasons is a proposal. (2) A card the customer returns is a customer reading. Does it end the run of estimates, and does it count as the actual reading Texas requires every six months? Kyle 07-10 said "no customer-initiated reads in v1"; this one the utility asked for. (3) Should an actual reading dated earlier than estimates already entered raise its own review? (A cap above Texas's six months is ruled out by DE-1 but not yet enforced: noted for the rates stream.)

---

### SCN-0143 — A dial that rolls over, and a lower read that is not a rollover

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. The meter's rollover point is a column (built); computing usage across it is the core's (CI-022).
*Rule:* when a reading is lower than the last actual reading on the same meter, the core counts it as a rollover only on a meter with a recorded rollover point. The usage is then what remains to the rollover plus the new reading, and it passes the same high and low checks as any read. A lower reading the checks reject is held for a re-read. It is never billed as negative usage, and the usage is never guessed. A reading below an *estimated* one is an over-estimate (SCN-0141), and a new meter's first reading is measured from its own installation reading (SCN-0144); neither is a rollover. Sources: CI-022; Kyle 07-10, D3-1 (the rollover point a column); `cast.md` §6 (a four-dial Ccf index, rolling over after 9,999).

**Given** Pecan Flat; PF-07, December's figure $6.85. The Nov 15 reading is 9,962 Ccf. Same month last year: 8.2 Mcf.

**When** the Dec 15 reading is (a) 0,041; (b) 9,950.

**Then**
- **(a)** A rollover: (10,000 − 9,962) + 41 = 79 Ccf = **7.9 Mcf**. The bill is 7.9 × $9.00 = $71.10, plus 7.9 × $6.85 = 54.1150, so $54.12: **$125.22**. The line records the raw readings, the rollover and the 7.9.
- **(b)** Read as a rollover, the usage would be 9,988 Ccf (998.8 Mcf), far over 150% of last year. The read is held, and a re-read is sent ("re-read for high or low usage"). It is not billed as zero, as a negative, or as a rollover.

---

### SCN-0144 — A meter changed partway through a period, at an elevated-pressure premise

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** the removal and installation readings and their lineage (CI-024, CI-032); a meter's pressure class and its confirmation; the record of a confirmed pressure mismatch at an installation, with who, when and why; the refusal to bill a gas meter with no pressure class (CI-023). **Not built:** the check itself, comparing the test's factor with the premise's, is the core's; zones (SCN-0136).
*Rule:* when a meter is changed during a period, the bill adds the old meter's use up to its removal reading and the new meter's use from its installation reading, under one customer charge. Before the new meter is billed, the factor its pressure test establishes is compared with the factor last known at the premise. A mismatch needs an operator's confirmation with a reason. A set-up value the test contradicts is corrected and confirmed. Sources: CI-024; Kyle 07-10, D3B-1 (the check after the pressure test), D3B-2; Kyle 10-15, R-10 (a dated install history per location).

**Given** BB-08 (LC-R, Industrial Park zone, 1.0400; December's figure $0.58). The Nov 15 reading on meter M-1 is 5,120.0. On Dec 1 M-1 is removed at 5,141.5 and meter M-2 is set at 0.0. M-2 arrives set up as standard pressure. The pressure test on Dec 1 establishes 1.0400. The Dec 15 reading on M-2 is 18.5.

**When** (a) M-2 is activated on Dec 1; (b) the December bill is computed on Dec 16; (c) instead, the test had established 1.0600.

**Then**
- **(a)** The test agrees with the premise's 1.0400, so there is no mismatch. M-2's "standard pressure" set-up is wrong: the operator corrects it to elevated and confirms it, citing the test. Until then M-2 is not activated.
- **(b)** M-1 21.5 + M-2 18.5 = 40.0 Mcf raw × 1.0400 = 41.6000 Mcf billed: $82.90 (once), distribution $96.10, commodity $222.56, gas cost 41.6 × $0.58 = $24.13, state $26.61, county $2.13: **$454.43**. The line shows both meters' readings. M-2's 0.0 after M-1's 5,141.5 is a new meter, not a rollover.
- **(c)** 1.0600 does not match the premise's 1.0400. M-2 is billed only after the operator confirms it with a reason (for example, "line pressure raised; test of Dec 1"), and the premise's factor changes from Dec 1 by the method rule (SCN-0137).
- M-1's readings stay with M-1 and with BB-08's address. M-1's history shows its removal on Dec 1.

---

### SCN-0145 — A meter moved to another house keeps its history; each house keeps the readings taken there

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. Installations by location are built (CI-032). Moving a meter by editing its premise directly, rather than by a removal and an installation, is not blocked (CI-027 PARTIAL; AC-7).
*Rule:* a reading belongs to the meter and to the address where it was taken. A meter changes address only by a removal and an installation, each with a reading. A correction later found for that meter follows it at the address and in the months it was there. Sources: Kyle 08-18, D-3 ("complete meter read history must stay with the meter and the service address"); Kyle 10-15, R-10; SCN-0037 (a correction follows the meter).

**Given** Pecan Flat. Meter M-7 served PF-06's house from 2024. It is removed on Mon Mar 15, 2027, and meter M-8 is set there the same day. M-7's shop test on Mar 18 finds it 4% slow (**invented**). It is refurbished, passes a test on May 10, and is set at PF-07's house on Mon May 17, 2027.

**When** (a) M-7's history is read; (b) PF-06's house's history is read; (c) the slow-meter correction is made; (d) a clerk changes M-7's premise directly to PF-07's house, with no removal or installation.

**Then**
- **(a)** M-7's readings run in order: at PF-06's house until its Mar 15 removal reading, then at PF-07's from its May 17 installation reading. Both tests are in its history.
- **(b)** PF-06's house shows M-7's readings until Mar 15, then M-8's. It never shows a reading M-7 took at PF-07's house.
- **(c)** The correction reaches only the months M-7 was at PF-06's house, bounded by Pecan Flat's backbilling rule, and goes to whoever was billed for each (SCN-0037). The passed test of May 10 is before PF-07's first reading, so PF-07 is untouched.
- **(d)** Refused (this stream's reading; not blocked today): a change of address is a removal and an installation, each with a reading.
- **Open (Ryan, for the rates stream):** a meter recorded at the wrong address from the start is a correction, not a move. How is it told apart from a move, and what happens to the readings already taken (CI-027)?
