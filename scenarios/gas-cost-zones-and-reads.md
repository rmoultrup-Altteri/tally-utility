# Gas cost, zones and factors, and meter reads

What the gas costs on a bill, the factors that turn a meter's raw reading into billed volume, and the readings themselves: estimates, re-reads, rollovers, meter changes. Invariants: CI-033 – CI-035 (the gas cost on the bill), CI-020 – CI-023, CI-026, CI-029 (zones, factors, rollover), CI-024, CI-025, CI-027, CI-030, CI-031, CI-090, CI-112 – CI-114 (reads, replacements, estimates). CI-034's text, a gas cost change inside a period prorated by days, is superseded by Kyle's ruling that the figure is never split (noted for the parity record). **Written ahead of its patches** (Ryan, 2026-11-25, DECISION-LOG): the rates stream's gas cost billing side, zones and factor tables, and read ownership and replacement reads are on its list but not claimed. Each scenario is written to the rulings and says what is built and what is not. The billing pipeline (`billing-pipeline-and-charge-composition.md`) already covers a gas cost credit and a pressure factor (SCN-0001, SCN-0055); dated factors are SCN-0078; keyed-wrong reads are `cancel-rebill.md` SCN-0002, 0027. Reviewed in round 7 (`review/2026-11-25-gas/`).

**Common to every scenario here.**
- **Gas cost is the billing side only.** The platform holds each approved gas cost figure, what was billed under it and the volumes. It keeps every past figure, so a rebill uses the figure the original bill used (except when that figure is itself corrected, SCN-0132). The utility's gas purchases, its over- or under-recovered balance and any cap on lost gas stay in its own accounting (Kyle 10-14, answers 6 and 7). The utility does its reconciliation from the platform's billing-side record (SCN-0134).
- **One figure per billing month.** A gas cost figure applies to a whole billing month, is never split by days, and cannot be changed in the ordinary way once locked (Kyle 11-03, answer 1). A bill's billing month is the month it is issued, at all three cast utilities (`cast.md` §6), and a figure is named by its billing month here ("December's figure" is the one on bills issued in December; SCN-0001 names the same figure by the month it was locked). The other rates follow the period, by the method stated for any rate change inside it (SCN-0001). The gas cost figure follows the billing month instead, and the bill records the month and the figure. The bill snapshot reads everything at one date, the period's last day, so how it records a figure picked by billing month is the rates stream's to solve.
- **A factor is stored with the raw quantity it multiplied** (Ryan 2026-11-04). A bill line shows the raw reading, each factor and the billed volume. All three utilities bill in Mcf, so no heating value or therm figures appear. No cast utility bills in an energy unit or has weather normalization; those wait for Gulf Plains' tariff and the weather family. **Today a bill line in Mcf without therm figures is refused at issue.** The money stream's patch carrying Ryan's 2026-11-04 decision is not drafted, so every worked bill here waits on it.
- **A reading is never overwritten once billed.** A re-read is a new reading that replaces the earlier one, names it, and states a reason from Kyle's list: re-read for high or low usage, re-read for a zero or missing read, re-read after an access problem, meter malfunction, estimate replaced by an actual, dispute recheck, tamper investigation, wrong meter, typo correction, other. Both readings stay (Kyle 08-18, D-5; Kyle 10-15, K-03). A reading's history stays with the meter and with the address (Kyle 08-18, D-3; Kyle 10-15, R-10).
- **Texas's meter-reading rule binds only Gulf Plains.** 16 TAC §7.45 sets standards for residential and small commercial gas service by a regulated utility, of its own force in unincorporated areas, and inside a city only where they don't conflict with the city's standards. GP-08 is in an unincorporated area. City systems such as Pecan Flat and Bluebonnet are not bound by it, even for customers outside the city limits. Their tariffs say nothing about estimates, so their settings in `cast.md` §6 are invented.
- **Dates** are 2026 unless stated. Every value in `cast.md` §6 is **invented**. New customers: BB-17 – BB-26, GP-08 – GP-11, PF-08 (`cast.md`). Each scenario stands alone unless it says it continues another.

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
- **Open (Kyle):** each utility states its billing month at onboarding (the issue month, or the month the period ends), as it states its method for a rate change. Is the issue month the right platform default, given (c)? The alternative gives BB-17 $0.42 and leaves (c) at $65.83.

---

### SCN-0131 — No figure locked for the month: the bills wait, and last month's figure is never used

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built** (as SCN-0130). The refusal is SCN-0001's, on Pecan Flat's facts, and the core's.
*Rule:* a bill is issued only with a locked figure for its billing month. Until one is locked, the bills that need it wait, with the reason shown. The run never falls back to the previous month's figure, unless the utility's tariff carries it forward (SCN-0149). A figure is locked when a supervisor approves it (this stream's reading). Sources: Kyle 11-03, answer 1; SCN-0001; Kyle 08-26, R-11 (a weather adjustment locks when approved: the same pattern, by analogy).

**Given** Pecan Flat. December's bills use November's purchase price. The supplier's invoice is late, so on Sun Dec 20 no figure is entered for December. November's bills used $6.10. PF-01 used 8.0 Mcf.

**When** (a) the December run starts on Dec 20; (b) on Dec 21 the clerk enters $6.85, not yet approved; (c) on Tue Dec 22 the supervisor approves it.

**Then**
- **(a)** Every Pecan Flat bill is held with the reason "no locked gas cost figure for December". No bill is issued at $6.10. The other lines are computed, but nothing is issued: a bill is issued whole or not at all.
- **(b)** Still held: an entered figure is not a locked one.
- **(c)** The bills are issued Dec 22. PF-01: 8.0 Mcf × $9.00 = $72.00, plus gas cost 8.0 Mcf × $6.85 = $54.80: **$126.80**, due Jan 1, 2027 as always. At $6.10 the gas cost would have been $48.80, and the bill $120.80.
- The figure's record shows who entered it, who approved it and when, and the supplier invoice it came from (an attached document).
- **Settled by rule (2026-11-25, triage of Kyle's questions):** a figure set mid-month from the supplier's invoice is the city's tariff ("adjusted monthly as necessary"); the lock is the supervisor's approval, as for a weather adjustment; a late bill keeps the due date its tariff states (the 1st here). Rule: follow the tariff, the platform default only where it is silent (Kyle 11-03).

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
- **Settled by rule (2026-11-25, triage of Kyle's questions):** the record carries both months, and the report totals by either; a report's layout is the stream's to settle.

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
- The expected result is (a). PF-02 is residential, so it pays no tax and the difference between the invariant and the schema does not show here; for a taxed customer it would (a minimum before tax, then tax on it, against a floor that includes the tax).
- **Settled by rule (2026-11-25, triage of Kyle's questions):** the minimum floors the whole bill, gas cost included, as CI-103 and the built schedule do (reading (a)). A city whose tariff floors the rate only would state it at onboarding.

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

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built** (zones and dated factors, CI-020, CI-026). Kyle's "never split" covers the gas cost figure only; a factor change follows his rate-change rule (settled by rule, below), and refusing a change entered with no method is the core's.
*Rule:* a factor change is handled like a rate change. When the utility enters the change, it states whether it is split by days, applied by read date, or applied by cycle, with no default. "By cycle" means what it means in SCN-0001: a period that straddles the change is billed wholly at the new factor. Sources: Kyle 11-03, answer 1 (the method for a rate change); SCN-0001; GBM's cross-month factor table (design, not a ruling: a factor that changes inside a period is weighted by days); Kyle 10-15, K-02.

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
- **Settled by rule (2026-11-25, triage of Kyle's questions):** a factor change follows the rate-change rule: the utility states the method when it enters the change, with no default (Kyle 11-03, answer 1, applied to factors).

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
- Each paid bill is credited and rebilled, and its payment moves to the corrected bill (SCN-0089). The $798.41 goes with the next regular bill, issued Sat Jan 16 and due Mon Feb 1, and ages from Jan 4.
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
- **Settled by rule (2026-11-25, triage of Kyle's questions):** (1) a request that finds the city wrong is waived and doesn't use up the free one (the reading that favours the customer, where the tariff is silent); (2) a read keyed too high is always rebilled, never left to catch up, because a refund is never held back (Kyle 11-03, answer 8).

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
- **Settled by rule (2026-11-25, triage of Kyle's questions):** the method, catch-up or rebill, is the utility's setting (CI-114; Kyle 10-15, R-11), and catch-up is the platform default.
- **Open (Kyle):** in (b′), is a credit for usage below the estimate right (whether usage can ever be negative is not ruled), and should it be priced at the estimated month's rates? A bill with a credit line also reads open after it is paid (the money stream's note on negative lines), so (b′) needs that rule too.

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
- **Open (Kyle, or tariff counsel):** (1) is an aggressive dog beyond a utility's control? The sorting of reasons is a proposal. (2) A card the customer returns is a customer reading. Does it count as the actual reading Texas requires every six months? (That it ends the run of estimates is built behaviour, SCN-0158; batch 7 asked both halves before this was seen, and a different answer on the run would change the built rule.) Kyle 07-10 said "no customer-initiated reads in v1"; this one the utility asked for.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** an actual reading dated earlier than estimates already entered does not clear the run (the built rule, AC-21; the conservative choice), and the core raises a review on it (SCN-0160). A cap above Texas's six months is ruled out by DE-1, not yet enforced: noted for the rates stream.

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

---

## Added cases (2026-11-25, the reviewers' gaps; reviewed in round 8, `review/2026-11-25-gas-2/`)

### SCN-0146 — A move-out partway through the month: two bills for one meter in one billing month, one figure

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** a utility setting, with a per-schedule override, for the fixed charge when a customer changes partway through a period: a share by days (the platform default), both customers pay in full, or whoever holds the account at the period's end pays in full. The line records which was applied. **Not built:** the gas cost figure by billing month (as SCN-0130); one reading that is both one customer's final and the next one's first is recorded once, marked as the boundary between the two customers (built), and named by both bills.
*Rule:* every bill issued in a billing month uses that month's one figure, however many bills a meter has that month and whatever period each covers. A final bill is a bill like any other. A part-month customer charge follows the utility's setting; where the tariff is silent, the platform default, a share by days, applies. Sources: Kyle 11-03, answer 1; SCN-0130; Kyle 11-03 (standing rule: the platform default where the tariff is silent).

**Given** Bluebonnet; BB-17 (R-U, inside the city, read on the last day of the month). Its bill for November's gas was issued Wed Dec 2 (SCN-0130 (b), $0.58). BB-17 moves out on Thu Dec 10, and the final reading that day shows 2.4 Mcf since Nov 30. BB-20 takes service from Fri Dec 11 at that reading; its Dec 31 reading shows 5.1 Mcf. Bluebonnet's tariff bills "the customer charge for each month of the year, regardless of whether service is disconnected during the summer months" (Brenham's words). That speaks to a customer with service all year, not to a part month, so Bluebonnet keeps the platform default (**invented**: its setting).

**When** (a) the final bill is issued Fri Dec 11; (b) BB-20's first bill, Dec 11 – 31, is issued Mon Jan 4, 2027.

**Then**
- **(a)** December's figure, $0.58, the same as on BB-17's Dec 2 bill. Dec 1 – 10 is 10 of December's 31 days:

| Line | Share by days (expected) | Full customer charge (the "both pay in full" setting) |
|---|---|---|
| Customer charge | 12.80 × 10 ÷ 31 = 4.1290: $4.13 | $12.80 |
| Distribution, 2.4 × $2.96 | $7.10 | $7.10 |
| Commodity, 2.4 × $5.35 | $12.84 | $12.84 |
| Gas cost adjustment, 2.4 × $0.58 | $1.39 | $1.39 |
| City sales tax 1% | on $25.46: $0.25 | on $34.13: $0.34 |
| **Total** | **$25.71** | **$34.47** |

  Due 15 days after issue, Sat Dec 26, moved to the next workday: Mon Dec 28.
- **(b)** January's figure, $0.71, though all BB-20's gas was used in December: the bill is issued in January (SCN-0130). Dec 11 – 31 is 21 days: customer charge 12.80 × 21 ÷ 31 = 8.6710, so $8.67; distribution 5.1 × $2.96 = $15.10; commodity 5.1 × $5.35 = $27.29; gas cost 5.1 × $0.71 = $3.62; city sales tax 1% on $54.68 = $0.55: **$55.23**. Its taxes are the period's, 2026's, with no crime-control district (as in SCN-0138).
- The two customer charges, $4.13 and $8.67, add to $12.80: one month's charge for the premise.
- The Dec 10 reading ends BB-17's billing and starts BB-20's: one reading of the meter, named by both bills.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** a share by days, the platform's built default, applies where the tariff is silent (Kyle 11-03: the platform default where the tariff is silent). A city whose tariff charges each customer the full month sets that at onboarding.

---

### SCN-0147 — A month missed with no estimate: two months billed on one read

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** the choice not to estimate is recorded as a setting (estimates allowed or not, for the utility, a rate schedule or a meter, with a reason), and a billing run records a meter skipped for no read. **Not built:** a dated record that one month's route was skipped and why; the gas cost figure by billing month (as SCN-0130); a minimum bill that counts per month covered (the minimum is one amount per bill).
*Rule:* at a utility with no fixed monthly charge, when a meter is not read and the utility has chosen not to estimate, no bill is issued that month. The next reading bills all the gas since the last one, on one bill, at that bill's billing month's figure. The minimum bill counts once per month covered. The high-usage check compares usage per month covered. (At a utility with a monthly customer charge, the skipped month's charge is still owed; CI-102.) Sources: Kyle 11-03, answer 1 (never split within a billing month); Pecan Flat's tariff (`cast.md` §1, $20.00 a month); CI-102.

**Given** Pecan Flat, which has no customer charge; PF-01 (its meter reads in Mcf). The Oct 15 reading is 1,172.0. Pecan Flat's November route is not read (the reader is ill), and the city records its choice not to estimate it. November's figure was $6.10, December's is $6.85. In the same months last year PF-01 used 7.6 and 7.9 Mcf.

**When** the Dec 15 reading is (a) 1,188.0; (b) 1,174.0, and the December bill is issued Sun Dec 20.

**Then**
- **(a)** 16.0 Mcf over two months is 8.0 a month, within 150% of last year, so the read passes with the reason "two months on one read". One bill for Oct 15 – Dec 15: 16.0 × $9.00 = $144.00, plus gas cost 16.0 × $6.85 = $109.60: **$253.60**, due Jan 1. It passes the $40.00 minimum for two months.
- **(b)** 2.0 Mcf: $18.00 + $13.70 = $31.70, raised to the two-month minimum by an adjustment of $8.30: **$40.00**. (Counted once per bill, $31.70 would pass the $20.00 minimum.)
- No gas is billed at November's $6.10: no bill was issued in November. Nothing fell due on Dec 1, and no penalty runs on it.
- The bill shows both readings, their dates, and that it covers two months.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** (1) whether to estimate a missed month or skip it is the utility's built setting; (2) the $20.00 minimum is "a month" in the tariff, so it counts per month covered.

---

### SCN-0148 — Gulf Plains: no actual reading in six months

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** the cap's exception and its override; the Texas law rows' cause "catch-up after estimates" (allowed, no limit, able to ground a cut-off only where the missed reads were beyond the utility's control). **Not built:** the six-month check, which is the core's (CI-090), since the built override would let an estimate through after six months; the utility's method for correcting estimates (CI-114).
*Rule:* where 16 TAC §7.45 binds, estimates are allowed only while an actual reading is taken at least every six months, and bills are rendered monthly. When six months pass without an actual reading, the platform reports the breach and keeps reporting it until an actual is taken. It does not quietly hold the bill. The next estimate needs a supervisor's recorded acknowledgment of the breach and a field order to get an actual reading (this stream's reading). The catch-up then bills all the gas the estimates missed, with no limit, recorded as a catch-up after estimates and reported with the run behind it. Sources: 16 TAC §7.45(6)(A) (bills monthly), (6)(C); Kyle 09-02, R-21 (a catch-up over six months of estimates is "on its face evidence the utility breached (6)(C)"; the platform should "surface that, not quietly bound it"; the catch-up is "uncapped").

**Given** Gulf Plains; GP-09, residential, unincorporated, behind a locked gate the customer keeps closed, with a meter the customer could read. The last actual reading was Mon Mar 1, 2027. Every read from Apr 1 to Sep 1 fails. A self-read card went each month from May; none came back. Each estimate past the cap was approved by a supervisor's override. GP-09's own use in the same months of 2026 gives six estimates totalling 29.1 Mcf (9.0, 7.2, 4.8, 3.1, 2.6, 2.4).

**When** (a) the Sep 1 estimate is approved for the Sep 5 bill; (b) a field order by appointment gets an actual reading on Fri Oct 1: 36.9 Mcf used since Mar 1.

**Then**
- **(a)** Six months have passed since Mar 1 with no actual reading. The Sep 1 estimate needs the supervisor's acknowledgment of the breach and a field order, both recorded. The Sep 5 bill is issued, marked "Estimated", and the breach goes on the report of six-month breaches.
- **(b)** The Oct 1 actual is validated, which ends the run of estimates. The Oct 5 bill bills 36.9 − 29.1 = **7.8 Mcf**: $15.00, delivery 7.8 × $4.10 = $31.98, gas cost 7.8 × $3.40 = $26.52, for **$73.50**. It is recorded as a catch-up after estimates, with no limit, and reported with the six estimates behind it. A locked gate the customer keeps closed is beyond the utility's control under the engineering proposal (SCN-0142 (e)), so the catch-up could ground a cut-off if unpaid (provisional).
- **Open (Kyle):** once six months have passed, should the next bill be held instead, which sets the six-month duty against the monthly-billing duty, or issued on an estimate with the breach recorded, as here?

---

### SCN-0149 — Gulf Plains files no new factor: its approved tariff carries the last one forward

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Not built** (as SCN-0130). The carry-forward is Gulf Plains' invented tariff term (`cast.md` §6); a regulated utility's term comes from the Commission's order in its rate case (§7.5519(c)).
*Rule:* whether a missing figure holds the bills or carries the last one forward is the utility's approved tariff term. A carried figure is recorded as the month's figure, marked carried, with the term that allows it. It is locked when a supervisor confirms that nothing was filed (this stream's reading). A late filing applies from the next billing month. Where §7.45 binds, the bill shows the gas cost per billing unit. Sources: `cast.md` §6; 16 TAC §7.45(6)(B)(v) (a bill shows "the total of any adjustments to the base bill and the amount of adjustments per billing unit"); Kyle 07-10, T-1 (a bill on a stale or missed figure is rebilled; it does not reach this case, because under the tariff the carried figure is the right one); SCN-0131 (the city that holds).

**Given** Gulf Plains files its factor by the last business day of each month for the next month's bills. Its tariff (**invented**) says a factor stays in effect until a new one is filed, and a factor filed during a month first applies to the next month's bills. September's factor is $3.40. Nothing is filed by Thu Sep 30, 2027. A factor of $3.90 is filed on Fri Oct 8. GP-08 used 2.9 Mcf in September.

**When** (a) on Fri Oct 1 the supervisor confirms nothing was filed; (b) the October bills are issued Tue Oct 5; (c) the $3.90 is filed; (d) a final bill is issued Tue Oct 12 to another customer.

**Then**
- **(a)** October's figure is recorded as $3.40, carried forward under the tariff term, and locked by the supervisor's confirmation.
- **(b)** The bills are not held, unlike Pecan Flat's (SCN-0131). GP-08: $15.00, delivery 2.9 × $4.10 = $11.89, gas cost 2.9 × $3.40 = $9.86: **$36.75**. The bill shows the gas cost as $3.40 per Mcf beside its total.
- **(c)** The $3.90 is November's figure. October's bills are not rebilled. At $3.90, GP-08's bill would have been $38.20.
- **(d)** Still $3.40: October's figure is locked for every October bill.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** carrying a factor forward, and when a late filing applies, are the utility's approved tariff terms, entered at onboarding.

---

### SCN-0150 — A meter destroyed with no removal reading, on a customer with no history to estimate from

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** an estimated reading and its reason; a fixed list of estimate methods (three-month average, twelve-month average, same month last year, last actual, zero); a fallback to a platform method when a schedule names none. **Not built:** an estimate set by a supervisor, its basis and its approval (none is in the method list, and no field holds a basis); an estimated removal reading.
*Rule (this stream's reading):* when the utility's method has too little history to run, the core does not fall back to another method on its own. (The built fallback is for a schedule that names no method, not for a method that cannot run.) A supervisor sets the estimate and its basis, both recorded, and the bill is marked as estimated. A removal reading that cannot be taken is estimated the same way. The new meter's use is measured from its own installation reading. Sources: Kyle 07-10, D3B-2 ("measurement-critical attributes must be affirmed, never defaulted"); Kyle 11-05, answer 13 (with no test history, a supervisor approves the estimate with its basis; ruled for a stopped meter, used here by analogy); CI-024; SCN-0144.

**Given** Bluebonnet; BB-18 (LC-R, Industrial Park, 1.0400), in service from Nov 20. Its one billed period, Nov 20 – Dec 14, used 30.0 Mcf raw over 25 days. Bluebonnet estimates from the average of the last three billed months (`cast.md` §6). On Fri Jan 8, 2027 a truck destroys the meter, and its index can't be read. A new meter is set the same day at 0.0, and its pressure test agrees with 1.0400. The Jan 15 reading on the new meter is 7.0. January's figure is $0.71.

**When** the January bill (Dec 15 – Jan 14) is prepared for issue on Sat Jan 16.

**Then**
- There are not three billed months, so Bluebonnet's method can't run, and the removal reading is held for a supervisor. The supervisor sets it at 28.8 Mcf of use since Dec 15: BB-18's daily average (30.0 over 25 days, 1.2 a day) for the 24 days to Jan 8. The basis is recorded, with the reason "other: meter destroyed".
- The bill is marked "Estimated": 28.8 estimated + 7.0 actual = 35.8 Mcf raw × 1.0400 = 37.2320 Mcf. That is $82.90, distribution $86.01, commodity $199.19, gas cost 37.232 × $0.71 = $26.43, state $24.66, county $1.97: **$421.16**. The line shows both meters, the estimated part and the factor.
- The run of estimates for the new meter starts at zero. The destroyed meter's estimated removal reading is its last.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** the supervisor chooses the basis case by case and records it; the record is what matters, not a fixed method.

---

### SCN-0151 — Bluebonnet at its estimate limit: the cap works; Texas's card and six months don't apply

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** the cap and its exception, resolved by an override or a field order (AC-20, AC-21). **Not built:** the cut-off check is the collections rules' (-26, not mirrored).
*Rule:* a city's own cap on estimates in a row works as at Gulf Plains. Texas's card, its six-month actual reading and its bar on a cut-off for an estimated bill do not bind a city system. A city that wants them says so in its tariff. Sources: AC-20, AC-21; 16 TAC §7.45's scope; SCN-0142.

**Given** Bluebonnet; BB-09 (R-R, outside the city). A validated actual reading on Nov 15, 2026, so no estimates in a row. The gate is locked on Dec 15, 2026, Jan 15, 2027 and Feb 15, 2027. Bluebonnet's cap is 3, and its tariff says nothing about estimates.

**When** the three bills are prepared; the supervisor resolves February's exception by an override; BB-09 doesn't pay the February bill.

**Then**
- December and January are estimated, and each bill is marked. On Feb 15 the third estimate raises the exception. The supervisor's override is recorded, and the February estimate is approved, as at Gulf Plains (SCN-0142 (c)).
- No card is required in January, and no six-month reading is required.
- Bluebonnet's tariff is silent on a cut-off for an estimated bill, so under the go-live rule it stated one at onboarding: an estimated bill may ground a cut-off (`cast.md` §6, **invented**). So nothing bars the cut-off because the bill is estimated. (Where the collections rules read this is not built.)
- **Settled by rule (2026-11-25, triage of Kyle's questions):** whether an estimated bill can ground a cut-off at a city is one of the settings the cut-off checks need, so the city states it before go-live (Ryan 2026-11-25, the go-live rule).

---

### SCN-0152 — A read that doesn't move: a stopped meter, or a house that used nothing

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** a low-usage setting (a fraction of the customer's own history, default 25%) and a separate check for zero on an active account. **Not built:** Kyle's starter rule of 10% of the class average (Pecan Flat has one class, so a café would be measured against homes); the re-read reason (SCN-0139).
*Rule:* a reading flagged as too low or zero is held and re-read ("re-read for a zero or missing read"). A re-read is a lead, not a finding: a meter is found stopped only by a field check or a shop test. A meter found stopped before its month was billed is billed for that month on an estimate a supervisor approves, with its basis; that is the month's own bill, not a backbill. A zero the re-read confirms, with no sign of a fault, is billed as zero, with the minimum. Sources: Kyle 07-10, D3A-2 (the starting low checks); Kyle 11-05, answer 13 ("a meter reader's report alone is a lead, not a finding"; a supervisor's approval with the estimate's basis); Pecan Flat's minimum (`cast.md` §1).

**Given** Pecan Flat, December's figure $6.85. (a) PF-03, a café open every day (taxed: state 6.25%, city 1.5%), read 300 Ccf (30.0 Mcf) in each of its last three months. Its Nov 15 reading is 2,340 Ccf, and the Dec 15 reading is 2,340. (b) PF-02, a renter, is away from Oct 20 to Dec 20. Its readings are 1,300 Ccf on Oct 15, 1,312 on Nov 15 (billed in November at 1.2 Mcf) and 1,312 on Dec 15.

**When** the December readings are checked.

**Then**
- **(a)** Zero at an open café is flagged, and the read is held. The re-read finds the same index with the burners on: a lead. The field check finds the dial stopped and is recorded as the finding. The meter is replaced. December's bill is estimated, reason "meter malfunction", at 29.0 Mcf, the café's three-month average (30.0, 30.0 and 27.0, **invented**), with the supervisor's approval: 29.0 × $9.00 = $261.00, gas cost 29.0 × $6.85 = $198.65, state 6.25% of $459.65 = $28.73, city 1.5% = $6.89: **$495.27**, marked "Estimated". No backbilling limit comes into it: nothing was billed short.
- **(b)** Zero is flagged (under 25% of PF-02's own history). The re-read confirms 1,312, and the house is empty. The bill is zero usage, raised to the **$20.00** minimum (PF-02 is residential, so no tax). The record shows the re-read and why the zero stood.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** (1) the low-usage check is the utility's setting, built as a fraction of the customer's own history; (2) a zero bill already issued is corrected under the city's six-month default for an undercharge (SCN-0019; Kyle 11-05, answers 10 – 12); Texas's three-month rule for a stopped meter binds regulated utilities only.

---

### SCN-0153 — A pressure factor where it doesn't belong, missing where it does, or wrong

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. **Built:** a meter is either base or elevated pressure, and an elevated meter with no factor is refused billing (CI-023). **Not built:** nothing stops a factor other than 1.0000 on a base-pressure meter (CI-029), so that refusal is the core's; zones (SCN-0136). The cause "billing constant error" exists only in the Texas law rows, which bind regulated utilities. For Bluebonnet the city's six-month default applies (SCN-0019, not built), and how the correction reaches the customer is unruled (SCN-0138's Open).
*Rule:* a base-pressure meter is billed at 1.0000, never another factor. An elevated meter is not billed without a factor. A wrong factor is corrected like a billing constant error: an overcharge is refunded as far back as the records show, and an undercharge is charged within the city's six months. Sources: CI-023, CI-029; Kyle 09-23 (a pressure factor "converted wrong" is a billing constant error); Kyle 11-03, answer 8 (refunds); SCN-0019; SCN-0138.

**Given** Bluebonnet, December's figure $0.58. (a) A clerk enters a factor of 1.0400 on BB-14's meter, a homeowner's base-pressure meter. (b) BB-18's new meter is recorded as elevated pressure with no factor. (c) Instead, BB-18's premise was assigned the Standard zone by mistake. Its meter was confirmed against it, and the Dec 16 bill (Nov 20 – Dec 14, 30.0 Mcf raw, the customer charge a share by days, 25 of 30 days) used 1.0000. A line survey on Mon Jan 4, 2027 finds the error.

**When** (a) and (b) the December run reaches the meter; (c) the correction is made on Jan 4.

**Then**
- **(a)** BB-14's bill is held: a factor other than 1.0000 on a base-pressure meter. Had a bill gone out at 1.0400, the overcharge would be refunded in full.
- **(b)** Refused by the built check. Once the confirmed 1.0400 is entered, the bill is issued.
- **(c)** The premise's zone is corrected to Industrial Park from Nov 20, and the wrong assignment and the confirmation against it stay as history. Customer charge 82.90 × 25 ÷ 30 = 69.0833, so $69.08 on both bills:

| | Billed at 1.0000 | Corrected at 1.0400 |
|---|---|---|
| Billed volume | 30.0 Mcf | 31.2 Mcf |
| Distribution, commodity, gas cost | $69.30, $160.50, $17.40 | $72.07, $166.92, $18.10 |
| State 6.25%, county 0.5% | $19.77, $1.58 | $20.39, $1.63 |
| **Total** | **$337.63** | **$348.19** |

  The **$10.56** the error hid goes with the next bill, issued Sat Jan 16 and due Mon Feb 1 (15 days is Sun Jan 31). It is recorded as a factor converted wrong, with the survey as the finding. The difference doesn't depend on how the customer charge is shared.

---

### SCN-0154 — A meter with a multiplier and a pressure factor: each step shown, four decimals carried

*Status:* draft (2026-11-25); in batch 7 for Kyle (K-20), not yet sent. A meter's multiplier and factor are recorded on the meter (built); the chain's arithmetic is the core's (CI-021, CI-022).
*Rule:* the raw index difference is multiplied first by the meter's multiplier, then by the pressure factor. The billed volume is carried to four decimals, half-up, and each line's dollar amount is rounded to the cent. The line shows each step. Sources: CI-021; Kyle 10-15, K-06 ("intermediate math carry four decimals", half-up to the cent); Ryan 2026-11-04 (a multiplier is stored with its raw quantity).

**Given** Bluebonnet; BB-21, a dry cleaner on Mill Road, outside the city (LC-R; the Mill Road pressure zone, 1.0437, `cast.md` §6), on a meter with a multiplier of 10 that reads to hundredths. Its December index difference is 4.27. December's figure is $0.58.

**When** the December bill is computed.

**Then**
- 4.27 × 10 = 42.70 Mcf metered, × 1.0437 = 44.56599, carried as **44.5660 Mcf** billed. The line shows 4.27, 10, 42.70, 1.0437 and 44.5660.
- $82.90; distribution 44.5660 × $2.31 = 102.9475, so $102.95; commodity 44.5660 × $5.35 = 238.4281, so $238.43; gas cost 44.5660 × $0.58 = 25.8483, so $25.85; state 6.25% of $450.13 = $28.13; county 0.5% = $2.25: **$480.51**.
- Here the unrounded volume gives the same cents. The test asserts the carried 44.5660 and the order of the steps.

---

## Added cases (2026-11-26, round 8's remaining gaps; reviewed in round 9, `review/2026-11-26-gas-3/`)

### SCN-0155 — A final reading that can't be taken: the estimated final bill is put right at the next occupant's first actual

*Status:* draft (2026-11-26); the question below is for Kyle's batch 8. **Built:** a reading can be recorded as estimated, with the purpose "final read", and marked as the boundary between an outgoing and an incoming customer; the part-month customer charge setting (as SCN-0146). **Not built:** the move-out itself, a final reading, a final bill and the deposit's disposition, is the core's (CI-122, partly built); so is sharing the gas between two actual readings across a change of customer; the gas cost figure by billing month (as SCN-0130).
*Rule (this stream's reading):* when a move-out reading can't be taken, the final reading is estimated, marked, and closes one customer's billing and opens the next one's. An estimated final bill is not left to stand, because the departing customer has no later bill to catch it up. When the next actual reading comes, the gas between the last actual before the move and that one is shared by days between the two customers. A replacement final reading, at the departing customer's share, replaces the estimate; both are kept. The final bill is voided and corrected at its own billing month's figure, and the new customer's first bill starts from the replacement reading. A part-month estimate is the utility's monthly estimate shared by the days covered, rounded half-up to the meter's tenth. Sources: GBM `application/configurable-rules/workflows/final-bill-generation.md`, exception 1 only (an estimated final bill has "no next cycle to true it up in"; the same workflow's full customer charge on a final bill is superseded here by SCN-0146; its invariant numbers are an older numbering); `knowledge/24-billing-failures-index.md` (the named failure: an estimated final bill "never reissued when actual differs"); CI-122; SCN-0133 (a correction uses the voided bill's billing month); Kyle 11-03, answer 17, and SCN-0029 (a credit left when a deposit-paid final bill is corrected down is a deposit refund, paid out whatever its size); SCN-0146.

**Given** Bluebonnet; BB-22 (R-U, inside the city, read on the last day of the month; deposit $150). Its Nov 30 actual reading is 4,100.0, and its last three months billed on actual readings averaged 9.3 Mcf. Its December 2 bill, for November's gas, is paid. BB-22 moves out on Thu Dec 10. The house is locked and the meter is inside a locked yard, so the final reading can't be taken. BB-23 (R-U, the new owner, also read on the last day of the month) takes service from Fri Dec 11. BB-23's first actual reading, on Thu Dec 31, is 4,108.0. December's figure is $0.58, January's $0.71. Both customer charges are a share by days (Bluebonnet's setting, `cast.md` §6).

**When** (a) the final bill is issued Fri Dec 11, and the deposit's remainder is refunded by check on Mon Dec 14; (b) the Dec 31 actual is validated, and on Mon Jan 4, 2027 the final bill is corrected and BB-23's first bill is issued; (b′) instead, the Dec 31 actual is 4,112.0.

**Then**
- **(a)** The final reading is estimated at 4,103.0: 9.3 × 10 ÷ 31 = 3.0 Mcf, for 10 of December's 31 days. Its reason is "access issue: locked gate", and it is marked as the final reading, an estimate, and the boundary between BB-22 and BB-23. The final bill, marked "Estimated": customer charge $4.13 (as SCN-0146), distribution 3.0 × $2.96 = $8.88, commodity $16.05, gas cost 3.0 × $0.58 = $1.74, city sales tax 1% on $30.80 = $0.31: **$31.11**, due Mon Dec 28. The deposit pays it, and **$118.89** is refunded on Dec 14 (Bluebonnet's route (b), at disconnection).
- **(b)** From Nov 30 to Dec 31 the meter moved 8.0 Mcf over 31 days: 10 days BB-22's, 21 days BB-23's. BB-22's share is 8.0 × 10 ÷ 31 = 2.5806, so 2.6 Mcf. BB-23's is the rest, 5.4 Mcf: the second share takes the remainder, so the two add to what the meter measured. The replacement final reading is 4,102.6, reason "other: shared by days at the next actual", naming the estimate.
  - The final bill is voided and corrected at December's figure, $0.58, its own billing month's, though the correction is issued in January (SCN-0133): $4.13, distribution $7.70, commodity $13.91, gas cost $1.51, tax 1% on $27.25 = $0.27: **$27.52**. Its taxes are 2026's, the period's. The void and the correction leave BB-22 a credit of **$3.59**. The deposit's application and the Dec 14 refund stay as they happened (SCN-0029). The $3.59 is paid out as a further deposit refund, so $122.48 is refunded in all, and the account can't close until it is paid.
  - BB-23's first bill starts from 4,102.6, at January's figure (SCN-0146 (b)): customer charge $8.67, distribution 5.4 × $2.96 = $15.98, commodity $28.89, gas cost 5.4 × $0.71 = $3.83, tax 1% on $57.37 = $0.57: **$57.94**. Its taxes are 2026's (as SCN-0146).
  - Had BB-23 instead been billed from the estimated reading, it would pay for 5.0 Mcf ($54.31) and BB-22 would keep its 3.0, whatever the meter showed. The estimate's error would stay with whichever customer it happened to favour.
- **(b′)** 12.0 Mcf over the 31 days: BB-22's share 12.0 × 10 ÷ 31 = 3.8710, so 3.9 Mcf, and BB-23's 8.1. The estimate was low. BB-22's corrected final bill: $4.13, $11.54, $20.87, $2.26, tax on $38.80 = $0.39: **$39.19**, so BB-22 owes **$8.08** more after the deposit's remainder has gone back. There is no next bill, so it is due 15 days after the correction, Tue Jan 19, 2027 (SCN-0033's rule for a corrected final bill). BB-23's first bill is 8.1 Mcf: $8.67, $23.98, $43.34, $5.75, tax on $81.74 = $0.82: **$82.56**. (Billed from the estimated reading it would be 9.0 Mcf, $90.75.)
- BB-23's bill shows that its starting reading replaced an estimate and that the gas was shared by days.
- **Open (Kyle):** when a final reading is estimated, is the gas up to the next actual reading shared by days between the two customers, with the final bill corrected either way, as here? Or does the new customer bill from the estimated reading, so the final bill stands? We'd make it a utility setting, with sharing by days as the default.

---

### SCN-0156 — A month missed with no estimate at Bluebonnet: the customer charge is still billed that month

*Status:* draft (2026-11-26). **Built:** the choice not to estimate, as a setting for a rate schedule or a meter (as SCN-0147); a billing run records a meter skipped for no read; a fixed monthly charge exists as a kind of charge. **Not built:** billing the customer charge whatever the usage, so that a skipped read never drops it, is the core's (CI-102, no schema guard); a bill of the customer charge alone, marked "no reading this month"; a dated record that one month's route was skipped and why (as SCN-0147); the gas cost figure by billing month (as SCN-0130).
*Rule:* at a utility with a monthly customer charge, a month with no reading and no estimate still has a bill: the customer charge alone, marked "no reading this month". The next reading bills all the gas since the last one, at that bill's billing month's figure, with one month's customer charge. The high-usage check compares usage per month covered. Sources: CI-102 (a customer with no usage still gets a bill carrying the customer charge; the parity record says the core must not let a skipped read drop it); Bluebonnet's minimum bill, the customer charge every month (`cast.md` §2); SCN-0147.

**Given** Bluebonnet; BB-24 (R-R, outside the city: $14.75 a month, $3.41 per Mcf; no tax). The Oct 15 actual reading is 820.0. The Sun Nov 15 route is not read (the reader is ill), and Bluebonnet records its choice not to estimate it. In the same months last year BB-24 used 6.8 and 7.4 Mcf (its history from the old system, loaded at go-live). November's figure is $0.42, December's $0.58.

**When** (a) the November bills are issued Mon Nov 16; (b) the Dec 15 actual reading is 834.4, and the December bill is issued Wed Dec 16.

**Then**
- **(a)** BB-24's November bill is the customer charge for Oct 16 – Nov 15, **$14.75**, marked "no reading this month", due Tue Dec 1. No gas is billed at November's $0.42.
- **(b)** 14.4 Mcf over two months is 7.2 a month, within 150% of last year's month, so the read passes with the reason "two months on one read". The bill covers the gas from Oct 15 to Dec 15 and the customer charge for Nov 16 – Dec 15: $14.75, distribution 14.4 × $3.41 = $49.10, commodity 14.4 × $5.35 = $77.04, gas cost 14.4 × $0.58 = $8.35: **$149.24**. It carries one customer charge, not two: November's was billed in November.
- The bill shows both readings, their dates, and that its gas covers two months.
- **Settled by rule (2026-11-26):** a customer charge is billed in the month it is owed, so a skipped read never drops it (CI-102). Holding it for a two-month bill instead ($29.50 on a $163.99 bill) is the alternative a utility could state at onboarding; nothing in Bluebonnet's tariff asks for it.

---

### SCN-0157 — A rebill of a bill that used a carried-forward figure keeps the carried figure

*Status:* draft (2026-11-26). **Not built** (as SCN-0133 and SCN-0149).
*Rule:* a correction uses the voided bill's billing month's figure (SCN-0133). Where that figure was carried forward under the tariff, the carried figure is the month's figure, so the correction uses it, even after a later figure has been filed. A downward correction keeps the original due date. Sources: SCN-0133; SCN-0149; Kyle 10-14, answer 6 ("rebills use the factor in effect at the time"); Kyle 11-05, answer 2 (the amount the customer already knew about keeps its due date), and SCN-0033.

**Given** SCN-0149's facts: Gulf Plains carried $3.40 forward as October 2027's figure, and $3.90 was filed on Fri Oct 8 for November's bills. GP-08's October bill, issued Tue Oct 5 for 2.9 Mcf, was **$36.75**, due Mon Oct 25, and is unpaid. On Thu Oct 21 the reading is found keyed wrong: the meter photo shows 2.4 Mcf used.

**When** the October bill is voided and corrected on Oct 21.

**Then**
- The correction uses October's figure, $3.40, though $3.90 is now on file: $15.00, delivery 2.4 × $4.10 = $9.84, gas cost 2.4 × $3.40 = $8.16: **$33.00**, still due Mon Oct 25. At $3.90 it would be $34.20, and issuing it so is refused by the core (SCN-0133).
- The correction names October as its billing month, with the figure marked carried, and the billing-side record counts the change against October's figure (SCN-0134).
- A correction issued in December, or a year later, gives the same $33.00.

---

### SCN-0158 — Gulf Plains: the self-read card comes back

*Status:* draft (2026-11-26); part of it is with Kyle (batch 7, question 6). **Built:** the reading method "customer reported"; the run of estimates ends at a validated reading not marked as an estimate, whatever its method (AC-21); a same-day estimate beside an actual is not counted. **Not built:** the card itself (the communication log, CI-095); entering the card's reading as not an estimate, which the core does (nothing stops a customer reading being entered as an estimate); the six-month check (CI-090), which would decide whether a customer's reading counts.
*Rule:* a reading the customer sends on the utility's card is recorded with the method "customer reported", is checked like any other reading, and once validated is the meter's reading for the period. Where it arrives in time for billing, the bill is rendered on it, catching up the gas the estimates missed. Where it arrives after the bill, the billed estimate stands and the reading is kept and reviewed (as SCN-0160). As built, a validated customer reading is not an estimate, so it ends the run of estimates. Whether it is the actual reading Texas requires every six months is Kyle's question. Sources: 16 TAC §7.45(6)(C) (the card in the second straight month without access; "If such a postcard is not received by the utility in time for billing, the utility may estimate"); AC-21; SCN-0141 (catch-up); SCN-0142.

**Given** SCN-0142's facts, with readings: GP-08's actual reading on Mon Mar 1, 2027 is 1,050.0. The Apr 1 read fails (an aggressive dog), and April's bill was estimated at 9.0 Mcf, $82.50, an estimated reading of 1,059.0. The May 1 read fails too, and the reader leaves the card. GP-08 reads the meter that evening, Sat May 1, and fills in 1,066.1.

**When** (a) the card reaches Gulf Plains on Mon May 3, and the May bill is issued Wed May 5; (b) instead, the card reaches Gulf Plains on Fri May 7.

**Then**
- **(a)** The reading is dated May 1, with the method "customer reported" and the card's arrival date. It passes the usage checks and is validated, so no estimate is made for May. The May bill bills 1,066.1 − 1,059.0 = 7.1 Mcf: $15.00, delivery 7.1 × $4.10 = $29.11, gas cost 7.1 × $3.40 = $24.14: **$68.25**, not marked "Estimated". Over March and April, 16.1 Mcf has been billed: what the meter shows. Estimates in a row: 0.
- **(b)** The May 5 bill was estimated at 7.2 Mcf, **$69.00**, an estimated reading of 1,066.2 dated May 1 (SCN-0142 (b)). The card's reading, the same date and 0.1 Mcf lower, is kept and reviewed; the billed estimate stands, and June catches up from 1,066.2. As built, the run of estimates ends: the card's reading is an actual dated the same day as the estimate, and a same-day estimate beside an actual is not counted. That is unlike SCN-0160, where an actual dated two days earlier leaves the run as it was.
- If Kyle rules that a customer's reading is not Texas's actual reading, the run still ends as built, but the six months still count from Mar 1, so an actual is needed by Sep 1. The six-month check (CI-090) would then have to tell a customer's reading from the utility's.

---

### SCN-0159 — A second and third estimate under the three-month average: estimated months don't feed the next estimate

*Status:* draft (2026-11-26). **Built:** the three-month average as a method; the cap and its exception (AC-20, AC-21). **Not built:** which months the average reads. The method is a name in a list, and what it averages is the core's. (A built three-month average on a meter's summary mixes estimated readings with actual ones; it is not the estimator, and the core must not reuse it.)
*Rule:* Bluebonnet's stated method averages the customer's last three months billed on actual readings: estimated months are skipped, so an estimate is never built on another estimate (**invented**: its setting, `cast.md` §6). The average is worked to four decimals and rounded half-up to the meter's tenth. A catch-up reading is checked on the gas since the last actual reading, per month covered. Sources: `cast.md` §6 (Bluebonnet's method and cap); Kyle 10-15, R-11 (estimation is dated rule data, so a utility's method is its own); Kyle 10-15, K-06 (four decimals, half-up); AC-21; SCN-0141; SCN-0156.

**Given** Bluebonnet; BB-25 (R-R, outside the city; no tax). Its last three months billed on actual readings, to Jun 15, Jul 15 and Aug 15, used 1.8, 2.1 and 3.0 Mcf, an average of 2.3. The Aug 15 reading is 600.0. The gate is locked on Sep 15, Oct 15 and Nov 15. In the same four months last year BB-25 used 2.6, 3.1, 3.4 and 5.2 Mcf. The figures are September's $0.30, October's and November's $0.42, December's $0.58. On Dec 15 the actual reading is 614.0.

**When** the four bills are issued, Sep 16, Oct 16, Nov 16 and Dec 16; at Nov 15 the third estimate raises the cap's exception, and the supervisor resolves it by an override.

**Then**

| Bill | Estimate (actual months only, expected) | Bill | If estimated months fed the average | Bill |
|---|---|---|---|---|
| Sep 16 | 2.3 Mcf | $35.59 | 2.3 Mcf | $35.59 |
| Oct 16 | 2.3 Mcf | $35.87 | (2.1 + 3.0 + 2.3) ÷ 3 = 2.4667, so 2.5 Mcf | $37.71 |
| Nov 16 | 2.3 Mcf | $35.87 | (3.0 + 2.3 + 2.5) ÷ 3 = 2.6 Mcf | $38.62 |
| Dec 16, actual 614.0 | 614.0 − 606.9 = 7.1 Mcf | $81.07 | 614.0 − 607.4 = 6.6 Mcf | $76.40 |

- Each bill is $14.75 plus the gas at $3.41, $5.35 and the month's figure. September's: $14.75 + $7.84 + $12.31 + $0.69. December's catch-up: $14.75 + $24.21 + $37.99 + $4.12.
- The Dec 15 reading passes the high-usage check: 14.0 Mcf since the Aug 15 actual, 3.5 a month, against last year's 14.3 over the same four months.
- Either way, 14.0 Mcf is billed in all: the meter's 614.0 − 600.0. The two methods differ in which months the gas is billed in, and so at which figure ($188.40 in all against $188.32).
- Each estimated bill is marked, with the method and the months it averaged.
- **Settled by rule (2026-11-26):** which months an average reads is part of the utility's stated method (Kyle 10-15, R-11), stated at onboarding. Actual months only is this stream's proposal for the platform default, because feeding estimates into estimates carries one guess into the next.

---

### SCN-0160 — An actual reading dated before an estimate already billed

*Status:* draft (2026-11-26). **Built:** the run of estimates counts estimates dated after the latest validated actual, so a back-dated actual doesn't end it (AC-21); a review can be recorded on a reading, and a reading with an open review can't be approved (AC-20). **Not built:** raising the review, which is the core's (no rule in the built list names a back-dated actual, so it is recorded as "other"); the catch-up method (CI-114).
*Rule:* an actual reading that arrives after an estimate was billed, but is dated before it, is kept in the meter's history and reviewed before it is approved. It does not reopen the billed estimate, and it does not end the run of estimates. The next actual reading catches up all the gas from the last billed reading, the estimate (catch-up, the platform default). Sources: AC-20, AC-21; SCN-0141; SCN-0142.

**Given** Bluebonnet; BB-26 (R-R, outside the city; no tax). The Oct 15 actual reading is 500.0, and BB-26's three-month average is 4.0 Mcf. In November and December last year BB-26 used 6.1 and 6.5 Mcf. The Sun Nov 15 read fails (a locked gate). The estimated reading of 504.0 is billed on Mon Nov 16 at November's $0.42: **$51.47**, marked "Estimated". On Fri Nov 20 a service technician's reading, taken on a leak call on Fri Nov 13, is entered: 506.2.

**When** (a) the Nov 13 reading is entered; (b) the Dec 15 actual is 512.0, and the December bill is issued Wed Dec 16; (b′) instead, the Dec 15 read fails too.

**Then**
- **(a)** The core raises a review on the Nov 13 reading: an actual dated before an estimate already billed. The meter's history now steps back, 506.2 on Nov 13 and then 504.0 on Nov 15; that is not a rollover (SCN-0143), and no review can be raised on the billed estimate. The reading shows that November's estimate was low by at least 2.2 Mcf; its 6.2 Mcf in 29 days passes the high-usage check against last year's 6.1. The reviewer resolves the review by an override, "billed estimate stands; catch up at the next actual", and the reading is then validated. The November bill is not rebilled.
- **(b)** The December bill catches up from the estimated reading: 512.0 − 504.0 = 8.0 Mcf at December's $0.58: $14.75, distribution $27.28, commodity $42.80, gas cost $4.64: **$89.47**. The read passes the high-usage check: 12.0 Mcf since the Oct 15 actual, 6.0 a month, against last year's 6.1 and 6.5. The Dec 15 actual ends the run of estimates.
- **(b′)** The December estimate is the second in a row, though a real reading from Nov 13 is on file: that reading is dated before the Nov 15 estimate, so it doesn't end the run. The estimate is the three-month average, 4.0 Mcf (the Nov 13 reading ended no billed month, so it doesn't feed the average, SCN-0159), from the billed 504.0: an estimated reading of 508.0, and a bill of $14.75 + $13.64 + $21.40 + $2.32 = **$52.11**.
- **Settled by rule (2026-11-26):** the review and the run as built; catch-up is the platform default where the utility states no method (SCN-0141).

---

### SCN-0161 — Gulf Plains: a new customer with no "same month last year"

*Status:* draft (2026-11-26). **Built:** the estimate methods, a fixed list; the part-month customer charge setting, default a share by days. **Not built:** an estimate set by a supervisor, with its basis (as SCN-0150); a premise's reading history across meter changes (a net-new item in GBM's list from Kyle's 08-18 rulings); whether "same month last year" reads the customer's history or the address's.
*Rule:* Gulf Plains' stated method reads the readings taken at the address, across meters, so a new customer in an existing house is estimated from the house's own use (**invented**: its setting, `cast.md` §6). Where there is no history at the address, the method can't run, and a supervisor sets the estimate with its basis, as at Bluebonnet (SCN-0150). This is this stream's reading, by analogy with the Texas rule for gas used but not metered, which looks first to the same customer at the same location, then to "consumption under similar conditions at the same location or of other similarly situated customers". Sources: 16 TAC §7.45(7)(B)(v)(II) (the analogy); Kyle 08-18, D-3, and Kyle 10-15, R-10 (a reading's history stays with the meter and the address); SCN-0150; `cast.md` §6.

**Given** Gulf Plains (live since Jan 15, 2026); its rates, $15.00 a month, $4.10 per Mcf, and $3.40 gas cost; the part-month customer charge, a share by days (`cast.md` §6). (a) GP-10 moves into a newly built house on Wed Feb 10, 2027, with a new meter set at 0.0. The Mar 1 actual reading is 3.8. (b) GP-11 moves into an existing house on Wed Feb 10, 2027, at a reading of 2,210.0. The Mar 1 actual reading is 2,214.4. Its earlier occupant used 8.4 Mcf there in March 2026. For both, the Apr 1 read fails: a locked construction gate across the road.

**When** the March and April bills are issued, Fri Mar 5 and Mon Apr 5.

**Then**
- **(a)** GP-10's first bill (19 of February's 28 days): customer charge 15.00 × 19 ÷ 28 = 10.1786, so $10.18; delivery 3.8 × $4.10 = $15.58; gas cost 3.8 × $3.40 = $12.92: **$38.68**. In April there is no March 2026 at this address, so the method can't run, and the estimate is held for a supervisor. The supervisor sets 6.2 Mcf, GP-10's own 0.2 Mcf a day for March's 31 days, and records the basis. The Apr 5 bill, marked "Estimated": $15.00 + $25.42 + $21.08 = **$61.50**.
- **(b)** GP-11's first bill: $10.18, delivery 4.4 × $4.10 = $18.04, gas cost 4.4 × $3.40 = $14.96: **$43.18**. Its April estimate is the house's March 2026, 8.4 Mcf: $15.00 + $34.44 + $28.56 = **$78.00**, marked "Estimated", with the basis "same month last year at this address". The bill doesn't show the earlier occupant's name or account. Had Gulf Plains stated that only a customer's own history counts, GP-11's estimate would be held for a supervisor, as in (a).
- The construction gate is a reason beyond the utility's control under the engineering proposal (SCN-0142 (e)).
- **Settled by rule (2026-11-26):** which history the method reads is part of the utility's stated method, stated at onboarding. The address's history is this stream's proposal for the platform default, following Kyle's rulings that keep a reading's history with the address.

---

### SCN-0162 — A final bill corrected in a later month, after the deposit was applied

*Status:* draft (2026-11-26). **Built:** voiding and rebilling; a final bill's deposit application and refund are entries never edited. **Not built:** the gas cost figure by billing month (as SCN-0133); the due date of a hidden undercharge on a corrected final bill (one due date per bill today, as SCN-0033); collections.
*Rule:* a final bill corrected later uses its own billing month's figure (SCN-0133). The void and the correction leave one net balance; the deposit's application and its refund stay as they happened. A credit left is paid out as a deposit refund, since no account remains to hold it. An undercharge the utility's error hid is owed on the corrected final bill with a new due date from the correction, and takes a penalty only if unpaid after it. The corrected reading is also the next occupant's starting reading. Sources: SCN-0133; Kyle 11-03, answer 17, and SCN-0029 (the deposit's entries are not edited; the credit is a deposit refund); `cash.md` SCN-0089 (money freed by a correction); SCN-0033 (settled by rule, 2026-11-25: a corrected final bill's hidden extra takes a new due date from the correction, Kyle 11-03, answer 10; a penalty only after it, Kyle 11-05, answers 1 and 2); the six-month default for a silent city (Kyle 11-05, answers 10 – 12; SCN-0019).

**Given** Pecan Flat; PF-08 (residential; deposit $100; its meter reads in Mcf to a tenth). Its Nov 15 reading is 2,038.0, and its November bill is paid. PF-08 moves out on Mon Nov 30. The final bill is issued that day at November's $6.10, due Tue Dec 1. The deposit pays the final bill, and the rest is refunded. On Wed Dec 9 a photo review finds the final reading keyed wrong. December's figure is $6.85. A new tenant took service from Dec 1 at the keyed reading.
- (a) Keyed 2,046.0 (8.0 Mcf); the photo shows 2,040.6 (2.6 Mcf). The final bill was $72.00 + $48.80 = $120.80. The deposit paid $100.00, and PF-08 paid the other $20.80 at the counter on Tue Dec 1.
- (b) Instead, keyed 2,040.6; the photo shows 2,046.0. The final bill was $23.40 + $15.86 = $39.26. The deposit paid it, and $60.74 was refunded on Wed Dec 2.

**When** the final bill is voided and corrected on Dec 9.

**Then**
- A replacement reading, reason "typo correction", replaces the keyed final reading. Both PF-08's corrected bill and the new tenant's first bill use it. Catching up on the next read isn't offered, because the next read belongs to another customer.
- Both corrections name November as their billing month and use $6.10. At December's $6.85 the corrected bill in (a) would be $41.21.
- **(a)** The corrected final bill: 2.6 × $9.00 = $23.40, gas cost 2.6 × $6.10 = $15.86: **$39.26**. The void (−$120.80) and the correction (+$39.26) leave PF-08 a credit of **$81.54**, refunded by check to its forwarding address as a deposit refund. The deposit's $100.00 application and the $20.80 payment stay as they happened. Recording the refund as $60.74 of deposit and $20.80 of payment (the freed deposit money pays the correction first) is this stream's reading: Kyle's answer 17 covers a final bill paid wholly from the deposit.
- **(b)** The corrected final bill is **$120.80**. The void (−$39.26) and the correction leave PF-08 owing **$81.54**, an undercharge the city's keying hid, within Pecan Flat's six-month default for an undercharge (cause "keying error"). There is no next bill, so it takes a new due date from the correction: Pecan Flat's due day, Fri Jan 1, 2027, the first at least its ordinary gap after Dec 9 (the tariff doesn't move a holiday due date, as SCN-0131). If it is unpaid, Pecan Flat's 10% posts on Sat Jan 2: **$8.15**. A cut-off has no meaning here, since the account is closed. What follows, collections, is not built or ruled.
- **Settled by rule (2026-11-26):** the due date and the penalty in (b) follow SCN-0033's rule for a corrected final bill, with Pecan Flat's fixed due day as the new due date.
