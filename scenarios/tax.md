# Tax by location

Which taxes a bill carries, decided by where the gas is delivered, who the customer is and what each line is. Invariants: CI-045 (each tax on its own base, in its order), CI-046 (exemptions per service type, and the $0.00 line), the tax half of CI-001 and CI-004 (tax rules and the places a premise is in, dated and readable as known at a past instant), CI-044 (the liability by jurisdiction). Schema: the rates stream's v5.4.2-30 (mirrored 2026-11-22: the utility's tax rows keyed to places, required taxability, exemptions per service, places as known at an instant; AC-47). Not built: the bill line that names its tax row and place, the $0.00 line keeping its base, the liability by jurisdiction and period (the money stream's; -30 limit L5); the cities and districts as places with their published rates (-32). Franchise fees wait on -31.

**Common to every scenario here.**
- The tax rows are the utility's own: each says which place levies it, its rate in percent, its order in the stack, which other taxes (if any) it is charged on top of, its source and citation, and whether it reaches residential gas (Kyle 10-14, answers 1, 2; Ryan 2026-09-30: a value the utility answers for stays its own). The Comptroller's published rate is a reference: it never bills, and a difference is reported (SCN-0109).
- Bluebonnet's rows (`cast.md` §2, "Tax rows"): the state 6.25%, Bluebonnet County 0.5%, the city 1%, and from Jan 1, 2027 the Bluebonnet Crime Control District 0.25%. Each is on the lines flagged taxable, which at Bluebonnet is every gas line, and never on a tax (no tax on tax in Texas unless a place declares it).
- Residential gas in Texas pays only the city's tax, where the city taxes it, and the fire-control or crime-control district's, where such a district in that city does (Tax Code §151.317, §321.105, §321.201(a), §321.1055; 34 TAC §3.334(k)(8), (l)(1)). Whether gas is residential follows the rate class and the premise's use, and is not a stored exemption (Kyle R-13).
- Figures are the October 2026 billing month's (`billing-pipeline-and-charge-composition.md` SCN-0001: commodity $5.35, gas cost adjustment $0.42 per Mcf), used in later months too **for comparison (invented)**, so a difference between two bills is the tax alone.
- A city system collects the state's sales tax on taxable gas like any seller. This is the stream's reading of Tax Code ch. 151 (a city-owned seller has no exemption from collecting it); a tax advisor confirms before go-live.

---

### SCN-0104 — A business inside the city: state, county and city tax, each on its own base

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* a taxable charge at a non-residential premise carries every tax of every place the premise is in on the tax axis, each computed on the taxable lines and never on another tax, each rounded on its own line; each tax line names the row and place it came from. A late penalty that is a forfeited prompt-payment discount is taxed like the gas. Sources: Kyle 10-14, answers 1, 2, 5; Kyle 11-05, answers 3a, 3b; Tax Code §151.051 (the state rate), §321.203(f) (the sale is made where the gas is delivered); K-06 rounding.

**Given**
- **BB-10 (invented)**, a bakery inside the city, schedule SC-U ($12.80 a month, $2.96 per Mcf). The premise is in the State of Texas, Bluebonnet County and the City of Bluebonnet on the tax axis.
- October 2026 bill, period Sep 15 – Oct 14, 20.0 Mcf, issued Thu Oct 15, due Fri Oct 30.

**When** (a) the bill is issued; (b) it is unpaid when the due date passes, and the penalty posts.

**Then**
- **(a)**

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | | $12.80 |
  | Distribution | 20.0 Mcf × $2.96 | $59.20 |
  | Commodity charge | 20.0 Mcf × $5.35 | $107.00 |
  | Gas cost adjustment | 20.0 Mcf × $0.42 | $8.40 |
  | State sales tax | 6.25% × $187.40 = 11.7125 | $11.71 |
  | City sales tax | 1% × $187.40 = 1.8740 | $1.87 |
  | County sales tax | 0.5% × $187.40 = 0.9370 | $0.94 |
  | **Total** | | **$201.92** |

  Each tax line records the four lines in its base, and names its tax row and its place. Tax computed once on the sum of the three rates (7.75% × $187.40 = 14.5235 → $14.52) would differ from the sum of the lines ($14.52 here, but not in general) and could not be traced to a place; a test asserts three lines.
- **(b)** The penalty is 10% of the tariff-priced lines: 10% × $187.40 = **$18.74** (the current bill only, charged once: `cast.md` §2). As a forfeited discount it is taxed like the gas: state 6.25% × $18.74 = 1.1713 → $1.17; city 1% → $0.19; county 0.5% × $18.74 = 0.0937 → $0.09: **$20.19** in all.
- **Open (Kyle):** a forfeited discount on a commercial bill carries the state and county tax too, not only the city's (his answer 3b named city sales tax because the example was residential). A tax advisor confirms before a gross/net city goes live.

---

### SCN-0105 — A home inside the city pays the city's tax only, and later a crime-control district's

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* a tax row that does not reach residential gas adds no line to a residential bill, not a $0.00 line; only a city that taxes residential gas, and a fire-control or crime-control district in it that has chosen to, do. Sources: Tax Code §151.317, §321.105, §321.201(a), §321.1055; 34 TAC §3.334(l)(1); Kyle 11-03, answer 4; Kyle R-13.

**Given**
- BB-01, a homeowner inside the city, schedule R-U; the reference bill's lines (6.0 Mcf): $65.18 (`cancel-rebill.md`).
- The City of Bluebonnet taxes residential gas (`cast.md` §2: it kept the tax, **invented**). The Bluebonnet Crime Control District (**invented**), citywide, levies 0.25% from Jan 1, 2027 and has chosen to tax residential gas; Bluebonnet received its order and map (§321.1055(c)).

**When** (a) the November 2026 bill is issued (Mon Nov 16); (b) the February 2027 bill (period Jan 15 – Feb 14) is issued; (c) as (b), for BB-10 (SCN-0104's bakery, 20.0 Mcf).

**Then**

| Line | (a) BB-01, Nov 2026 | (b) BB-01, Feb 2027 | (c) BB-10, Feb 2027 |
|---|---|---|---|
| Tariff-priced lines | $65.18 | $65.18 | $187.40 |
| State sales tax | none | none | 6.25% → $11.71 |
| City sales tax | 1% → $0.65 | 1% → $0.65 | 1% → $1.87 |
| County sales tax | none | none | 0.5% → $0.94 |
| District sales tax | none (not yet in force) | 0.25% × $65.18 = 0.1630 → $0.16 | 0.25% × $187.40 = 0.4685 → $0.47 |
| **Total** | **$65.83** | **$65.99** | **$202.39** |

- BB-01 is residential because its schedule is residential and its premise is a home (Kyle R-13). Neither the state nor the county row adds a line; a $0.00 line is for an exempt customer (SCN-0107), not for a tax that never reached the bill.
- The local rates add up to 1.75%, inside the 2% local limit (§321.102(e)-(h)); the limit is applied by the Comptroller in the rate it publishes, and the utility's rows follow it (SCN-0109).
- **Open (rates):** a district may tax residential gas only while its city does (§321.1055(d)). Nothing links the district's row to the city's: if Bluebonnet stopped taxing residential gas, the district's row would go on reaching it until someone closed it. Whether the two should be checked together, or the gaps report should flag it, is the rates stream's to weigh.

---

### SCN-0106 — Outside the city: a home pays no tax; a business pays the state and the county

*Status:* draft (2026-11-24), not yet sent to Kyle. **Corrects SCN-0055 (c)**, which showed no tax on a large commercial bill outside the city.
*Rule:* outside the city limits no city tax applies, but the state's and the county's taxes still apply to non-residential gas. Sources: Kyle 11-03, answer 4 (city tax inside the city only); Tax Code §151.051, §151.317; 34 TAC §3.334(k)(8).

**Given** SCN-0055's bills: (a) BB-02, a renter outside the city, schedule R-R, 6.0 Mcf; (b) BB-08, large commercial outside the city, schedule LC-R, 40.0 Mcf at a pressure factor of 1.0400. Both premises are in Bluebonnet County and outside every city on the tax axis.

**When** the October 2026 bills are issued.

**Then**

| Line | (a) BB-02 | (b) BB-08 |
|---|---|---|
| Tariff-priced lines | $69.83 | $419.03 |
| State sales tax | none: residential | 6.25% × $419.03 = 26.1894 → $26.19 |
| County sales tax | none: residential | 0.5% × $419.03 = 2.0952 → $2.10 |
| City sales tax | none: outside the city | none: outside the city |
| **Total** | **$69.83** | **$447.32** |

- SCN-0055 (c)'s total of $419.03 was the tariff-priced lines only; the bill is $447.32.

---

### SCN-0107 — An exempt customer: a $0.00 line per tax, keeping its base; only for the service the certificate names

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* a customer exempt for a service pays no tax on that service's lines, and each tax that would have applied shows a $0.00 line that keeps the base it would have been charged on and names the exemption. An exemption counts only once it is verified, only for the services it names, and only over its dates. An exemption that names no service is refused. Sources: Kyle 10-14, answer 5; Kyle R-12 (an exemption is born pending and counts once verified); CI-046; -30 (exemptions name their services).

**Given**
- BB-03, the county courthouse, inside the city (**invented**), schedule G ($72.10 a month, $1.67 per Mcf). October 2026 bill, 50.0 Mcf.
- Bluebonnet County gave Bluebonnet an exemption certificate as a government buyer (**invented**: a certificate under the Comptroller's form 01-339), covering gas, from Jan 1, 2026, verified by a clerk on Jan 9, 2026.

**When** the October bill is issued, with (a) the certificate as given; (b) the certificate listing water only; (c) the certificate received but not yet verified; (d) the clerk entering an exemption that names no service.

**Then**
- **(a)**

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | | $72.10 |
  | Distribution | 50.0 Mcf × $1.67 | $83.50 |
  | Commodity charge | 50.0 Mcf × $5.35 | $267.50 |
  | Gas cost adjustment | 50.0 Mcf × $0.42 | $21.00 |
  | State sales tax | exempt: base $444.10 | $0.00 |
  | City sales tax | exempt: base $444.10 | $0.00 |
  | County sales tax | exempt: base $444.10 | $0.00 |
  | **Total** | | **$444.10** |

  Each $0.00 line names the certificate. That is what tells an auditor this was an exempt sale and not a place that levies nothing.
- **(b)** and **(c)** The bill is taxed in full: state $27.76 (6.25% × $444.10 = 27.7563), city $4.44, county $2.22 (0.5% × $444.10 = 2.2205): **$478.52**.
- **(d)** Refused when entered: an exemption names at least one service ("every service" is the list written out).
- A line with no service type is refused, not read as covered by any exemption.
- **Open (Kyle):** in (c), the certificate is verified on Nov 3, dated from Jan 1. Are the bills already issued at full tax corrected (the tax refunded to the county), or does the exemption start with the next bill? In Texas a buyer can also claim a refund from the Comptroller, so either may be lawful; which does the utility do?

---

### SCN-0108 — Annexation: the city's rates from the ordinance's date, the city's tax from the next quarter

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* one annexation gives a premise two dates: on the boundary date it is inside the city for its rate schedule; on the sales-tax date (the first day of the quarter after the Comptroller receives the ordinance and map) it is inside the city for the city's tax. Both are recorded with their evidence, and neither is derived from the other. Sources: Tax Code §321.102(c); `application/places-sources/texas.md` §3 ("store both; never derive one from the other"); Kyle R-26 (the regulatory and tax axes stay separate).

**Given**
- **BB-11 (invented)**, a homeowner just outside the city, schedule R-R ($14.75, $3.41).
- Bluebonnet annexes BB-11's street by an ordinance effective Mon Feb 15, 2027; the city secretary sends it with its map, and the Comptroller receives it on Wed Mar 3, 2027 (all **invented**). The city tax applies there from Thu Apr 1, 2027. The crime-control district's boundary is citywide and is taken to follow the city's tax date (**invented**; see Open).
- Bluebonnet's schedules key on the city limits (urban inside, rural outside), so BB-11 moves to R-U on Feb 15. The boundary date falls on a period's first day (**invented**) to keep the rate split out of this scenario.

**When** the bills are issued: (a) February (Jan 15 – Feb 14); (b) March (Feb 15 – Mar 14); (c) April (Mar 15 – Apr 14); (d) May (Apr 15 – May 14); (e) as (b), but the clerk recorded the tax-axis membership from Feb 15 too.

**Then**

| Bill | Schedule | Tariff-priced lines | City tax | District tax | Total |
|---|---|---|---|---|---|
| (a) February | R-R | $69.83 | none: outside | none | **$69.83** |
| (b) March | R-U | $65.18 | none: not yet in force here | none | **$65.18** |
| (c) April | R-U | $65.18 | Open | Open | — |
| (d) May | R-U | $65.18 | 1% → $0.65 | 0.25% → $0.16 | **$65.99** |

- The premise carries two memberships in the city: on the regulatory axis from Feb 15 (evidence: the ordinance), on the tax axis from Apr 1 (evidence: the Comptroller's quarter, with the date it received the ordinance). The March bill is the case that tells them apart: city rates, no city tax.
- **(e)** The March bill charged $0.65 city and $0.16 district tax that were not yet in force. When found, the tax-axis membership is corrected (voided and replaced, dated Apr 1) and the March bill corrected: **$0.81 refunded**. A refund of tax wrongly charged has no backbilling limit (Kyle 11-04: a silent city's refunds are unlimited). **To check before sending:** Tax Code §321.3025 covers tax collected in added territory before the effective date; its text is not in our sources.
- **Open (Kyle):** the April bill's period runs Mar 15 – Apr 14 and the tax starts Apr 1. Is the whole bill taxed (it closes after Apr 1: $0.65 and $0.16, total $65.99), none of it (the first bill wholly after Apr 1 is May's: $65.18), or the taxable lines split by days (17 of 31 days untaxed)? The Comptroller's rule (34 TAC §3.334, 2024 text) does not say; it ties local tax to where the gas is delivered. The same question arises for every rate change on a quarter's first day (SCN-0109), so the answer is one platform rule, or one each utility states. Recommendation for Kyle to react to: the utility states its method when it enters a tax change, as for rate changes (Kyle 11-03, answer 1).
- **Open (Kyle):** whether a citywide crime-control district grows with the city on the same tax date, or only when the district itself sends a new boundary (§321.1055(c) has the district send its boundaries to the utility).
- A limited-purpose annexation would move neither membership for tax: a city may not tax in a limited-purpose area (Local Gov't Code §43.130(c)). An extraterritorial area counts as outside for city taxes (§42.902).

---

### SCN-0109 — A published rate change: billed only once the utility approves it; a gap reported until then

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* a new published rate never bills by itself. The utility's operator approves it by recording a new row from the quarter's first day, recorded with who approved it; the old row is closed, not edited. Until then the bill uses the utility's own row and a report lists every place where the published rate differs from it, or where a place a premise is in publishes a rate and the utility has no row. A bill uses the rows as known when its run reads them. Sources: Kyle 10-14, answer 1 ("no rate change goes live without operator approval"); Ryan 2026-09-30; -30 (the gaps report; rows never edited, closed once); AC-47 (a run's instant).

**Given**
- The Comptroller's file for the quarter beginning Fri Oct 1, 2027 publishes the City of Bluebonnet's rate as 1.25% (**invented**; with the county's 0.5% and the district's 0.25%, the local total is 2%). The platform loads it as the city's reference rate.
- Bills for the period Oct 15 – Nov 14 are issued Mon Nov 15, 2027: BB-01 (residential, $65.18) and BB-10 (the bakery, $187.40).

**When** (a) nobody approves the change before Nov 15; (b) an operator approves it on Tue Oct 5; (c) an operator approves it on Sat Nov 20, after the bills; (d) the clerk tries to approve it by changing the rate on the existing row.

**Then**

| | (a) and (c) as issued | (b) |
|---|---|---|
| BB-01 city tax | 1% → $0.65 | 1.25% × $65.18 = 0.8148 → $0.81 |
| BB-01 total (with the district's $0.16) | **$65.99** | **$66.15** |
| BB-10 city tax | 1% → $1.87 | 1.25% × $187.40 = 2.3425 → $2.34 |
| BB-10 total (state $11.71, county $0.94, district $0.47) | **$202.39** | **$202.86** |

- **(a)** From Oct 1 the gaps report lists the City of Bluebonnet: Bluebonnet's row 1%, published 1.25%, with the published figure's source. The report shows it; nothing bills at 1.25%.
- **(b)** The 1% row ends Sep 30; a 1.25% row runs from Oct 1, recorded Oct 5 with the approving operator. The gap is gone.
- **(c)** The Nov 15 bills read the rows as known at their run's instant, so they charge 1%; replaying them later gives the same answer, because each bill records the rows it used. Each is $0.16 (BB-01) and $0.47 (BB-10) short of the approved rate.
- **(d)** Refused: a tax row is never edited. A change is a close and a new row.
- Had the Comptroller's file named a county Bluebonnet's premises sit in and Bluebonnet had no county row, the report lists that county with no row: a published tax nobody approved.
- **Open (Kyle):** in (c), the utility owes the tax at 1.25% for October deliveries whatever it billed (the stream's reading; a tax advisor confirms). Does it correct the issued bills, put the difference on the next bill, or absorb it? A test needs one answer.

---

### SCN-0110 — A premise placed in the wrong jurisdiction: what the old bills used, and the correction

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* each bill records the tax rows and places it used, so it can always be shown what it did. When a premise's place on the tax axis turns out wrong, the place is corrected (voided and replaced, with evidence), and the bills it affected are corrected from the true facts; tax wrongly charged is refunded. Sources: CI-001, CI-004; -30 (places as known at an instant; known limit L7: a bill records what it used); AC-47; Kyle 11-04 (refunds unlimited at a silent city).

**Given**
- **BB-12 (invented)**, a renter outside the city, schedule R-R (correctly, on the regulatory axis), in Bluebonnet's extraterritorial area. When it was set up on Jan 1, 2026, an address lookup placed it inside the City of Bluebonnet on the tax axis.
- Its October and November 2026 bills (6.0 Mcf each): $69.83 of tariff-priced lines, city tax 1% × $69.83 = 0.6983 → $0.70: **$70.53** each.
- On Thu Dec 3, 2026 the city's boundary map shows the premise outside; the clerk voids the tax-axis membership and records the premise as outside, citing the map.

**When** (a) the October bill is shown on Dec 10; (b) the bills are corrected; (c) the December bill is issued Dec 15.

**Then**
- **(a)** It shows what it charged and why: the city's row and the city membership it used. Read as known at its own run's instant, the premise is still inside; read now, it is outside. Both answers are true of their instant; the bill's own record is what it used.
- **(b)** Each bill is corrected without city tax: $69.83, **$0.70 refunded** on each, **$1.40** in all.
- **(c)** No city tax: **$69.83**.
- A premise outside on the regulatory axis but inside on the tax axis is not by itself an error: after an annexation the two dates differ (SCN-0108), and after a disannexation they differ the other way. Nothing refuses it; nothing reports it either.

---

### SCN-0111 — A city that levies no local tax: residential pays nothing, a café pays the state

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* with no city or county tax, a residential bill carries no tax at all and a non-residential one carries the state's only. With one rate class for everyone, whether a premise is residential comes from its use. Sources: `cast.md` §1 (Pecan Flat: no local sales tax adopted); Tax Code §151.317(c) (residential use; a tenant on a term over 29 days), (e) (predominant use per meter per billing period); Kyle R-13.

**Given**
- Pecan Flat (`cast.md` §1): one rate, $9.00 per Mcf plus gas cost ($6.10 per Mcf in this month, **invented**, as in SCN-0053 and SCN-0084); a $20.00 minimum bill. Its county levies no sales tax (**invented**). Pecan Flat flags every gas line taxable (**invented**).
- PF-01, a homeowner, 5.0 Mcf. **PF-03 (invented)**, a café, 30.0 Mcf.

**When** the bills are issued for (a) PF-01; (b) PF-03; (c) **PF-04 (invented)**, a house rented by the week to visitors, 5.0 Mcf; (d) **PF-05 (invented)**, a home with a hair salon in the garage on the same meter.

**Then**

| Line | (a) PF-01 | (b) PF-03 |
|---|---|---|
| Gas, $9.00 per Mcf | 5.0 × $9.00 = $45.00 | 30.0 × $9.00 = $270.00 |
| Gas cost, $6.10 per Mcf | 5.0 × $6.10 = $30.50 | 30.0 × $6.10 = $183.00 |
| State sales tax | none: residential | 6.25% × $453.00 = 28.3125 → $28.31 |
| **Total** | **$75.50** | **$481.31** |

- **(c)** Not residential use: a stay under 30 days is not a residence (§151.317(c)(2)). Taxed as (b) would be: 6.25% × $75.50 = 4.7188 → **$4.72**, total **$80.22**.
- **(d)** **Open (Kyle):** one meter used for both is wholly taxable or wholly exempt by its predominant use in each billing period (§151.317(e)). Kyle deferred predominant use to a table of its own (R-13). Who decides the use each period: the utility's recorded use of the premise (changed when the customer reports it), or a figure per bill?
- PF-03's use is recorded on the premise with its dates, as every input the tax reads is.

---

### SCN-0112 — Another state: a tax charged on top of another tax, in the stated order

*Status:* draft (2026-11-24), not yet sent to Kyle. All Fremont law here is **invented**.
*Rule:* a tax is charged on another tax only where its row names that tax; then the taxes are computed in their stated order, each on its base plus the taxes it names. A row may not name itself, nor a kind of tax the platform does not know. Sources: Kyle 10-14, answer 2 (the stack comes from law and the tariff); `tax-design.md` 2.1 (tax on tax declared, empty by default); -30 (a row is never computed on itself; only known kinds).

**Given**
- Prairie Line Gas Company (`cast.md` §4); **PL-03 (invented)**, a homeowner in the City of Lakeview, Fremont (invented). Rates **invented**: $15.00 a month and $6.00 per Mcf; 8.0 Mcf.
- Fremont taxes residential gas. Lakeview levies a 3% utility users' tax, first in the stack; Fremont's 5% sales tax is second and is charged on the bill **including** the utility users' tax (all **invented**). "Utility users' tax" is a kind of tax the platform adds for Fremont, not a code change.

**When** (a) the bill is issued; (b) Prairie Line enters the sales-tax row without naming the utility users' tax; (c) a clerk enters a row that is charged on itself; (d) a row names a kind of tax the platform has not added.

**Then**
- **(a)**

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | | $15.00 |
  | Usage | 8.0 Mcf × $6.00 | $48.00 |
  | Utility users' tax (1st) | 3% × $63.00 | $1.89 |
  | Sales tax (2nd) | 5% × ($63.00 + $1.89) = 3.2445 | $3.24 |
  | **Total** | | **$68.13** |

  The sales-tax line's base records the two charges and the utility users' tax line.
- **(b)** The sales tax is 5% × $63.00 = $3.15: **$68.04**. Both are possible rows; only the law says which is right, so the platform takes the row as entered and the bill shows its base.
- **(c)** Refused when entered. **(d)** Refused when entered.
- **Open (rates):** nothing checks that a tax charged on another sits later in the stack. A sales-tax row first in the stack and charged on a utility users' tax second would leave the core no order to compute in. Whether to refuse it when entered is the rates stream's to weigh.

---

### SCN-0113 — Entering a tax row: what is refused

*Status:* draft (2026-11-24), not yet sent to Kyle.
*Rule:* a tax row names a place of a kind that levies that tax, which exists in the platform's places over the whole of the row's dates; its rate has at most four decimals; its citation is not blank; it is the entering utility's own. A place is never closed from under a row. Sources: -30 (its rules, each a battery check); Kyle 10-14, answer 2 (source and citation required); K-06.

**Given** Bluebonnet's clerk enters tax rows (all **invented** except as cited).

**When** the clerk enters (a) the crime-control district's row in December 2026, before the platform has loaded the district as a place; (b) a city rate of 1.12345%; (c) a row with the citation "—"; (d) a row for Pecan Flat's city, signed in as Bluebonnet; (e) a county row that says it reaches residential gas; and (f) the platform later closes the City of Bluebonnet's place record while Bluebonnet's row is in force, with no successor.

**Then**
- **(a)** Refused: there is no such place yet. The district's places and published rates are a platform data load (-32, not built); until then no utility can bill a district's tax.
- **(b)** Refused: four decimals at most. **(c)** Refused: a citation has a letter or a digit. **(d)** Refused: a utility writes its own rows only.
- **(e)** Accepted. Counties, transit authorities and most districts may not tax residential gas (34 TAC §3.334(l)(1)(A)), so this row is wrong, but nothing refuses or reports it. Nor is a city's "reaches residential" compared with the place's published fact (whether the city kept the tax, Tax Code §321.105). **Open (rates):** refuse (e) when entered for a kind of place the law bars, and add the residential fact to the gaps report?
- **(f)** Refused when committed, unless a successor place with the same code covers the row's dates in the same transaction: the row is keyed by the place's code, so it carries over to the successor.

---

### SCN-0114 — The tax owed to each jurisdiction for a period: billed, collected and exempt

*Status:* draft (2026-11-24), not yet sent to Kyle. The liability record is the money stream's and is not built (-30 limit L5).
*Rule:* the platform holds the liability, not the remittance: per jurisdiction and accounting period, the tax billed and the tax collected, the exempt base beside them, and an optional filing reference. Payments to the state and cities stay in the utility's own books. Sources: Kyle 10-14, answer 4; CI-044; -23 (a payment is applied per line).

**Given** Bluebonnet's October 2026 bills from SCN-0104 (BB-10), SCN-0106 (b) (BB-08) and SCN-0107 (a) (BB-03, exempt); for this scenario these are the only taxed bills in the period (**invented**). BB-10 pays $100.00 on Tue Nov 3; the others pay in full in October.

**When** the October period's liability is read.

**Then**

| Jurisdiction | Tax billed | Exempt base | Tax collected |
|---|---|---|---|
| State of Texas | $11.71 + $26.19 = $37.90 | $444.10 | $26.19 + BB-10's share (Open) |
| City of Bluebonnet | $1.87 | $444.10 | BB-10's share (Open) |
| Bluebonnet County | $0.94 + $2.10 = $3.04 | $444.10 | $2.10 + BB-10's share (Open) |

- Each figure traces to the bill lines that make it up, and each line to its row and place. BB-03's $0.00 lines give the exempt base; a jurisdiction that levies nothing would show no line at all.
- **Open (Kyle):** BB-10's $100.00 pays part of a bill with three tax lines. Kyle's two-tier order (11-05, answer 16) orders bills and kinds of charge, not the lines within one bill. Does a partial payment pay the tax lines first, last, or in proportion (each tax collected in the share $100.00 is of $201.92)? The figure collected per jurisdiction depends on it.
- **Open (Kyle; a tax advisor):** does the utility report the tax when billed or when collected? The liability holds both either way; which one its return uses is the utility's to state, if Texas allows it the choice (not checked).
