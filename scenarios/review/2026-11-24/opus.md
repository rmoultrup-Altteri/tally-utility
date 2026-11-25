# Review: scenarios/tax.md (SCN-0104 to 0114), commit dc7209c

Reviewer: Opus. Scope: `scenarios/tax.md`, the `cast.md` edits, the SCN-0055 (c) correction note. Read against `scenarios/README.md`, `application/places-sources/texas.md` §3 and §5, `tax-inventory.md`, `tax-design.md`, `sql/v5.4.2-30-tax-levies-and-taxability.sql`, the live `tally` database (read-only selects: `place_kinds`, `tax_kinds`, `places`, `place_fact_kinds`, membership checks), AC-47, Kyle's rulings (10-14; 11-03 answer 4; 11-05 answers 3a, 3b, 16, 20; 08-26 R-12/R-13; 09-02 R-26; 10-15 K-05) and the other scenario files.

## What I checked and found clean

- **Arithmetic.** I recomputed every line. All four-decimal working figures, half-up cents and totals are right: 0104 (a) $201.92, (b) $20.19; 0105 $65.83 / $65.99 / $202.39; 0106 $447.32; 0107 $444.10 / $478.52; 0108 $69.83 / $65.18 / $65.99 / refund $0.81; 0109 $65.99 / $66.15 / $202.39 / $202.86 and the shortfalls $0.16 / $0.47; 0110 $70.53, refund $1.40; 0111 $75.50 / $481.31 / $80.22; 0112 $68.13 / $68.04; 0114's billed sums. No case where rounding to four decimals first changes the cent.
- **Weekdays.** These are all right: Thu Oct 15, Fri Oct 30, Mon Nov 16, Tue Nov 3 (2026); Mon Feb 15, Wed Mar 3, Thu Apr 1, Fri Oct 1, Tue Oct 5, Mon Nov 15, Sat Nov 20 (2027); Thu Dec 3, Thu Dec 10, Tue Dec 15 (2026). Due dates are 15 days after issue. The period of 31 days with 17 untaxed in 0108 (c) is right.
- **Texas law.** These claims match the sources:
  - §321.102(c): the quarter after the Comptroller receives the ordinance and map, so Mar 3 gives Apr 1.
  - §321.201(a), §321.1055(c)(2) and (d), §321.203(f), 34 TAC §3.334(k)(8) and (l)(1)(A).
  - §151.317(c)(2) (more than 29 days) and (e) (predominant use).
  - LGC §43.130(c), §42.902.
- **Schema claims against v5.4.2-30 and the live database.** Each claim below matches the patch and the data:
  - **SCN-0109.** A levy is never edited, only closed and succeeded; `created_by` records who approved it. The gaps report has both parts: a rate that differs, and a place with a published rate but no levy (r2).
  - **SCN-0112 (c) and (d).** `computed_on` naming its own kind is refused; so is an unknown kind. `tax_kinds` is platform-held.
  - **SCN-0113.** Each refusal is in `tax_levy_insert_check`: a place not in force over the dates, more than four decimals, a blank citation, another tenant. A county with `reaches_residential = true` is accepted. `z_check_place_levy_coverage` refuses a close with no successor and passes a same-code successor.
  - **SCN-0107 (d).** A non-empty `service_types` is required, and `should_charge_tax` raises on a NULL service type.
  - **Places.** Live `place_kinds` includes `special_purpose_district`, `extraterritorial_area` and `limited_purpose_area`. Only Texas and its counties are loaded, as the header says (-32).
- **Rulings.** No scenario contradicts:
  - Kyle 10-14 answers 1, 2, 4 and 5;
  - Kyle 11-03 answer 4;
  - Kyle 11-05 answers 3a, 3b and 20;
  - Kyle R-12, R-13 and R-26.

---

## Findings

### B1 (blocker). SCN-0114: the October figures leave out BB-10's late penalty and its tax, and count a November payment in October

**What is wrong.** BB-10's bill was due Fri Oct 30. It pays on Tue Nov 3, so it is late, and by SCN-0104 (b) and the cast's penalty rule a penalty of $18.74 posts the day after the due date. That day is Sat Oct 31, inside October (compare SCN-0048 and cash.md line 249: "unpaid on Dec 1; on Dec 2 a penalty"). That penalty carries its own tax lines: state $1.17, city $0.19, county $0.09. So October's billed tax is:

| Jurisdiction | Correct | Table shows |
|---|---|---|
| State | $39.07 | $37.90 |
| City | $2.06 | $1.87 |
| County | $3.13 | $3.04 |

Accounting periods are calendar months (periods-and-aging.md, common facts), so the Nov 3 payment falls in November. October's "tax collected" for BB-10 is $0.00 whatever the payment order. The "BB-10's share (Open)" cells for October are therefore not open at all.

**Fix.** Pick one:
- add the penalty's tax lines to October's billed figures and put BB-10's collection in a November table; or
- have BB-10 pay on time, part of the bill, in October, if the aim is a partial payment inside the period.

Also say that "period" means the accounting period. Whether it means that or the filing period is an open point in tax-inventory §4 point 12.

### S1 (should-fix). SCN-0114: the Open on splitting a partial payment within one bill is already answered

**What is wrong.** Kyle's K-05 (10-15) makes the order within a bill the utility's own setting. cash.md's common facts set it for every cast utility: fixed charge, usage, riders, taxes, fees. BB-10's $100.00 is less than its $187.40 of charges, so it pays no tax at all. The Open's three options (tax first, last, or in proportion) do not apply, and answer 16 is not the relevant ruling.

**What is still open.** How one payment is split among three tax lines of the same kind, once it reaches the taxes. cash.md's order is by kind of charge, and all three lines are taxes.

**Fix.** Use a payment that reaches partway into the taxes, for example $195.00 on $201.92. Cite K-05 and cash.md for the order. Ask Kyle only how the three tax lines share the remainder.

### S2 (should-fix). SCN-0108 (b): the March 2027 bill leaves out the pipeline safety fee

**What is wrong.** Bluebonnet bills the fee ($1.00 per service line) on its March bills (cast §2; SCN-0054: "the March bills are issued on Mar 15, 2027"). BB-11's March bill is issued in March 2027, so it should carry the fee, outside the tax base: **$66.18**, not $65.18.

**Fix.** Add the fee line and change the total to $66.18, or say BB-11's March bill is taken without it. Either way, the comparison with tax still holds, since the fee is outside every tax base.

### S3 (should-fix). SCN-0110: the premise was set up on Jan 1, 2026, but only October and November are corrected

**What is wrong.** BB-12 was placed inside the city on the tax axis "when it was set up on Jan 1, 2026", the day Bluebonnet went live. Its January to September 2026 bills would also have carried the wrong city tax. As written, (b) refunds $1.40 when the true refund is about $7.70 (eleven bills at $0.70, if each had the same usage).

**Fix.** Either:
- set BB-12 up on Sep 15, 2026 (for example, a move-in), so only October and November carry the tax; or
- correct every bill from January and state the total. Kyle's ruling for a city whose ordinance is silent: refunds go back as far as the records show.

### S4 (should-fix). SCN-0111: Pecan Flat's "no city sales tax at all" is not in the cast

**What is wrong.** The scenario's title and Rule say "a city that levies no local tax", citing "`cast.md` §1 (Pecan Flat: no local sales tax adopted)". But cast §1 says only "Local sales tax **on residential gas**: not adopted". That leaves open whether Pecan Flat levies a city sales tax on commercial gas. This commit added the county row ("none") but no row for the city. PF-03's café bill ($481.31, state tax only) therefore rests on a fact the cast does not hold.

**Fix.** Add a cast §1 row: "City sales tax: none (**invented**): Pecan Flat levies no local sales tax". Or add a city tax line to PF-03.

### S5 (should-fix). SCN-0107: "only over its dates" is in the Rule but no case tests it

**What is wrong.** The Rule says an exemption counts "only over its dates". The cases test the service named (b), the verification (c) and an exemption with no service (d), but nothing about dates. CI-046 is specifically "lifecycle and period validity".

**Fix.** Add a case: a certificate that expires partway through a billing period (or starts partway through). Two things need deciding:
- whether the exemption is read on one date (the period's end, as the franchise reference date of Kyle's D6-1), or split;
- what the $0.00 line shows.

If that is not ruled, the Open goes to Kyle.

### S6 (should-fix). SCN-0108 (e) and SCN-0110 cite "Kyle 11-04" for unlimited refunds at a silent city; that ruling is Kyle 11-03, answer 8

**What is wrong.** No 11-04 Kyle ruling exists in GBM. The rule that a city with a silent ordinance refunds "as far back as the records show" is Kyle 11-03, answer 8 (backbilling.md, opening note). Answer 12 of 11-05 covers the months before go-live.

**Fix.** Cite "Kyle 11-03, answer 8 (and 11-05, answer 12 for months before go-live)" in both places.

### S7 (should-fix). SCN-0113 (d) is ambiguous: "a row for Pecan Flat's city, signed in as Bluebonnet"

**What is wrong.** There are two readings:
- **Bluebonnet writes a row under Pecan Flat's utility.** That is refused ("a utility writes its own levies only").
- **Bluebonnet writes its own row naming the City of Pecan Flat as the place.** That is **accepted**, once that city is loaded. Nothing ties a levy's place to the utility's service area; the gaps report only reads places the utility's premises are in.

A test built from the second reading would expect a refusal the schema does not give.

**Fix.** Write "a row recorded as Pecan Flat's own, signed in as Bluebonnet". Optionally add an Open (rates): should a levy for a place none of the utility's premises are in be reported?

### M1 (minor). Claims stated as law that the sources do not support

- **§151.051, the 6.25% state rate** (SCN-0104, 0106, cast "Tax rows"). texas.md lists the 6.25% rate under "Could not verify", and §151.051's text is not in the sources. Mark it "to check" or quote it.
- **SCN-0105: "the limit is applied by the Comptroller in the rate it publishes".** The sources say only that the rate is "automatically reduced" under §321.102(e)-(h), not who applies it.
- **SCN-0107 Open: "In Texas a buyer can also claim a refund from the Comptroller".** This is not in the sources; mark it "not checked".
- **SCN-0111 (c): "a stay under 30 days is not a residence (§151.317(c)(2))".** (c)(2) defines a tenant's residential use (a term longer than 29 days). The conclusion also needs (c)(1) not to apply, since the owner does not occupy the house as a home. Rephrase so it doesn't claim more than the text.
- **SCN-0108: "34 TAC §3.334, 2024 text".** The sources cite the Cornell (LII) copy with no year.

### M2 (minor). Cast wording: Bluebonnet "adopted" a city tax on residential gas

**What is wrong.** Under §321.105(a), a city that adopted its tax on or after Oct 1, 1979 may not tax residential gas. Only a city whose tax predates that and that kept or reimposed it may. SCN-0105 says Bluebonnet "kept the tax", but cast §2 still says "adopted, city rate 1%" and cites §321.105 as making it the city's choice. Pecan Flat's row says the same.

**Fix.** Write "kept (a city whose tax predates Oct 1, 1979, **invented**)". For Pecan Flat, the choice exists only if it is such a city.

### M3 (minor). SCN-0114 cites CI-044 for the tax liability; CI-044 is the franchise fee invariant

CI-044 is "Franchise Fee Traceable to Franchising Jurisdiction". The sales-tax liability (Kyle 10-14, answer 4) has no invariant of its own. tax-inventory §4 point 12 says the remittance half of CI-044 needs re-reading against answer 4. Cite Kyle's answer 4 as the rule, and CI-044 only by analogy, or drop it from the file's header.

### M4 (minor). New cast members used but not added to the cast

- PF-04 and PF-05 (SCN-0111) are not in the customers table.
- BB-08 (SCN-0055, now reused by 0106 and 0114) is not there either.
- Fremont's tax facts (Lakeview's utility users' tax at 3%, the 5% sales tax on top of it, Fremont taxing residential gas) are not in cast §4's "Fremont's rows so far" table.

The cast's own rule: "If a scenario needs a fact the cast doesn't have, add it here first."

### M5 (minor). SCN-0110's last bullet has the directions backwards

**What is wrong.** BB-12's shape is outside on the rate-schedule axis and inside on the tax axis. An annexation (SCN-0108) produces the opposite: inside for rates from the ordinance's date, outside for tax until the quarter. A disannexation produces BB-12's shape, because the tax stays until the quarter after the Comptroller receives the ordinance.

**Fix.** Say the disannexation is the case that matches. Also, since this mismatch is exactly what hid BB-12's error, consider an Open (rates): a report of premises whose two axes disagree with no annexation or disannexation behind it.

### M6 (minor). SCN-0112: "a kind of tax the platform adds for Fremont, not a code change"

`tax_kinds` is "written by reviewed migration" (-30), so adding a kind is a reviewed data patch, not a clerk's entry. Say "a platform row added by a reviewed migration, not a change to the calculation".

### M7 (minor). SCN-0104 and 0107 take Bluebonnet's October rates for small commercial and governmental customers, while SCN-0001's Oct 1 ordinance changed only the residential schedule

SCN-0001's ordinance raises only R-U. SC-U shares R-U's new figures ($12.80, $2.96), so a reader may ask whether SC-U changed on Oct 1 too. If it did, BB-10's Sep 15 – Oct 14 bill would split. State it in the common facts: "small commercial and governmental rates unchanged Oct 1 (**invented**)".

### M8 (minor). SCN-0104 (b): the Open on taxing the penalty is mostly answered

Kyle 11-05 answer 3b says a forfeited discount is "taxed like the gas". On a commercial bill the gas carries state, county and city tax. The Open can be narrowed to a confirmation, with the tax-advisor check already on the list.

### M9 (minor). Important cases of tax by location not yet written

These are suggestions for a later batch, not defects in what is written:
- **A transit authority, or two districts stacking, with the automatic reduction to 2%** (§321.102(e)-(h); AC-47 names "two stacking districts" as its risk).
- **Tax on a credit or a correction:** a gas cost credit inside the city lowers the tax base; a void-and-rebill refunds tax using the levies in force at the time.
- **A premise whose use changes from home to business partway through a period** (beside SCN-0111 (d)).
