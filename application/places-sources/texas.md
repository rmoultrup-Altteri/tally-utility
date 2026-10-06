# Texas source inventory for a `places` model (gas billing)

Researched 2026-10-06. All statute text below was fetched from the Texas Legislative Council's file server, which backs statutes.capitol.texas.gov. That site is now an Angular app, so `curl` on `statutes.capitol.texas.gov/Docs/...` returns only the app shell. The working raw path is:
`https://tcss.legis.texas.gov/resources/<CODE>/htm/<CODE>.<CH>.htm` (e.g. `.../resources/UT/htm/UT.101.htm`).
The citable public URL form is `https://statutes.capitol.texas.gov/Docs/UT/htm/UT.101.htm#101.003`.
TAC text came from Cornell LII (`https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-45` form). LII says it updates quarterly, so LII text may lag the Texas Register.
Quotes are verbatim from the fetched text. Copies of the fetched files are in `scratchpad/src/`.

---

## 1. Gas rate jurisdiction (GURA, Utilities Code Title 3, Subtitle A)

### Short answer to the critical question
**GURA's "gas utility" definition excludes municipal corporations. A city-owned gas system is not a GURA "gas utility". The Railroad Commission (RRC) has no rate or service jurisdiction over it, except where GURA expressly names "municipally owned utility".** The city council sets the rates, by ordinance or under its charter. The one RRC hook is an appeal by ratepayers who live outside the city.

**Utilities Code §101.003(7)** — https://statutes.capitol.texas.gov/Docs/UT/htm/UT.101.htm#101.003
> "Gas utility" includes a person or river authority that owns or operates for compensation in this state equipment or facilities to transmit or distribute combustible hydrocarbon natural gas or synthetic natural gas for sale or resale in a manner not subject to the jurisdiction of the Federal Energy Regulatory Commission under the Natural Gas Act ... The term does not include:
> (A) a municipal corporation; ...

**§101.003(8)**
> "Municipally owned utility" means a utility owned, operated, and controlled by a municipality or by a nonprofit corporation the directors of which are appointed by one or more municipalities.

**§101.003(4)** (corporation)
> ... The term does not include a municipal corporation, except as expressly provided by this subtitle.

**§101.003(13)**
> "Regulatory authority" means either the railroad commission or the governing body of a municipality, in accordance with the context.

**§102.002 — Limitation on RRC jurisdiction** (UT.102.htm#102.002)
> Except as otherwise provided by this subtitle, this subtitle does not authorize the railroad commission to:
> (1) regulate or supervise a rate or service of a municipally owned utility; or
> (2) affect the jurisdiction, power, or duty of a municipality that has elected to regulate and supervise a gas utility in the municipality.

GURA names "municipally owned utility" expressly in these places:
- §102.101(e): uniform accounts. "In this section, 'gas utility' includes a municipally owned utility."
- §102.152 / §104.054: depreciation accounts and rates.
- §102.153 / §104.058: merchandise profit and loss.
- §102.202: audit.
- §104.056: tax benefits incl. investment tax credit.
- §§104.201-.203, 104.254-.2551: service to and billing of state agencies and public retail customers. Under §104.203 a payment in lieu of taxes may not be counted in rates charged to school and hospital districts.
- **§103.053: appeal by ratepayers outside the municipality.**

**Jurisdiction over investor-owned and other non-municipal gas utilities**

**§102.001(a)** (UT.102.htm#102.001)
> The railroad commission has exclusive original jurisdiction over the rates and services of a gas utility:
> (1) that distributes natural gas or synthetic natural gas in: (A) areas outside a municipality; and (B) areas inside a municipality that surrenders its jurisdiction to the railroad commission under Section 103.003; and
> (2) that transmits, transports, delivers, or sells natural gas ... to a gas utility that distributes the gas to the public.
> (b) The railroad commission has exclusive appellate jurisdiction to review an order or ordinance of a municipality exercising exclusive original jurisdiction as provided by this subtitle.

**§103.001** (UT.103.htm#103.001)
> ... the governing body of a municipality has exclusive original jurisdiction over the rates, operations, and services of a gas utility within the municipality, subject to the limitations imposed by this subtitle, unless the municipality surrenders its jurisdiction to the railroad commission under Section 103.003.

**§103.003: surrender and reinstatement.** This is a fact about the city that changes over time.
> (a) A municipality may elect to have the railroad commission exercise exclusive original jurisdiction over gas utility rates, operations, and services in the municipality by ordinance or by submitting the question of the surrender of its jurisdiction to the voters at a municipal election. ... (c) A municipality may not elect to surrender its jurisdiction while a case involving the municipality is pending. (d) A municipality that surrenders its jurisdiction to the railroad commission may reinstate its jurisdiction. ...

**§103.053: appeal by ratepayers of a municipally owned utility who are outside the municipality**
> (a) The ratepayers of a municipally owned utility who are outside the municipality may appeal to the railroad commission an action of the municipality's governing body affecting the municipally owned utility's rates by filing with the railroad commission a petition for review signed by a number of ratepayers served by the utility outside the municipality equal to at least the lesser of 10,000 or five percent of those ratepayers. ... (c) For purposes of this section, each person who receives a separate bill is a ratepayer. ...

§103.054: the petition must be filed within 30 days after the city's final decision. §103.055: the appeal is heard de novo. The RRC sets the rates "the municipality should have set". If the RRC has not ruled after 185 days, the proposed rates are deemed approved.

**§104.006: rates outside municipalities** (non-municipal gas utilities)
> Without the approval of the railroad commission, a gas utility's rates for an area not in a municipality may not exceed 115 percent of the average of all rates for similar services for all municipalities served by the same utility in the same county as that area.

The units here are **county** plus the set of municipalities that utility serves within that county.

**Other chapters that reach municipal systems directly**
- **Local Government Code §552.001(b)-(c)** (LG.552.htm): "A municipality may purchase, construct, or operate a utility system inside or outside the municipal boundaries ... may sell water, sewer, gas, or electric service to any person outside its boundaries." §552.002(c) covers home-rule cities: "... may sell it to the public on terms as provided by the municipal charter, ordinance, or resolution of the governing body of the municipally owned utility." §552.906(b)(1) covers general-law cities: "by ordinance regulate the rates and compensation charged the public by the municipality for utility service".
- **LGC §552.0025** (municipal deposits and liens): "(c) A municipality may require varying utility deposits for customers as it deems appropriate in each case." It also bars charging a new customer for a prior customer's debt (a), bars third-party guarantees (b), and allows a lien by ordinance on non-homestead property (d)-(h). The lien does not reach tenant-name accounts after the owner gives rental-property notice. The lien is perfected by recording in **the real property records of the county where the property is located**.
- **Utilities Code ch. 182, Subch. A** (elderly payment delay) applies to public utilities. §182.001(2): "'Utility' means an electric, gas, water, or telephone utility operated by a public or private entity." §182.002 requires a delay to the 25th day for a residential customer aged 60 or over. §182.005 exempts a utility only if it charges no late fee, does not suspend before the 26th day, **and** is regulated under Title 2.
- **Utilities Code ch. 182, Subch. B** (customer-data confidentiality) applies to a "government-operated utility", which §182.051(3) defines to include gas.
- **Utilities Code §121.211(d),(g)**: the RRC pipeline-safety fee of up to $1 per service line. "Each operator of a gas distribution system and each gas master meter operator shall recover as a surcharge to its existing rates the amounts paid". The text is not limited to GURA "gas utilities". Municipal operators are operators.

### Does 16 TAC Chapter 7 (incl. §7.45) apply to municipally owned systems?
**On its face, no, with one express exception.** Chapter 7's definition imports the Title 3 definitions, and those exclude municipal corporations.

**16 TAC §7.115(18)** — https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-115
> Gas utility (utility)--Any gas utility or utility as defined in Texas Utilities Code, Title 3.

**16 TAC §7.115(26)**
> Municipality--A city, incorporated village, or town, existing, created, or organized under the general, home-rule, or special laws of the state.

**16 TAC §7.45 opening paragraph** — https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-45
> For gas utility service to residential and small commercial customers, the following minimum service standards shall be applicable in unincorporated areas. In addition, each gas distribution utility is ordered to amend its service rules to include said minimum service standards within the utility service rules applicable to residential and small commercial customers within incorporated areas, but only to the extent that said minimum service standards do not conflict with standards lawfully established within a particular municipality for a gas distribution utility.

§7.45 therefore applies of its own force only **in unincorporated areas**. Inside a city it becomes part of the utility's tariff, and city standards override it. The deposit rules are in §7.45(5): a deposit may not exceed one-sixth of estimated annual billings, interest is "according to the rate as established by law", and the deposit is waived for victims of family violence.

**The express exception is the elderly-delay subparagraph, §7.45(2)(E)(ii)(II):**
> Utility--A gas utility or municipally owned utility, as defined in Texas Utilities Code, §§ 101.003(7), 101.003(8), and 121.001 - 121.006.

So municipally owned utilities are named only in the elderly-delay rule, and that rule mirrors Utilities Code ch. 182, which binds them by statute anyway.

**§7.460 (extreme-weather disconnection) applicability**
> This rule applies to gas utilities, as defined in Texas Utilities Code, § 101.003(7) and § 121.001 ... within the jurisdiction of the Railroad Commission pursuant to Texas Utilities Code, § 102.001.

Its statutory source, **Utilities Code §104.258(a)(2)**, defines "provider" as "a gas utility, as defined by Sections 101.003 and 121.001". §121.001 does not obviously reach a city either. §121.001(b): "In this subchapter, 'person' means an individual, company, limited liability company, or private corporation". The text therefore does not bind a municipal system to the freeze rule. A municipal system may adopt the rule voluntarily.

**Utilities Code §104.351(2)** (master-meter disconnect notice to cities) also expressly excludes municipally owned utilities: "'Gas utility' has the meaning assigned by Section 181.021 but does not include a municipally owned utility ..."

**Model consequence.** Every rule must carry its **regulated-entity applicability**: GURA gas utility, municipally owned utility, any operator, or any "utility" public or private. This is separate from geography. For a municipal system, rate authority is the owning city's governing body for every premise, inside or outside city limits. The inside/outside fact still matters because only ratepayers outside the city have the §103.053 appeal right, and because the outside group is counted to set the petition threshold.

## 2. "Environs"

The word does **not** appear in the GURA statute (checked chs. 101-105) or in PURA ch. 33 or Water Code ch. 13. It is an RRC rule term.

**16 TAC §7.115(14)**
> Environs rates--Residential and commercial rates for a gas utility applicable to natural gas sales and service in unincorporated areas adjacent to or near incorporated cities and towns, aside from special rates as defined in this section.

**§7.115(33)**
> Special rates--Residential and commercial rates for a gas utility applicable to natural gas sales and service established pursuant to Commission orders applicable only to service by a given utility within a specified area and not specifically keyed to the rates charged in any incorporated area.

**16 TAC §7.220(a)(1)** — https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-220
> The environs rates may be the same rates as those in effect in the nearest incorporated area in Texas served by the same utility where gas is obtained from at least one common pipeline supplier or transmission system. The Commission, on application by a utility, on complaint by any affected person, or on its own motion may review the rate in or boundaries of a given environs area and may consent to or order an adjustment where appropriate.

§7.220(a)(2): quality-of-service rules in Subch. D "shall apply to environs areas and become part of environs rates regardless of whether the same quality of service rules are in effect in the related incorporated areas."

§7.220(b)(1) gives the required statement-of-intent wording for an environs rate tied to a city: "... Any rate changes pursuant to this Statement of Intent will not become effective until identical changes have become effective within the City of ____." Rate schedules must state: "Effective on the latter of ____ or such other date as new rates become effective in the City of ____."

**16 TAC §7.315(c)(2)**: each tariff names "the full name of the customer or city, area, or environs that will be affected by the tariff". §7.315(d)(1)(B) requires "the current service charges in the city, environs, or other area affected by the tariff filing".

- **Unit:** an environs area is a utility-specific, RRC-recognized unincorporated area tied to a "related incorporated area". Its boundaries can be reviewed and adjusted by the RRC.
- **Membership:** set by the utility's RRC tariff and service-area description. There is no statewide map.
- **Change:** by RRC order or tariff filing. Under §7.245 rates are prospective from the order date. An environs rate may become effective on the same date as the related city rate.
- **Municipal systems:** this does not apply. A municipal system's outside-city customers have the §103.053 appeal instead.

## 3. Annexation (Local Government Code ch. 42-43)

- **Unit:** municipal corporate limits ("full-purpose" boundary). LGC ch. 43 also recognizes **limited-purpose** annexation (Subch. F). §43.130(c): "The municipality may not impose a tax on any property in an area annexed for limited purposes or on any resident of the area for an activity occurring in the area." Whether limited-purpose territory is "within the municipality" for GURA §103.001 / §102.001 was **not resolved** in primary text.
- **Mechanism:** annexation is by **ordinance**, adopted after the consent, petition or election steps:
  - §43.0671: owner request.
  - §43.0686(c) and §43.0697(c): "holding a final public hearing ... at which the ordinance annexing the area may be adopted".
  - Ch. 43 has no general rule fixing the effective date. The ordinance states its own date; ch. 43 refers throughout to "the effective date of the annexation".
- **Durability:** §43.901 makes an annexation ordinance conclusively presumed valid after two years with no challenge. Disannexation exists (§§43.141-.148). §43.148 requires refunds of property taxes and fees collected during the period the area was annexed.
- **Gas service is not a "municipal service" that must follow annexation.** §43.056(c): "'full municipal services' means services provided by the annexing municipality within its full-purpose boundaries, including water and wastewater services and excluding gas or electrical service."
- **Effect on rate jurisdiction (non-municipal gas utility):** this follows from §102.001 and §103.001. On the effective date the premise moves from RRC original jurisdiction ("areas outside a municipality") to city original jurisdiction ("within the municipality"). It also leaves any environs tariff. No statute was found that sets a separate utility-rate transition date. Treat the switch as keyed to the ordinance effective date and the tariff that applies in the city.
- **Effect on the franchise / right-of-way charge:** Tax Code §182.025 and §182.021 key on "within an incorporated city or town". Membership moves on the effective date of annexation. The charge may be collected only if the franchise covers the new territory, and the utility's own tariff decides when it starts billing. No primary text was found that fixes a lag.
- **Effect on municipal sales tax: lagged, under the Comptroller's notice rule.** Tax Code §321.102(c):
  > If a municipality in which the tax imposed under this chapter is in effect changes its boundaries, the municipal secretary shall send ... to the comptroller a certified copy of the ordinance that adds or detaches municipal territory and that shows the effective date of the boundary change. The ordinance must be accompanied by a map clearly showing the added or detached territory. Except as provided by Subsection (d), the tax takes effect in the added territory or is inapplicable to the detached territory on the first day of the first calendar quarter after the comptroller receives the ordinance and map.

  §321.102(d) allows a further quarter if the Comptroller asks for more time within 10 days. §321.3025 covers tax collected in added territory before the effective date.

  **So one annexation produces at least two effective dates on the same premise:** the boundary date (rate jurisdiction and franchise) and the sales-tax date (always the first day of a quarter, after Comptroller receipt).
- **ETJ** (LGC ch. 42): §42.021 sets ETJ width by population. Since 2023 there is release by petition or election (Subch. D-E, SB 2038). GURA does not key on ETJ; it keys on inside or outside a municipality. §42.902 restricts imposing tax in the ETJ. ETJ is relevant only as the area from which annexation can come (§43.014) and for city regulations, not for gas rates.

## 4. Municipal franchise / right-of-way charges for gas

The task's guess of Utilities Code §121.211 is **not** a franchise fee. That section is the RRC pipeline-safety fee (item 6). LGC ch. 283 covers telecom rights-of-way (title: "Management of Public Right-of-Way Used by Telecommunications Provider in Municipality"). Neither applies here.

**GURA §103.002** (UT.103.htm#103.002)
> (a) This subtitle does not restrict the rights and powers of a municipality to grant or refuse a franchise to use the streets and alleys in the municipality or to make a statutory charge for that use.

**Tax Code §182.025** (TX.182.htm#182.025)
> (a) An incorporated city or town may make a reasonable lawful charge for the use of a city street, alley, or public way by a public utility in the course of its business. (b) The total charges, however designated or measured, may not exceed two percent of the gross receipts of the public utility for the sale of gas or water within the city. ... (e)(3) "Public utility" means: (A) a person who owns or operates a gas or water works or water plant used for local sale and distribution located within an incorporated city or town in this state ...

Read literally, §182.025 sets a 2% cap on charges for street use. Many franchises charge more. §182.026(b)(2) says the subchapter does not "impair or alter a provision of a contract, agreement, or franchise made between a city and a public utility company relating to a payment made to the city". How the cap and existing franchises interact was **not resolved** here.

**Tax Code §182.022: state gas/water/electric gross receipts tax**, keyed on city population band:
> (a) A tax is imposed on each utility company that makes a sale to an ultimate consumer in an incorporated city or town having a population of more than 1,000, according to the last federal census next preceding the filing of the report. (b) ... .581 percent ... more than 1,000 but less than 2,500 ...; 1.07 percent ... 2,500 or more but less than 10,000 ...; 1.997 percent ... 10,000 or more ...

**§182.026(a)**
> This subchapter does not apply to a utility company owned and operated by a city, town, county, water improvement district, or conservation district.

So a municipal gas system pays **neither** the state gross receipts tax **nor** a §182.025 street charge to itself. If it serves inside *another* city, that other city's franchise or street charge can apply. Municipal systems commonly make PILOT or general-fund transfers instead; §104.203 limits PILOT recovery from school and hospital districts.

**Utilities Code §121.2025** limits city charges on gas *pipeline* facilities to cost-based charges, appealable to the RRC. 16 TAC Subch. F (§§7.6001-.6007) covers those appeals. That is distinct from distribution franchises; see Tax Code §182.025 carve-in.

- **Unit:** incorporated city limits, plus the city's population as of the last federal census for the §182.022 band.
- **Membership:** inside or outside city limits by address. Population band per census.
- **Change:** annexation ordinance effective date; a new decennial census changes the band.
- **Publisher:** the city (ordinance and boundary maps). There is no state boundary file for franchise purposes.
- **How customers are charged:** the line item appears per the tariff. §7.315(d)(1)(A) requires tariffs to list "franchise fees" among the adjustments.

## 5. Sales tax on gas

**State, Tax Code §151.317** (TX.151.htm#151.317)
> (a) ... gas and electricity are exempted from the taxes imposed by this chapter when sold for: (1) residential use; ... (b) The sale ... of gas and electricity sold for the uses listed in Subsection (a), are exempted from the taxes imposed by a municipality under Chapter 321 except as provided by Sections 151.359(j) and 321.105. (c) In this section, "residential use" means use: (1) in a family dwelling or in a multifamily apartment ... occupied as a home or residence when the use is by the owner ...; or (2) ... by a tenant who occupies the dwelling ... under a contract for an express initial term for longer than 29 consecutive days. ... (e) Natural gas or electricity used during a regular monthly billing period for both exempt and taxable purposes under a single meter is totally exempt or taxable based on the predominant use of the natural gas or electricity measured by that meter.

Commercial gas is taxable at the state rate plus local rates unless another §151.317(a) use applies, such as manufacturing or agriculture. Exemption is determined per meter per billing period by predominant use.

**Municipal local tax on residential gas, Tax Code §321.105**
> (a) There are exempted from the taxes imposed by a municipality under this chapter the sale ... of gas and electricity for residential use in any municipality that: (1) adopted the tax on or after October 1, 1979; or (2) adopted the tax before that time but: (A) failed to exempt the residential use of gas and electricity before May 1, 1979; and (B) has not reimposed the tax as provided by Subsection (c). ... (c) [a pre-May 1, 1979 city with the exemption] may reimpose the taxes on gas and electricity for residential use by ordinance ... (e) The exemption or reimposition ... takes effect within the municipality as provided by Section 321.104(a) after receipt of a copy of the ordinance.

**§321.201(a)**: "If the municipality imposes the tax on gas and electricity for residential use, only the municipal tax is added to the sales price of sales of gas and electricity for residential use." For residential gas in a taxing city, the tax is the city rate alone, with no state, county, transit or SPD tax, except for the two SPD types below.

**§321.203(f)**: "The sale of natural gas and electricity is consummated at the point of delivery to the consumer." This is the premise. County ch. 323 has the same rule at §323.203(f).

**SPDs, Tax Code §321.1055** (eff. 1/1/2010): a fire control/EMS district (LGC ch. 344, tax under §321.106) or a crime control and prevention district (LGC ch. 363, tax under §321.108) located in a city that taxes residential gas may impose the tax on residential gas "within the district". The district must send its order **and "a copy of the district's boundaries to each gas and electric company whose customers are subject to the tax"** (§321.1055(c)(2)). Under (d), if the city stops taxing, the district may not tax.

**34 TAC §3.334(k)(8), (l)(1)** (Comptroller rule) — https://www.law.cornell.edu/regulations/texas/34-Tex-Admin-Code-SS-3-334
> (8) Natural gas and electricity. Any local city and special purpose taxes due are based upon the location where the natural gas or electricity is delivered to the purchaser. ... residential use of natural gas and electricity is exempt from all county sales and use taxes and all transit authority sales and use taxes, most special purpose district sales and use taxes, and many city sales and use taxes. ...
> (l)(1)(A) ... Counties, transit authorities, and most special purpose districts are not authorized to impose sales and use tax on the residential use of natural gas and electricity. Pursuant to Tax Code, § 321.105, any city that adopted a local sales and use tax effective October 1, 1979, or later is prohibited from imposing tax on the residential use of natural gas and electricity.

**Comptroller lists** (authoritative publisher):
- Policy page: https://comptroller.texas.gov/taxes/sales/utility/
- Cities that impose the tax, with column "Retained prior to 05/01/79 or reimposition date": https://comptroller.texas.gov/taxes/sales/utility/cities.php
- Cities eligible but not imposing: https://comptroller.texas.gov/taxes/sales/utility/cities-eligible.php. The page says "Any city not included on either list is not eligible to impose the tax."
- SPDs levying, with columns "Associated Municipality", "Type of Boundary" (all "Citywide" today) and "Effective Date": https://comptroller.texas.gov/taxes/sales/utility/spd-levy.php

**Stacking (commercial and other taxable gas):** state 6.25% (rate not re-verified here), plus city, county, transit authority (MTA/CTD/RTA) and one or more SPDs. Under §321.102(e)-(h) a local entity's rate is automatically reduced when overlapping local taxes would exceed 2%; transit authorities are excluded from that reduction.
- Comptroller address-based tools: the Sales Tax Rate Locator, https://mycpa.cpa.state.tx.us/atj/ (from Comptroller press release 2021-06-30). Downloadable address and jurisdiction rate files are "update[d] quarterly to account for new tax jurisdictions and rate changes" (same release, and https://comptroller.texas.gov/taxes/file-pay/edi/sales-tax-rates.php).
- **Effective dates are always quarter starts:**
  - §321.102(a): new city tax or rate change takes effect on the first day of the quarter after one full quarter following Comptroller notice.
  - §321.102(b): the additional municipal tax takes effect October 1.
  - §323.102: county taxes take effect October 1 (except crime control and ch. 326/383 taxes).
  - Boundary changes follow the rule in item 3.
- **Membership is by delivery-point address against Comptroller jurisdiction boundaries.** For the two SPD types the district boundary is mailed to the utility.

## 6. Gas utility pipeline tax (Utilities Code ch. 122) and RRC pipeline-safety fee

**§122.051**: "(a) A tax is imposed on each gas utility. (b) The gas utility tax is imposed at the rate of one-half of one percent of the gross income of the gas utility." §122.001(1) limits the "gas utility" here to **§121.001(a)(2)** pipelines: eminent-domain or similar pipelines, "whether for public hire or not". A deduction for gas purchase, treating, storage and transport costs applies under §122.052.

**16 TAC §7.351(d)(2)** excludes: "revenues received from burnertip sales by a gas utility engaged solely in retail gas distribution". A pure distribution LDC, and certainly a municipal system, generally owes nothing on retail sales. The tax is a cost of service; it is not a customer-level line keyed to place. No statute requiring a separate pass-through line was found.

**Pipeline-safety fee, §121.211(d),(g)**: up to $1 per service line per year. It is recovered "as a surcharge to its existing rates". Per (g), for investor-owned and cooperative systems the surcharge is excluded from franchise-fee and gross-receipts bases, and it "[is] not subject to a sales and use tax". This is system-wide, not place-keyed. It is listed because it is a statutory surcharge whose exclusion from tax and franchise bases the billing engine must honor.

## 7. Special districts (Water Code ch. 54 MUDs)

**Water Code §54.201(b)** lists MUD purposes: water supply, wastewater, drainage, irrigation, land elevation, navigation, parks. Gas is not among them. The only gas mention in WA ch. 49 (general district law) is a reference to gas utilities as third parties (line on gas utilities and pipeline owners). **No MUD gas-service power and no district-level gas rule was found.**

The districts that do matter for gas billing are the **sales-tax SPDs**: fire control/EMS and crime control districts (item 5), plus, for commercial gas, any SPD sales tax such as hospital, library, ESD or MDD as listed by the Comptroller. MUDs can also be annexed (LGC §§43.071-.075), which changes city membership.

## 8. Time zones

**49 CFR §71.7(e)** — https://www.ecfr.gov/current/title-49/part-71/section-71.7 (fetched via eCFR API)
> Oklahoma-Texas-New Mexico. From the junction of the Kansas-Colorado boundary with the northern boundary of the State of Oklahoma westerly along the Colorado-Oklahoma boundary to the northwest corner of the State of Oklahoma; thence southerly along the west boundary of the State of Oklahoma and the west boundary of the State of Texas to the southeast corner of the State of New Mexico; thence westerly along the Texas-New Mexico boundary to the east line of Hudspeth County, Tex.; thence southerly along the east line of Hudspeth County, Tex., to the boundary between the United States and Mexico.

**§71.8**: the mountain zone "includes that part of the United States that is west of the boundary line ... described in § 71.7". **§71.7(g)**: "All municipalities located upon the zone boundary line described in this section are in the mountain standard time zone, except Murdo, S. Dak."

So **El Paso and Hudspeth counties are Mountain; the rest of Texas is Central.**
- **Authority:** US DOT under the Uniform Time Act, 15 U.S.C. 260-267. Changes are by DOT rulemaking published in the Federal Register.
- **Unit:** county, as the regulation describes it. Store the zone as an IANA tz id. `America/Denver` covers the El Paso area; the tz database has no El-Paso-specific zone.
- **Billing use:**
  - due dates
  - "weekend day" in §104.258(b)
  - the weather-emergency day in §104.258(a)(1)
  - meter-read cutoffs

## 9. Weather zones / weather normalization

- No statewide RRC weather-zone map was found. Weather normalization adjustments (WNA) are **tariff items**. 16 TAC §7.315(d)(1)(A) requires rate schedules to include "all adjustments to the base rates, including but not limited to late payment charges, gas cost adjustments, purchased gas adjustments, prompt payment provisions, franchise fees, authorized rate case expense surcharges, and weather normalization adjustments."
- Any weather station or zone a WNA uses is set in the individual utility's tariff, keyed to "city, environs, or other area" (§7.315(c)(2)). For a municipal system it is set by the city's own ordinance.
- **The one geographic weather key in rule is the extreme-weather disconnect freeze.** 16 TAC §7.460(b)(1):
  > An extreme weather emergency means a day when the previous day's highest temperature did not exceed 32 degrees Fahrenheit and the temperature is predicted to remain at or below that level for the next 24 hours according to the nearest National Weather Station for the county where the customer takes service.

  The statute, §104.258(a)(1), says only "according to the nearest National Weather Service reports". The rule adds **county** as the key. On applicability to municipal systems, see item 1; on its face it does not bind them.

## 10. Other place-keyed rules found

| Rule | Unit it keys on | Applies to |
|---|---|---|
| Utilities Code §104.103(a)(1): rate-increase notice "in a newspaper having general circulation in each county containing territory affected by the proposed increase"; (b) allows bill or mail notice instead | county | GURA gas utilities |
| §104.102-.105 hearings: "notice to the governing body of each affected municipality and county" (§104.105(c)) | municipality, county | GURA gas utilities |
| §104.006: 115% cap vs. average of the same utility's city rates "in the same county" | county + municipalities | GURA gas utilities |
| §104.352 / 16 TAC §7.475: 10-day notice to the **municipality** before disconnecting a nonsubmetered master-metered multifamily property "located in the municipality", if the city registered a representative | municipality | GURA gas utilities only (§104.351(2) excludes municipally owned) |
| §104.112 relocation surcharge ("customers in the service area where the relocation occurred") | utility service area / rate area | GURA gas utilities |
| LGC §552.0025(g),(h): municipal utility lien recorded in county real property records | county (of the parcel) | municipal systems |
| Utilities Code ch. 182 Subch. C, meter testing on complaint to the municipality | municipality; §182.101(5) "a person, other than a governmental entity, who provides ... gas for consumption in a municipality" | non-government utilities in a city |
| Utilities Code ch. 183, deposit interest at the rate set yearly by the PUC (§183.003) | statewide | §183.001(2) "a person, firm, company, corporation, receiver, or trustee who furnishes ... gas"; applicability to cities **not resolved** |
| §103.052: resident petition appeal ("qualified voters of the municipality") | municipality | city-regulated GURA utilities |
| Comparable outside-city appeal rights for municipal *electric* (PURA §33.101-.102, with a duty to disclose the count and list of outside ratepayers) and *water/sewer* (Water Code §13.043(b)(3); outside ratepayers "a separate class") | inside/outside the owning city | relevant for a multi-commodity design |

---

## What a places model must hold

Units. Each needs an id, a type, a jurisdiction-specific code, and validity in time (`valid_from`/`valid_to`):
1. **State.** Selects the whole rule family: GURA/RRC versus another state's PUC.
2. **County.** Uses:
   - time zone (49 CFR 71)
   - extreme-weather station selection (16 TAC §7.460)
   - rate-increase newspaper notice (§104.103)
   - the 115% outside-city cap (§104.006)
   - county sales tax
   - lien recording (LGC §552.0025)
3. **Municipality (incorporated city or town), full-purpose limits.** Uses:
   - rate-jurisdiction holder for non-municipal utilities
   - franchise and street charge (Tax §182.025)
   - state gross receipts band (Tax §182.022, needs **census population**)
   - city sales tax and **residential-gas taxability flag with effective date** (Tax §321.105; Comptroller list)
   - master-meter disconnect notice
   - for a municipal system, the **owning city** (inside versus outside, which drives the §103.053 appeal class)
4. **Limited-purpose annexed area.** A distinct status, because city taxes are barred there (LGC §43.130). Its GURA treatment is unresolved.
5. **ETJ.** Optional. It has no gas-rate effect, but it is the source of most annexations.
6. **Environs area / tariff rate area.** Utility-specific and RRC-tariffed, linked to a "related incorporated area" (16 TAC §§7.115, 7.220, 7.315). Generalize this as a **utility rate area**. A municipal system has its own inside and outside rate areas set by ordinance.
7. **Sales-tax jurisdictions as published by the Comptroller:**
   - city
   - county
   - transit authority (MTA/CTD/RTA)
   - SPDs, each with type, because fire control/EMS and crime control districts may tax residential gas and others may not
   - Each with: rate history at quarter-start dates, residential-gas flag and date, and the Comptroller jurisdiction code. Membership is resolved by delivery-point address using the Comptroller locator or quarterly address file.
8. **Time zone.** IANA id; Texas derives it from county.
9. **Weather reference.** Two kinds:
   - the NWS station "nearest ... for the county" (disconnect freeze)
   - the tariff's WNA station or zone, if any

Facts per premise:
- **service delivery point** (address and geocode). Taxes key on "point of delivery to the consumer" (Tax §321.203(f)).
- membership rows in each unit, with **effective-from/to dates and the source** of each:
  - ordinance number and date
  - Comptroller quarter date
  - RRC order or tariff
  - census
- per-meter **use classification by billing period** (residential as defined in Tax §151.317(c); predominant use under §151.317(e))

Facts per unit, as time-versioned rows:
- city: rate-jurisdiction status (retained or surrendered to the RRC, §103.003, by ordinance or election date)
- city: franchise agreement and percentage
- city: census population band
- city: residential-gas tax status and date
- SPD: boundary type ("Citywide" or partial) and associated municipality

Facts per utility:
- entity type (GURA gas utility, municipally owned utility, or cooperative). This drives rule applicability (items 1, 4, 6, 10).
- owning municipality, if municipally owned

**Several effective dates per event.** One annexation produces:
- the boundary date (ordinance), which drives rate jurisdiction, franchise and limited-purpose status
- the sales-tax date (first day of a quarter after Comptroller receipt, possibly one quarter later), which drives city tax

Store both. Never derive one from the other.

Overlap and precedence:
- A premise sits in many units at once: state, county, at most one city, at most one transit authority, possibly several SPDs, one rate area and one time zone.
- Rate jurisdiction (non-municipal utility): city if inside and not surrendered; otherwise the RRC.
- Rate authority (municipal system): always the owning city's governing body. Outside-city ratepayers have an RRC appeal right.
- Sales tax on residential gas: only a pre-1979 city that taxes it, plus that city's fire/crime SPDs.
- Sales tax on other gas: all applicable levels stack, subject to the 2% local cap and the automatic-reduction rule (§321.102(e)-(h)).

## Could not verify

- Whether Utilities Code ch. 183 (deposit interest) binds municipally owned utilities. §183.001(2) lists "person, firm, company, corporation" and is silent on municipalities. No AG opinion was checked.
- Whether limited-purpose annexed territory counts as "within the municipality" for GURA §§102.001 and 103.001.
- Whether any statute fixes when a utility must start charging a city's franchise fee after annexation, beyond the ordinance and franchise themselves.
- How the Tax Code §182.025 2% cap interacts with franchise agreements that set a higher percentage. §182.026(b)(2) suggests contracts control; not resolved.
- What 2019 HB 2263 Sec. 4 (eff. 1/1/2024) changed in Tax Code §182.022. The current text still taxes gas utility companies in cities over 1,000; the amendment history was not read.
- The current state sales tax rate (6.25%) and the exact Comptroller address-file schema and download URL. Only the press release and landing page were seen; the files were not downloaded.
- Whether any Texas statute or rule applies an extreme-weather disconnect ban to municipally owned gas systems. None was found; §104.258 and 16 TAC §7.460 reach only GURA and ch. 121 gas utilities.
- Whether the LII copy of 16 TAC ch. 7 is current to the Texas Register. LII updates quarterly; the SOS TAC viewer was not checked. LII also lists no Subchapter A for ch. 7.
- Unofficial Mountain time observance outside El Paso and Hudspeth (e.g., parts of Culberson County). Under 49 CFR 71 only those two counties are Mountain; local practice was not checked.
- Justia was not used. No Attorney General opinions or court cases were read, so all conclusions rest on statutory and rule text alone.
