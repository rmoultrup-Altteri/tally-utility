# Tax by location

Which taxes a bill carries, decided by where the gas is delivered, who the customer is and what each line is. Invariants: CI-045 (each tax on its own base, in its order), CI-046 (exemption certificates, valid for the period; the $0.00 line), CI-047 (a premise's tax places from the ground truth, dated, a correction recorded), the tax half of CI-001 and CI-004 (tax rules and a premise's places, dated and readable as known at a past instant). The liability by jurisdiction is Kyle's answer 4 of 10-14, not yet an invariant of its own (CI-044 is the franchise fee's, and waits on -31).

**Built:** the rates stream's v5.4.2-30 (mirrored 2026-11-22): the utility's tax rows keyed to places, required taxability, exemptions per service, places as known at an instant; AC-47 (the instant a billing run reads at). **Not built:** the bill line that names its tax row and place, the $0.00 line keeping its base, the liability by jurisdiction and period (the money stream's; -30 limit L5); the cities, transit authorities and districts as places with their published rates (-32); a premise's use recorded with dates, and which of the schedule and the use decides "residential" (rates; SCN-0111). Franchise fees wait on -31.

**Common to every scenario here.**
- The tax rows are the utility's own: each says which place levies it, its rate in percent, its position in the stack, which other taxes (if any) it is charged on top of, its source and citation, and whether it reaches residential gas (Kyle 10-14, answers 1, 2; Ryan 2026-09-30: a value the utility answers for stays its own). The Comptroller's published rate is a reference: it never bills, and a difference is reported (SCN-0109).
- A premise is in a place for tax only by its own recorded membership on the tax axis, with its dates and evidence. Being inside a city does not by itself put it in a citywide district: each membership is recorded (CI-047).
- Bluebonnet's rows and their stack positions are in `cast.md` §2 ("Tax rows"): 1 the state, 2 Bluebonnet County, 3 the city, 4 the crime-control district (from Jan 1, 2027), 5 the transit authority (east of Main Street only, until Sep 30, 2027; SCN-0115). Every local tax at a location counts toward Texas's 2% limit, a transit authority's included (Tax Code §321.101(f)): east of Main Street the local total is exactly 2.0% in 2027 until the transit authority ends, and 2.0% west of it once the city's rate rises in SCN-0109. Each is on the lines flagged taxable and never on another tax (no tax on tax in Texas unless a place declares it). Bills list tax lines in stack order.
- Residential gas in Texas pays only the city's tax, where the city may and does tax it, and a fire-control or crime-control district's in that city, where it has chosen to (Tax Code §151.317, §321.105, §321.201(a), §321.1055; 34 TAC §3.334(k)(8), (l)(1)). Whether gas is residential follows the rate class and the premise's use, and is not a stored exemption (Kyle R-13). A tax that does not reach residential gas adds no line to a residential bill (the stream's reading: a $0.00 line is for an exempt customer, SCN-0107).
- **The state rate is 6.25%**: "The sales tax rate is 6-1/4 percent of the sales price of the taxable item sold" (Tax Code §151.051(b); read 2026-11-24 from texas.public.law, marked verified May 26, 2025).
- A city system collects the state's sales tax on taxable gas like any seller. This is the stream's reading of Tax Code ch. 151; a tax advisor confirms before go-live.
- Figures are the reference November 2026 bill's (`cancel-rebill.md`: period Oct 15 – Nov 13, issued Mon Nov 16, due Tue Dec 1; commodity $5.35 and gas cost adjustment $0.42 per Mcf; the schedules' rates as in `cast.md`, none changed inside the period), used in later months too **for comparison (invented)**, so a difference between two bills is the tax alone.

---

### SCN-0104 — A business inside the city: state, county and city tax, each on its own base

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* a taxable charge at a non-residential premise carries the tax of every place the premise is in on the tax axis, each computed on the taxable lines and never on another tax, each rounded on its own line, in stack order; each tax line names the row and place it came from. A late penalty that is a forfeited prompt-payment discount is taxed like the gas. Sources: Kyle 10-14, answers 1, 2, 5; Kyle 11-05, answers 3a, 3b; Tax Code §321.203(f) (the sale is made where the gas is delivered); K-06 rounding.

**Given**
- **BB-10 (invented)**, a bakery inside the city, schedule SC-U ($12.80 a month, $2.96 per Mcf). Its premise is recorded on the tax axis in the State of Texas, Bluebonnet County and the City of Bluebonnet.
- The November 2026 bill, 20.0 Mcf.

**When** (a) the bill is issued; (b) it is unpaid on the due date, and the penalty posts on Wed Dec 2.

**Then**
- **(a)**

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | | $12.80 |
  | Distribution | 20.0 Mcf × $2.96 | $59.20 |
  | Commodity charge | 20.0 Mcf × $5.35 | $107.00 |
  | Gas cost adjustment | 20.0 Mcf × $0.42 | $8.40 |
  | State sales tax | 6.25% × $187.40 = 11.7125 | $11.71 |
  | County sales tax | 0.5% × $187.40 = 0.9370 | $0.94 |
  | City sales tax | 1% × $187.40 = 1.8740 | $1.87 |
  | **Total** | | **$201.92** |

  Each tax line records the four lines in its base, and names its tax row and its place. A test asserts the three lines, not only the total: one combined rate gives the same total here, but not always (SCN-0106 (b): 6.75% × $419.03 = $28.28, against $26.19 + $2.10 = $28.29).
- **(b)** The penalty is 10% of the tariff-priced lines: 10% × $187.40 = **$18.74** (the current bill only, charged once: `cast.md` §2). As a forfeited discount it is taxed like the gas (Kyle 11-05, answer 3b), so on a business it carries every tax the gas does: state 6.25% × $18.74 = 1.1713 → $1.17; county 0.5% × $18.74 = 0.0937 → $0.09; city 1% → $0.19: **$20.19** in all.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** Kyle ruled the penalty "taxed like the gas" (Kyle 11-05, answer 3b), and a business's gas carries state, county and city tax, so its penalty does too. His own condition stands: a tax advisor confirms before a gross/net city goes live.

---

### SCN-0105 — A home inside the city pays the city's tax only, and later a crime-control district's

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* a tax that does not reach residential gas adds nothing to a residential bill; only a city that may and does tax residential gas, and a fire-control or crime-control district in it that has chosen to, do. Sources: Tax Code §151.317, §321.105, §321.201(a), §321.1055; 34 TAC §3.334(l)(1); Kyle 11-03, answer 4; Kyle R-13.

**Given**
- BB-01, a homeowner inside the city, schedule R-U; the reference bill's lines (6.0 Mcf): $65.18.
- The City of Bluebonnet's sales tax predates Oct 1, 1979 and it kept the tax on residential gas (`cast.md` §2, **invented**). The Bluebonnet Crime Control District (**invented**), citywide, levies 0.25% from Jan 1, 2027 and has chosen to tax residential gas; Bluebonnet received its order and boundaries (§321.1055(c)).
- From Jan 1, 2027 BB-01's and BB-10's premises are recorded in the district on the tax axis, citing the district's notice (evidence: the tax authority's notice).

**When** (a) the November 2026 bill is issued; (b) the February 2027 bill (period Jan 15 – Feb 14) is issued; (c) as (b), for BB-10 (SCN-0104, 20.0 Mcf); (d) as (b), for **BB-15 (invented)**, a home inside the city whose district membership the clerk never recorded.

**Then**

| Line | (a) BB-01, Nov 2026 | (b) BB-01, Feb 2027 | (c) BB-10, Feb 2027 | (d) BB-15, Feb 2027 |
|---|---|---|---|---|
| Tariff-priced lines | $65.18 | $65.18 | $187.40 | $65.18 |
| State sales tax | none | none | 6.25% → $11.71 | none |
| County sales tax | none | none | 0.5% → $0.94 | none |
| City sales tax | 1% → $0.65 | 1% → $0.65 | 1% → $1.87 | 1% → $0.65 |
| District sales tax | none (not yet in force) | 0.25% × $65.18 = 0.1630 → $0.16 | 0.25% × $187.40 = 0.4685 → $0.47 | none recorded |
| **Total** | **$65.83** | **$65.99** | **$202.39** | **$65.83** (should be $65.99) |

- BB-01 is residential because its schedule is residential and its premise is a home (Kyle R-13).
- West of Main Street the local rates add up to 1.75% (east of it, 2.0% from Jan 1, 2027, SCN-0115), inside the 2% local limit; a local rate that would pass it "is automatically reduced" (§321.102(e)-(h)). The utility's rows carry the reduced rate; the gaps report would show a row that did not (SCN-0109).
- **(d)** BB-15 pays no district tax, and nothing reports it: the gaps report lists places a premise *is* recorded in. **Open (rates):** a check that every premise recorded in a city is also recorded in each citywide district of that city, or the report extended to list them.
- **Open (rates):** a district may tax residential gas only while its city does (§321.1055(d)). Nothing links the district's row to the city's; if Bluebonnet stopped taxing residential gas, the district's row would go on reaching it until someone closed it. Check the two together, or report it?

---

### SCN-0106 — Outside the city: a home pays no tax; a business pays the state and the county

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle. **Corrects SCN-0055 (c)**, which showed no tax on a large commercial bill outside the city.
*Rule:* outside the city limits no city tax applies, but the state's and the county's taxes still apply to non-residential gas. Sources: Kyle 11-03, answer 4 (city tax inside the city only); Tax Code §151.317; 34 TAC §3.334(k)(8).

**Given** SCN-0055's October 2026 bills: (a) BB-02, a renter outside the city, schedule R-R, 6.0 Mcf; (b) BB-08, large commercial outside the city, schedule LC-R, 40.0 Mcf at a pressure factor of 1.0400. Both premises are recorded on the tax axis in the state and Bluebonnet County, and in the city's extraterritorial area, which counts as outside for city tax (Local Gov't Code §42.902).

**When** the bills are issued.

**Then**

| Line | (a) BB-02 | (b) BB-08 |
|---|---|---|
| Tariff-priced lines | $69.83 | $419.03 |
| State sales tax | none: residential | 6.25% × $419.03 = 26.1894 → $26.19 |
| County sales tax | none: residential | 0.5% × $419.03 = 2.0952 → $2.10 |
| City sales tax | none: outside the city | none: outside the city |
| **Total** | **$69.83** | **$447.32** |

---

### SCN-0107 — An exempt customer: a $0.00 line per tax, keeping its base; only for the service and period the certificate covers

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* a customer exempt for a service pays no tax on that service's lines, and each tax that would have applied shows a $0.00 line that keeps the base it would have been charged on and names the certificate. A certificate counts only once verified, only for the services it names, and only for a period it is valid for; when it expires the customer is taxed again with no one changing a setting. An exemption that names no service is refused. Sources: Kyle 10-14, answer 5; Kyle R-12 (born pending, counts once verified); CI-046 (valid for the period; expiry reverts by itself; a backdated certificate goes to the operator); -30 (exemptions name their services).

**Given**
- BB-03, the county courthouse, inside the city, west of Main Street (`cast.md`), schedule G ($72.10 a month, $1.67 per Mcf). The November 2026 bill, 50.0 Mcf.
- Bluebonnet County gave Bluebonnet a government exemption certificate (**invented**), for gas, valid from Jan 1, 2026, verified by a clerk on Jan 9, 2026.

**When** the November bill is issued, with (a) the certificate as given; (b) the certificate listing water only; (c) the certificate received but not yet verified; (d) the clerk entering an exemption that names no service; (e) the certificate having expired Sep 30, 2026; (f) the certificate expiring Oct 31, 2026, inside the period.

**Then**
- **(a)**

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | | $72.10 |
  | Distribution | 50.0 Mcf × $1.67 | $83.50 |
  | Commodity charge | 50.0 Mcf × $5.35 | $267.50 |
  | Gas cost adjustment | 50.0 Mcf × $0.42 | $21.00 |
  | State sales tax | exempt: base $444.10 | $0.00 |
  | County sales tax | exempt: base $444.10 | $0.00 |
  | City sales tax | exempt: base $444.10 | $0.00 |
  | **Total** | | **$444.10** |

  Each $0.00 line names the certificate. That is what tells an exempt sale from a place that levies nothing.
- **(b)**, **(c)** and **(e)** The bill is taxed in full: state $27.76 (6.25% × $444.10 = 27.7563), county $2.22 (0.5% × $444.10 = 2.2205), city $4.44: **$478.52**. In (e) nobody changes a customer setting: the expired certificate simply does not cover the period.
- **(d)** Refused when entered: an exemption names at least one service ("every service" is the list written out). A line with no service type is refused, not read as covered by any exemption.
- **(c), continued.** The certificate is verified on Nov 20, valid from Jan 1. The bills already issued at full tax are not changed by themselves: the backdated certificate goes to an operator, who decides whether to credit the tax on past bills, and the decision and who made it are recorded (CI-046; the workflow is not built). A later rebill of one of those bills for any other reason reads the certificate as known then, and comes out exempt. The law gives the county two routes: it may ask the utility to refund tax paid in error, or claim a refund from the Comptroller (34 TAC §3.295(h)(1), citing §3.325). **Open (Kyle):** is there a default for the operator's choice, and how far back may the credit reach?
- **(f)** **Open (Kyle):** "valid for the period" does not say which date decides when a certificate ends inside a period: the period's end (taxed in full), its start (exempt in full), or a split of the base by days. The Comptroller's certificate rule (34 TAC §3.287, read 2026-11-24) has no rule by period: a seller accepts a certificate "at or before the time of the transaction" (d)(2)(A).

---

### SCN-0108 — Annexation: the city's rates from the ordinance's date, the city's tax from a later quarter

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* one annexation gives a premise two dates: on the boundary date it is inside the city for its rate schedule; for the city's tax it is inside from the first day of the quarter after the Comptroller receives the ordinance and map, or a quarter later if the Comptroller asks for more time within ten days. Both are recorded with their evidence, and the tax date is recorded, not computed. Sources: Tax Code §321.102(c), (d); `application/places-sources/texas.md` §3 ("store both; never derive one from the other"); Kyle R-26 (the regulatory and tax axes stay separate); CI-047.

**Given**
- **BB-11 (invented)**, a homeowner just outside the city, schedule R-R ($14.75, $3.41), 6.0 Mcf every month.
- Bluebonnet annexes BB-11's street by an ordinance effective Mon Feb 15, 2027; the Comptroller receives it with its map on Wed Mar 3, 2027 and asks for no more time (all **invented**). So the city tax applies there from Thu Apr 1, 2027.
- BB-11's premise is recorded inside the city on the regulatory axis from Feb 15 (evidence: the ordinance), and inside the city on the tax axis from Apr 1 (evidence: the tax authority's notice, with the date it received the ordinance). It is recorded in the crime-control district from Apr 1 too (**invented**; see the second Open).
- Bluebonnet's schedules key on the city limits, so BB-11 moves to R-U on Feb 15. The boundary date falls on a period's first day (**invented**) to keep the rate split out of this scenario.
- Bluebonnet bills the pipeline safety fee, $1.00, on its March bills, outside every tax base (`cast.md` §2; SCN-0054).

**When** the bills are issued: (a) February (Jan 15 – Feb 14); (b) March (Feb 15 – Mar 14); (c) April (Mar 15 – Apr 14); (d) May (Apr 15 – May 14); (e) as (b), but the clerk recorded the tax-axis memberships from Feb 15 too; (f) as (d), but the Comptroller asked for more time on Mar 10, so the tax date is Jul 1, and both tax-axis memberships (city and district) are recorded from Jul 1.

**Then**

| Bill | Schedule | Tariff-priced lines | Pipeline safety fee | City tax | District tax | Total |
|---|---|---|---|---|---|---|
| (a) February | R-R | $69.83 | — | none: outside | none | **$69.83** |
| (b) March | R-U | $65.18 | $1.00 | none: not yet in force here | none | **$66.18** |
| (c) April | R-U | $65.18 | — | Open | Open | — |
| (d) May | R-U | $65.18 | — | 1% → $0.65 | 0.25% → $0.16 | **$65.99** |
| (f) May | R-U | $65.18 | — | none: from Jul 1 | none | **$65.18** |

- The March bill is the case that tells the two dates apart: the city's rates, no city tax.
- **(e)** The March bill charged $0.65 city and $0.16 district tax not yet in force there (on $65.18; never on the fee). When found, the tax-axis memberships are voided and recorded again from Apr 1, citing the notice, and the March bill is corrected. The utility credits the overcharge when it finds it (settled below): **$0.81 is credited** to the account (refunded if the customer asks, as any credit). A refund of an overcharge goes back as far as the records show (Kyle 11-03, answer 8). Tax Code §321.3025 (read 2026-11-24): an amount a seller collects in added territory before the city's tax takes effect "is treated as if it were revenue from the taxes imposed by the municipality", and the payer keeps the right to claim a refund. That section speaks only of the city's tax: so the $0.65 of city tax is not owed back by law unless the customer claims it, and for the $0.16 of district tax we read no such rule. **Open (a citation check):** the crime-control district taxes under chapter 321 too (§321.1055), so §321.3025's "taxes imposed by the municipality" may reach its $0.16 as well.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** the utility credits the whole $0.81 when it finds the error, the district's $0.16 included, and does not leave the customer to claim it: a missing rule never holds back a refund (Kyle 11-03, answer 8). Recovering it on the utility's tax return is for a tax advisor.
- **Open (Kyle):** the April bill's period runs Mar 15 – Apr 14 and the tax starts Apr 1. Is the whole bill taxed (it closes after Apr 1: $0.81 of tax, $65.99), none of it (the first bill wholly after Apr 1 is May's: $65.18), or the taxable lines split by days (17 of 31 days untaxed)? Neither the local-tax rule (34 TAC §3.334) nor the Comptroller's rule on gas and electricity (34 TAC §3.295, read 2026-11-24) says; §3.295 speaks of a billing period only for predominant use. Recommendation: the utility states its method when it enters a tax change, as for rate changes (Kyle 11-03, answer 1), with a tax advisor's check. The same question arises for every tax change on a quarter's first day (SCN-0109).
- **Open (a citation check, or tax counsel):** whether a citywide crime-control district's territory grows with the city's annexation on the same tax date, or only when the district sends new boundaries (§321.1055(c)). The rates stream then records the date the law gives.
- A limited-purpose annexation moves neither tax membership: a city may not tax in a limited-purpose area (Local Gov't Code §43.130(c)).

---

### SCN-0109 — A published rate change: billed only once the utility approves it; a gap reported until then

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* a new published rate never bills by itself. The utility's operator approves it by recording a new row from the quarter's first day; the old row is closed, not edited. Until then the bill uses the utility's own row and a report lists every place where the published rate differs from it, or where a place a premise is in publishes a rate and the utility has no row. A billing run reads the tax rows and the premise's places at one instant, chosen when no earlier transaction is still open, and each bill records the rows and places it used. Sources: Kyle 10-14, answer 1 ("no rate change goes live without operator approval"); Ryan 2026-09-30; -30 (the gaps report; rows never edited, closed once); AC-47.

**Given**
- The Comptroller's file for the quarter beginning Fri Oct 1, 2027 publishes the City of Bluebonnet's rate as 1.25% (**invented**). The transit authority ended Sep 30, 2027 (**invented**, `cast.md` §2), so with the county's 0.5% and the crime-control district's 0.25% the local total is 2.0% everywhere in the city; had the transit authority still overlapped (or a district whose tax pays its debt), the city could not have raised its rate; a district without such debt would instead have been reduced automatically (Tax Code §321.101(f), §321.102(e)–(h); that case is under "Not yet written"). The platform loads it as the city's reference rate.
- Bills for the period Oct 15 – Nov 14 are issued Mon Nov 15, 2027 by one run: BB-01 (residential, $65.18) and BB-10 (the bakery, $187.40), both recorded in the city and the district.

**When** (a) nobody approves the change before Nov 15; (b) an operator approves it on Tue Oct 5; (c) an operator approves it on Sat Nov 20, after the bills; (d) the clerk tries to approve it by changing the rate on the existing row; (e) as (b), but the approval was being saved, not yet committed, when the run began.

**Then**

| Line | (a) and (c), as issued | (b) |
|---|---|---|
| BB-01 city tax | 1% → $0.65 | 1.25% × $65.18 = 0.8148 → $0.81 |
| BB-01 district tax | 0.25% → $0.16 | $0.16 |
| BB-01 total | **$65.99** | **$66.15** |
| BB-10 state, county, district | $11.71, $0.94, $0.47 | the same |
| BB-10 city tax | 1% → $1.87 | 1.25% × $187.40 = 2.3425 → $2.34 |
| BB-10 total | **$202.39** | **$202.86** |

- A test asserts each tax line: a missed district and a raised city rate can give the same total.
- **(a)** From Oct 1 the gaps report lists the City of Bluebonnet: Bluebonnet's row 1%, published 1.25%, with the published figure's source. Nothing bills at 1.25%.
- **(b)** The 1% row ends Sep 30; a 1.25% row runs from Oct 1, recorded Oct 5. The gap is gone. The approver is the operator the application records; **Open (rates):** the database does not refuse a tax row recorded with no user, though Kyle's answer 1 requires an operator's approval.
- **(c)** The Nov 15 bills read the rows as known at the run's instant, so they charge 1%, and each records the 1% row it used. They are $0.16 (BB-01) and $0.47 (BB-10) short of the approved rate.
- **(d)** Refused: a tax row is never edited. A change is a close and a new row.
- **(e)** The run must not choose an instant while the approval it began before is still open: it waits for no earlier transaction to be open, then chooses its instant and reads (AC-47). Choosing first and waiting after is not enough: a bill computed before the approval commits charges 1%, and every later read at that same instant answers 1.25%, so the bill cannot be reproduced from the rows (it still records the row it used). Had two separate transactions closed the old row and added the new one, a read at that instant could instead be refused for good (two rows of one tax).
- Had a county Bluebonnet's premises are recorded in published a rate with no Bluebonnet row, the report lists that county with no row: a published tax nobody approved.
- **Open (Kyle):** in (c), the utility owes the tax at 1.25% for the period whatever it billed (the stream's reading; a tax advisor confirms). Does it correct the issued bills, put the difference on the next bill, or absorb it? And if BB-10's Nov 15 bill is voided and rebilled in December for a misread, the rebill reads the rows as known then and charges 1.25% (the stream's reading, as in SCN-0110): is that right, or should a rebill keep the original's tax?

---

### SCN-0110 — A premise placed in the wrong jurisdiction: what the old bills used, and the correction

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* each bill records the tax rows and places it used, so it can always be shown what it did. When a premise's place on the tax axis turns out wrong, the place is corrected (voided and replaced, with evidence), and the bills it affected are corrected from the true facts; tax wrongly charged is credited. Sources: CI-001, CI-004, CI-047; -30 (places as known at an instant; known limit L7: a bill records what it used); AC-47; Kyle 11-03, answer 8 (a refund goes back as far as the records show).

**Given**
- **BB-12 (invented)**, a renter in the city's extraterritorial area, schedule R-R (correctly, on the regulatory axis). Service began Sep 15, 2026; at setup an address lookup placed the premise inside the City of Bluebonnet on the tax axis.
- The October and November runs each chose their instant when no earlier transaction was open (AC-47).
- Its two bills, October (Sep 15 – Oct 14) and November (Oct 15 – Nov 13), 6.0 Mcf each: $69.83 of tariff-priced lines, city tax 1% × $69.83 = 0.6983 → $0.70: **$70.53** each, both paid.
- On Thu Dec 3, 2026 the clerk reads the city's annexation ordinances and map, voids the city membership and records the premise in the extraterritorial area, citing the ordinances (evidence: an ordinance).

**When** (a) the October bill is shown on Dec 10; (b) the bills are corrected; (c) the December bill is issued Wed Dec 16.

**Then**
- **(a)** It shows what it charged and why: the city's row and the city membership it used. Read as known at its own run's instant, the premise is still inside; read now, it is outside. The bill's own record is what it used; the read at its instant agrees with it only because the run chose its instant as AC-47 requires.
- **(b)** Each bill is corrected without city tax: $69.83, **$0.70 credited** on each, **$1.40** in all.
- **(c)** No city tax: **$69.83**.
- Outside on the regulatory axis but inside on the tax axis is BB-12's shape; a disannexation produces it lawfully for a time (rates change on the ordinance date, the tax stops a quarter after the Comptroller's receipt), and an annexation the opposite (SCN-0108). Nothing refuses either, and nothing reports one. **Open (rates):** a report of premises whose two axes disagree with no annexation or disannexation recorded behind it would have caught BB-12 at setup.

---

### SCN-0111 — A city that taxes business gas but may not tax homes; the premise's use decides

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* a city whose sales tax began on or after Oct 1, 1979 taxes non-residential gas but may not tax residential gas; whether a premise is residential comes from its use, since Pecan Flat has one rate class. Sources: `cast.md` §1; Tax Code §321.105(a), §151.317(c), (e); 34 TAC §3.295(a)(8) (residential use), (f)(1) (predominant use per meter), (h)(5) (a single-family home needs no certificate); Kyle R-13.

**Given**
- Pecan Flat (`cast.md` §1): one rate, $9.00 per Mcf plus gas cost ($6.10 per Mcf in this month, **invented**, as in SCN-0053 and SCN-0084). Every gas line is flagged taxable (**invented**). Its city sales tax, 1.5%, was adopted in 1987 (**invented**), so it may not reach residential gas; its county levies none (**invented**). Each premise below is recorded on the tax axis in the State of Texas and the City of Pecan Flat, and in no district or transit authority.
- What each premise's use is recorded as, today by the clerk: PF-01 a home, owner-occupied; **PF-03 (invented)**, a café, commercial; **PF-04 (invented)**, a house the owner rents to visitors by the week, short-term rental; **PF-05 (invented)**, a home with a hair salon in the garage on the same meter.

**When** the bills are issued: (a) PF-01, 5.0 Mcf; (b) PF-03, 30.0 Mcf; (c) PF-04, 5.0 Mcf; (d) PF-05.

**Then**

| Line | (a) PF-01 | (b) PF-03 | (c) PF-04 |
|---|---|---|---|
| Gas, $9.00 per Mcf | $45.00 | 30.0 × $9.00 = $270.00 | $45.00 |
| Gas cost, $6.10 per Mcf | $30.50 | 30.0 × $6.10 = $183.00 | $30.50 |
| State sales tax | none: residential | 6.25% × $453.00 = 28.3125 → $28.31 | 6.25% × $75.50 = 4.7188 → $4.72 |
| City sales tax | none: residential | 1.5% × $453.00 = 6.7950 → $6.80 | 1.5% × $75.50 = 1.1325 → $1.13 |
| **Total** | **$75.50** | **$488.11** | **$81.35** |

- **(c)** Not residential use: the Comptroller's rule defines it as use in a building "occupied as a residence", and a tenant's only on a term of more than 29 days, or beyond 29 consecutive days with documentation (34 TAC §3.295(a)(8); Tax Code §151.317(c)). Weekly visitors meet neither. The stream's reading; a tax advisor confirms.
- **(d)** One meter used for both is wholly taxable or wholly exempt by its predominant use in each billing period (§151.317(e)).
- **Settled by rule (2026-11-25, triage of Kyle's questions):** the use recorded on the premise decides, dated and changed when the customer reports it. The law fixes the test (all or nothing, by predominant use each period), so only how the use is recorded was open, and that is a record shape, the stream's to settle; a figure per bill is not needed to apply an all-or-nothing test. Kyle deferred predominant use to a record of its own (R-13).
- **Open (rates):** a premise's use has one current value today, with no dates, and no value for a short-term rental; and where the schedule says residential but the use says otherwise (a weekly rental on Bluebonnet's R-U), nothing says which decides. Both are needed before (a)–(c) can be tested as written.

---

### SCN-0112 — Another state: a tax charged on top of another tax, in the stated order

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle. All Fremont law here is **invented** (`cast.md` §4).
*Rule:* a tax is charged on another tax only where its row names that kind of tax; the taxes are computed in stack order, each on its base plus the taxes it names. A row may not name its own kind, nor a kind of tax the platform does not know. Sources: Kyle 10-14, answer 2 (the stack comes from law and the tariff); `tax-design.md` 2.1 (tax on tax declared, empty by default); -30.

**Given**
- Prairie Line Gas Company (`cast.md` §4); **PL-03 (invented)**, a homeowner in the City of Lakeview, Fremont. Rates **invented**: $15.00 a month and $6.00 per Mcf; 8.0 Mcf.
- Fremont taxes residential gas. Lakeview levies a 3% utility users' tax, position 1; Fremont's 5% sales tax is position 2 and is charged on the bill including the utility users' tax. "Utility users' tax" is a kind of tax the platform adds by a reviewed data change, not a change to the calculation.

**When** (a) the bill is issued; (b) Prairie Line enters the sales-tax row without naming the utility users' tax; (c) a clerk enters a sales-tax row charged on sales tax; (d) a row names a kind of tax the platform has not added.

**Then**
- **(a)**

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | | $15.00 |
  | Usage | 8.0 Mcf × $6.00 | $48.00 |
  | Utility users' tax (1) | 3% × $63.00 | $1.89 |
  | Sales tax (2) | 5% × ($63.00 + $1.89) = 3.2445 | $3.24 |
  | **Total** | | **$68.13** |

  The sales-tax line's base records the two charges and the utility users' tax line.
- **(b)** The sales tax is 5% × $63.00 = $3.15: **$68.04**. Both are possible rows; only the law says which is right, so the platform takes the row as entered and the bill shows its base.
- **(c)** and **(d)** Refused when entered. So one place's sales tax cannot be charged on another place's sales tax; no known law does that, but the limit is noted for the rates stream.
- **Open (rates):** nothing checks that a tax charged on another sits later in the stack. A sales-tax row at position 1 charged on a utility users' tax at position 2 would leave the core no order to compute in. Refuse it when entered?

---

### SCN-0113 — Entering a tax row: what is refused, and what is not

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle.
*Rule:* a tax row names a place of a kind that levies that tax, which exists in the platform's places over the whole of the row's dates; its rate has at most four decimals; its citation is not blank; it is the entering utility's own. A place is never closed from under a row. Sources: -30 (its rules, each a battery check); Kyle 10-14, answer 2 (source and citation required); K-06.

**Given** Bluebonnet's clerk enters tax rows (all **invented** except as cited).

**When** the clerk enters (a) the crime-control district's row in December 2026, before the platform has loaded the district as a place; (b) a city rate of 1.12345%; (c) a row with the citation "—"; (d) a row in the utility Pecan Flat's name, signed in as Bluebonnet; (e) a Bluebonnet row naming the City of Pecan Flat, where Bluebonnet serves no premise; (f) a sales-tax row naming the city's extraterritorial area; (g) a county row that says it reaches residential gas; and (h) the platform later closes the City of Bluebonnet's place record while Bluebonnet's row is in force, with no successor.

**Then**
- **(a)** Refused: there is no such place yet. The districts and their published rates are a platform data load (-32, not built); until then no utility can bill a district's tax.
- **(b)** Refused: four decimals at most (the row names a place already loaded; a row naming a place not yet loaded is refused for the place before its decimals are checked). **(c)** Refused: a citation has a letter or a digit. **(d)** Refused: a utility writes its own rows only.
- **(e)** Accepted, once the platform has loaded the City of Pecan Flat as a place (until then refused, as in (a)). A utility may serve premises in another city, so naming one is lawful; this row bills nothing until a premise is recorded there.
- **(f)** Refused: only a state, county, city, transit authority or special district levies sales tax.
- **(g)** Accepted. Counties, transit authorities and most districts may not tax residential gas (34 TAC §3.334(l)(1)(A)), so the row is wrong, but nothing refuses or reports it. Nor is a city's "reaches residential" compared with whether the city may (Tax Code §321.105). **Open (rates):** refuse (g) for a kind of place the law bars, and add the residential question to the gaps report?
- **(h)** Refused when committed, unless a successor place with the same code covers the row's dates in the same transaction: the row is keyed by the place's code, so it carries over to the successor.

---

### SCN-0114 — The tax owed to each jurisdiction for a period: billed and collected

*Status:* draft (2026-11-24); review round 5 and its second pass applied. Not yet sent to Kyle. The liability record is the money stream's and is not built (-30 limit L5).
*Rule:* the platform holds the liability, not the remittance: per jurisdiction and accounting period, the tax billed and the tax collected, and an optional filing reference. Payments to the state and cities stay in the utility's own books. A tax is billed in the period of the bill or charge that carries it, and collected in the period the payment that pays it posts (the stream's reading). Sources: Kyle 10-14, answer 4; Kyle 10-15, K-05 (the utility's own order within a bill); -23 (a payment is applied per line).

**Given**
- Bluebonnet's November 2026 bills (issued Nov 16): BB-10 (SCN-0104, $201.92), BB-08 (SCN-0106 (b)'s figures, $447.32, **invented** for November) and BB-03 (SCN-0107 (a), exempt). For this scenario they are the only taxed bills, and no December bill is issued to BB-10, BB-08 or BB-03 (**invented**). BB-08 and BB-03 pay in full on Wed Nov 25.
- BB-10 pays nothing by the due date; its penalty and the penalty's tax post on Wed Dec 2 (SCN-0104 (b)). It pays $100.00 on Thu Dec 3, and the rest, $122.11, on Tue Dec 15.
- Within one bill Bluebonnet pays the fixed charge, then usage, then riders, then taxes, then fees (`cash.md`, **invented**; K-05).

**When** the November and December liabilities are read on Jan 4, 2027.

**Then**

| Jurisdiction | Nov billed | Nov collected | Dec billed | Dec collected |
|---|---|---|---|---|
| State of Texas | $11.71 + $26.19 = $37.90 | $26.19 | $1.17 | $11.71 + $1.17 = $12.88 |
| Bluebonnet County | $0.94 + $2.10 = $3.04 | $2.10 | $0.09 | $0.94 + $0.09 = $1.03 |
| City of Bluebonnet | $1.87 | $0.00 | $0.19 | $1.87 + $0.19 = $2.06 |

- BB-10's $100.00 on Dec 3 pays the $12.80 customer charge, the $59.20 distribution and $28.00 of the commodity charge: no tax. The Dec 15 payment pays the rest of the bill and its three taxes, then the penalty and its taxes, taking the bill before the penalty (the cash family's order, Kyle 11-05, answer 16; either way both are paid by Dec 15, so the table does not depend on it).
- Each figure traces to the bill lines that make it up, and each line to its row and place. BB-03's $0.00 lines carry a base of $444.10 per jurisdiction, and the liability shows that exempt base too, for the utility's return.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** showing the exempt sales beside each jurisdiction's tax is a report layout, the stream's to settle.
- **Open (Kyle):** when a payment reaches a bill's tax lines but cannot pay them all, are they paid in stack order or in proportion? K-05 orders kinds of charge, not lines of the same kind.
- **Settled by rule (2026-11-25, triage of Kyle's questions):** whether tax is reported when billed or when collected, and in which month, is the utility's own reporting basis, stated at onboarding (the tariff and the utility govern, Kyle 11-03); the liability holds both figures either way (Kyle 10-14, answer 4).

---

### SCN-0115 — Places that overlap: a transit authority on part of the city

*Status:* draft (2026-11-24), written after review round 5 (Codex 8, Fable missing cases 2 and 7, Opus M9); second pass applied. Changed 2026-11-25 (review round 6, Fable S-G2): the transit authority is 0.25%, the least Texas allows, and the hospital district is removed so east of Main stays at the 2% limit; BB-13 is $202.86. Not yet sent to Kyle.
*Rule:* a premise pays the tax of each place it is recorded in, decided premise by premise, not by its city; a place that covers part of a city (a transit authority here; a district alike) taxes only the premises inside it. A transit authority's tax and most districts' never reach residential gas. Sources: Kyle 10-14, answer 1 ("a service location links to every jurisdiction it sits in"); 34 TAC §3.334(k)(8), (l)(1)(A); Tax Code §321.101(f) (every local tax at a location, a transit authority's included, counts toward the 2% limit) and §321.102(e)-(h) (a transit authority's rate is never the one automatically reduced).

**Given**
- The Bluebonnet Area Transit Authority (**invented**), 0.25%, the least a Texas transit authority may levy (Transportation Code §451.404(a), §452.401(a), §460.551(a)), covers the part of the city east of Main Street, and does not tax residential gas. It ends Sep 30, 2027 (**invented**; SCN-0109). A transit authority is joined or left by whole cities or county areas, so a city only partly inside one got that way by annexing land beyond it (**invented**: Bluebonnet annexed the land west of Main from outside the authority). **Open (a citation check):** how annexation moves a transit authority's boundary (Transportation Code ch. 451, 452, 460). With the city's 1%, the county's 0.5% and the crime-control district's 0.25%, the local total east of Main is 2.0%, the limit.
- February 2027 bills (period Jan 15 – Feb 14). **BB-13 (invented)**, a hardware store east of Main, schedule SC-U, 20.0 Mcf; BB-10, the bakery, west of Main; **BB-14 (invented)**, a home east of Main, R-U, 6.0 Mcf. Each premise's memberships are recorded as stated.

**When** the bills are issued.

**Then**

| Line | BB-13, store east | BB-10, bakery west | BB-14, home east |
|---|---|---|---|
| Tariff-priced lines | $187.40 | $187.40 | $65.18 |
| 1 State 6.25% | $11.71 | $11.71 | none |
| 2 County 0.5% | $0.94 | $0.94 | none |
| 3 City 1% | $1.87 | $1.87 | $0.65 |
| 4 Crime-control district 0.25% | $0.47 | $0.47 | $0.16 |
| 5 Transit authority 0.25% | 0.4685 → $0.47 | none: outside | none: residential |
| **Total** | **$202.86** | **$202.39** | **$65.99** |

- BB-13's crime-control district and transit lines are both $0.47: a test tells them apart by the row and place each line names, not by amount.
- Two businesses in the same city pay different taxes because of where each is; a core that keys transit to the city would bill BB-10 $0.47 too much.

---

### SCN-0116 — A taxed bill with a line outside the tax base and a credit inside it

*Status:* draft (2026-11-24), written after review round 5 (Fable missing cases 3 and 9; Opus M9); second pass applied. Not yet sent to Kyle.
*Rule:* a tax's base is the lines flagged taxable, including a negative one, which lowers it; a line not flagged taxable stays outside every tax base on a taxable customer's bill. Sources: Kyle 10-14, answer 5 ("a taxable customer never makes a non-taxable item taxable"); 34 TAC §3.295(j) ("Sales or use tax is not due on any surcharge for pipeline safety fees" of an investor-owned or municipally owned gas distribution company, read 2026-11-24); 16 TAC §8.201; Bluebonnet's tariff (the gas cost adjustment can be a credit).

**Given** BB-10's March 2027 bill (period Feb 15 – Mar 14), 20.0 Mcf, with a gas cost credit of −$0.15 per Mcf (**invented**) and the year's $1.00 pipeline safety fee (SCN-0054).

**When** the bill is issued.

**Then**

| Line | Arithmetic | Amount |
|---|---|---|
| Customer charge | | $12.80 |
| Distribution | 20.0 Mcf × $2.96 | $59.20 |
| Commodity charge | 20.0 Mcf × $5.35 | $107.00 |
| Gas cost adjustment | 20.0 Mcf × −$0.15 | −$3.00 |
| Pipeline safety fee | not taxable | $1.00 |
| State sales tax | 6.25% × $176.00 | $11.00 |
| County sales tax | 0.5% × $176.00 | $0.88 |
| City sales tax | 1% × $176.00 | $1.76 |
| Crime-control district | 0.25% × $176.00 | $0.44 |
| **Total** | | **$191.08** |

- Each tax line's base names the four gas lines, the credit among them, and not the fee. Taxing the fee would add $0.08 to the four taxes ($0.06, $0.01, $0.01, $0.00 at these rates).
- How a negative line nets in what the bill shows as open after a payment is the money stream's question already on the board (review round 4); the tax arithmetic here does not depend on it.

---

## Not yet written (tax)

A city rate rise that would pass 2% where a district or transit authority overlaps (Tax Code §321.101(f), §321.102(e)-(h): the district's rate is reduced there automatically unless it has debt paid from the tax; a transit authority's never is, so the city may not raise); disannexation worked through; a premise with no city status recorded on the tax axis (refuse the bill, or tax by the state alone? for Ryan or the rates stream); a premise whose use changes partway through a period; the franchise fee (after -31).
