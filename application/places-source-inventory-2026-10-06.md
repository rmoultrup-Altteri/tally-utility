# Places source inventory

**Date:** 2026-10-06.
**Purpose:** the spec for the places and applicability foundation (rule-terms v2 §9 and §12 step 1; audit §4 step 2). It lists every real source that decides which law applies to a customer, and the unit each one keys on. The places patch is drafted against this list, and reviewers check the draft against it.

**Sources:**
- `places-sources/texas.md`: Texas, from primary texts (statutes.capitol.texas.gov, 16 TAC via Cornell LII, Comptroller, 49 CFR 71).
- `places-sources/utility-type-10-states.md`: who each state's gas customer law applies to, across OK, LA, NM, AR, KS, OH, IL, NY, CA and GA.
- `places-sources/our-sources.md`: every place-like column in `tu.sql`, the 2026-09-22 shared-places note (gas-billing-memory) and audit §3.1.

The main session spot-checked the key quotes against the saved texts: Utilities Code §101.003(7), §102.002 and LGC §552.0025(c) for Texas; the utility-type agent checked LA 45:850, NM 27-6-13, IL 11-117-12.1 and KS 66-104(b). Each report lists what it could not verify.

## 1. The headline findings

**1. Texas's gas law does not reach a city-owned gas system** (answers Kyle question K10).
- Utilities Code §101.003(7): "'Gas utility' … does not include: (A) a municipal corporation".
- §102.002: the Act does not let the Railroad Commission "regulate or supervise a rate or service of a municipally owned utility".
- 16 TAC ch. 7 takes its "gas utility" definition from the Act (§7.115(18)), and §7.45 applies by its own force "in unincorporated areas".
- Municipal deposits: LGC §552.0025(c), "A municipality may require varying utility deposits for customers as it deems appropriate in each case."
- The city council sets the rates for every premise, inside or outside the city (LGC §552.001-.002). The Commission's only hook is the outside-city ratepayers' appeal (Utilities Code §103.053).
- **Consequence:** for our first customers, deposit, disconnection and most customer-service policy is the **city's own**, recorded as the utility's tariff rows under rule-terms v2. It is not a state law row. The Texas §7.45 rows apply to investor-owned gas utilities. Decision tables #53–55 describe a policy a city may adopt, which is a useful default, not law.

**2. Across 10 states, municipal systems are outside the commission's customer rules in 9.** New York is the exception: its municipal gas systems fall under the Public Service Law (HEFPA) and 16 NYCRR Parts 11 and 13.
- Louisiana and New Mexico municipals can opt in by election.
- Six states bind municipal systems by **specific statutes** (verified):
  - KS 12-822 (deposit interest, a separate account) and 12-808c (a 3-month deposit cap);
  - IL 11-117-12.1 (no shutoff at or below 20 °F);
  - NM LIUAA winter rules and a "reasonable" deposit;
  - OK §35-107 (deposit refund and forfeiture);
  - CA PUC Div. 5 (deposit cap, notices, appeals);
  - NY HEFPA.
- So "municipal" does not mean "no state law". It means a different, smaller set of state law.

**3. The applicability key needs more than "municipal or not".**
- Ownership comes in at least seven kinds: municipal, county or other political subdivision, typed special district or authority, investor-owned, cooperative, piped propane, master-meter.
- Commission-jurisdiction status is a separate, **dated** fact, because elections change it without changing ownership.
- Some laws key on ownership even after an opt-in (LA 45:850).
- Some key on where the premise is relative to the city (KS 3 miles, NM 5 miles).
- Some key on size (KS ≤100 customers, NY <20).
- Some apply only if a local body adopts them (IL 305 ILCS 20/13).

**Correction to the deposits survey:** Louisiana's 5% deposit interest (R.S. 45:848) does not bind municipal systems. R.S. 45:850 excludes plants "owned by any municipality or political subdivision". The survey now carries a correction note.

## 2. The requirements, classified

**Place kind** = a unit a premise belongs to. **Key** = a dimension on law and tariff rows. **Utility fact / Premise fact / Unit fact** = a dated fact held about the utility, the premise or the place. **Out** = stated, not modelled now.

| # | Requirement | Source | Class |
|---|---|---|---|
| P1 | State | Every rule family | Place kind (validated code) |
| P2 | County: time zone (TX), the weather station for the freeze rule, rate-increase notice, the 115% outside-city cap, county sales tax | TX §104.103, §104.006, 16 TAC §7.460, 49 CFR 71 | Place kind |
| P3 | City, full-purpose limits: rate jurisdiction for non-municipal utilities, franchise and street charge (Tax §182.025, 2% cap for gas), census population band, city sales tax and residential-gas taxability | TX Utilities Code §§102–103, Tax §§182.022–.025, §321.105 | Place kind, with unit facts |
| P4 | Limited-purpose annexed area: city taxes barred; gas-rate treatment unresolved | LGC §43.130 | Place kind (status); open |
| P5 | Extraterritorial jurisdiction: no gas-rate effect; where most annexations come from | LGC ch. 42 | Place kind, optional |
| P6 | Utility rate area: "environs" for investor-owned utilities, tied to a related incorporated area; inside and outside rate areas for a city system | 16 TAC §§7.115, 7.220, 7.315; city ordinance | Place kind, utility-owned (tenant) |
| P7 | Sales-tax jurisdictions as the Comptroller publishes them: city, county, transit authority, special-purpose districts by type (only fire-control and crime-control districts may tax residential gas) | Tax §§151.317, 321.105, 321.203(f); Comptroller | Place kinds (tax axis, kept separate per R-26), with rate history at quarter-start dates |
| P8 | Time zone, as an IANA id; in Texas from the county (El Paso and Hudspeth are Mountain) | 49 CFR 71.7(e) | Unit fact of a county or place |
| P9 | Weather reference: the National Weather Service station for the county (freeze rule); the tariff's weather-normalization zone | 16 TAC §7.460; tariff | Unit fact (law); utility-owned zone (existing `wna_zones`) |
| P10 | Premise relative to a municipal boundary (inside; outside within N miles) | KS 66-104f; NM 3-25-3; TX §103.053 appeal class | Premise fact, derived from place membership plus distance where the law needs it |
| A1 | Owner type (≥7 kinds) | utility-type report, dimension 1 | Utility fact, dated; **key** on law rows |
| A2 | Commission-jurisdiction status (in or out, by election or relinquishment), separate from owner type | LA 45:1164.2, 33:4491; NM 62-6-5; KS 66-104e; GA | Utility fact, dated; **key** |
| A3 | Size thresholds (customer counts, population) | KS 66-104c; NY §66(13); CA §4452 | Parameters in `terms`; the count is a utility fact |
| A4 | Local opt-in adoption | IL 305 ILCS 20/13(k) | Unit fact (the city adopted it, dated) |
| A5 | Regulator or enforcing body per rule set (commission, city council, the utility's own board as appeal forum, a human-services agency, pipeline safety) | utility-type report, dimension 6 | Attribute of the law row's rule set (`terms` or `source_note`), not free text on rate items |
| A6 | Customer class and attributes: residential or not (per meter per period in TX tax), heating source, master-metered, service member, family violence | Tax §151.317(c),(e); IL 8-205; CA §10009.1; IL 11-117-12.2 | Existing class rows plus customer and meter facts |
| A7 | Retail role in unbundled markets (distribution company, marketer) | GA Art. 5 | **Out** (stated; no customer of ours is a marketer) |
| D1 | Several effective dates per event: an annexation has a boundary date (rate jurisdiction, franchise) and a sales-tax date (the first day of a quarter after the Comptroller receives it) | LGC ch. 43; Tax §321.102(c)-(d) | Membership rows carry their own dates **per axis**; never derive one from another |
| D2 | Evidence for each membership: ordinance number and date, Comptroller quarter, RRC order, census | Texas report, "facts per premise" | Source columns on membership rows |
| D3 | A premise is in many units at once (state, county, ≤1 city, ≤1 transit authority, several districts, one rate area, one time zone) | Texas report, "overlap" | Many-to-many dated membership, with per-kind cardinality |

## 3. What our schema has today (from `our-sources.md`)

- `service_locations` stores city, county and state as free text, `inside_city_limits` (default **true**) and a free-text `franchise_city`. None of it is dated, so an annexation rewrites history.
- `jurisdictions` is per tenant, mixing the place's identity with the utility's weather-normalization settings (the 2026-09-22 note).
- `franchise_fee_rules` names its city by text.
- The regulator is free text on rate items.
- There is no tax-jurisdiction table (the A-8 gap).
- `America/Chicago` is hard-coded (tu.sql 19184).
- Law tables key on `state_code` only.

## 4. What this means for the design (to draft from)

1. **Platform `places`:** shared, no tenant. Fields: kind (P1–P5, P7), a jurisdiction-specific code, name, parent, validity dates, and source. Unit facts (P3, P8, P9, A4) are dated rows on a place, each cited.
2. **Dated membership of a premise in places:** many-to-many, with per-kind cardinality (D3), dates per axis (D1) and evidence (D2). The regulatory and tax axes are separate (R-26).
3. **Utility facts, dated:** owner type (A1), commission-jurisdiction status (A2), the owning place for a municipal system, and the customer count (A3).
4. **Law and tariff rows gain owner type and jurisdiction status as key columns** (rule-terms v2 §9). Their lookup resolves a premise to (state, place memberships, the utility's owner type and status, class) on the date, and refuses when nothing is in force.
5. **`jurisdictions` keeps the utility's own settings** (weather-normalization zone) and points at a place (the 2026-09-22 shape). Utility rate areas (P6) are tenant rows linked to places.
6. **Time zone comes from the premise's place;** `America/Chicago` goes.
7. **Out of scope, stated:** A7 (marketers), address geocoding and boundary maps (membership is recorded with its evidence; how the utility determined it is outside the schema), and P4's unresolved gas-rate treatment.

## 5. For Kyle

- **K10 (answered from the statute, to confirm against practice).** Texas's gas-utility law does not reach city-owned systems. Do Texas cities commonly adopt §7.45's deposit, interest and refund terms by ordinance anyway? And does Utilities Code ch. 183 (deposit interest) bind a city? §183.001(2) lists "person, firm, company, corporation" and is silent on municipalities.
- **K11.** For our first customers, which customer-service policies are written in the city's ordinance, and which in a utility policy or tariff? That decides where a municipal utility's rows are cited.
