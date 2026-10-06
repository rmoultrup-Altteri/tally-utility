# Which kinds of gas utility each state's customer-protection law binds (10 states)

Surveyed 2026-10-06 for the law-row applicability key. Texas is surveyed separately and is not covered here.

**How to read the labels**
- **verified:** the operative words were read in primary text, meaning statute, constitution or codified rule, on an official site or Cornell LII.
- **mirror:** read on Justia, onecle or vLex. Arkansas and Georgia statutes are mirror-only.
- **secondary:** taken from a commission page, an annotation or a press release.
- **unverified:** a reading or inference with no text behind it.

Nothing here was filled in from memory.

**Where the sources are**
- Raw fetched texts are under `scratchpad/put/src/` (state prefix), plus `scratchpad/src/` from the deposits survey.
- New York statutes and California leginfo pages were read in a browser because curl was blocked. There are no raw New York files.

**Spot-checks by the compiling session against the cached text**
- La. R.S. 45:850: "Nothing in R.S. 45:845 through 45:849 applies to water, gas or electric power plants owned by any municipality or political subdivision of Louisiana."
- NMSA 27-6-13(A)(2): the definition of "utility" in the Low Income Utility Assistance Act (LIUAA): "a publicly, privately or municipally owned utility or a distribution cooperative utility for the rendition of electric power or gas".
- 65 ILCS 5/11-117-12.1: the 20 °F rule "applies to all municipalities that own or operate a public utility, including home rule units".
- K.S.A. 66-104(b): the 3-mile text.

**Correction to the deposits survey (`application/deposits-source-survey-2026-10-06.md`)**
- That survey left open whether La. R.S. 45:848's 5% deposit interest binds municipal systems.
- It does not. R.S. 45:850 excludes plants "owned by any municipality or political subdivision" from §§845–849.
- The survey should be corrected, and so should the Louisiana entry in the wiki-ingestion log.

---

## Oklahoma — partly verified

Sources (all read in full text this session; raw copies in `put/src/`):
- Oklahoma Statutes, official complete-title RTFs from the Oklahoma Legislature: Title 17 `https://www.oklegislature.gov/OK_Statutes/CompleteTitles/os17.rtf` (`OK_os17.txt`), Title 11 `.../os11.rtf` (`OK_os11.txt`), Title 18, 52, 60, 74 (same pattern). Title 17 shows amendments through Laws 2025, c. 160, so the text is current as of the 2025 session.
- Okla. Const. art. 9 and art. 18, official RTFs `https://www.oklegislature.gov/OKStatutes/CompleteTitles/oc9.rtf` and `oc18.rtf` (`OK_const_art9.txt`, `OK_const_art18.txt`).
- OAC 165:45-1-2 and 165:45-1-4 from Cornell LII, cached earlier in `scratchpad/src/ok1-2.txt` and `ok1-4.txt`. OAC 165:20-1-1 and 165:20-5-2 from Cornell LII (`OK_oac165-20-*.html`).
- oscn.net could not be used: its index pages sit behind a Cloudflare Turnstile challenge.

### 1. Regulated utility definition

**17 O.S. §151(A)(1)** (https://www.oklegislature.gov/OK_Statutes/CompleteTitles/os17.rtf):
> "The term "public utility" as used in Sections 151 through 155 of this title shall be taken to mean and include every corporation, association, company, individuals, their trustees, lessees, or receivers, successors or assigns, except as hereinafter provided, **and except cities, towns, or other bodies politic**, that now or hereafter may own, operate, or manage any plant or equipment, or any part thereof, directly or indirectly, for public use, or may supply any commodity to be furnished to the public: a. for the conveyance of gas by pipeline, b. for the production, transmission, delivery, or furnishing of heat or light with gas, ..."

The same subsection exempts not-for-profit rural water and sewer corporations under 18 O.S. §§851-863 "in any and all respects from the jurisdiction and control of the Corporation Commission". It gives no equivalent gas exemption.

**17 O.S. §152(A)**:
> "The Commission shall have general supervision over all public utilities, with power to fix and establish rates and to prescribe and promulgate rules, requirements and regulations, affecting their services, operation, and the management and conduct of their business"

**Constitution.** The constitution also excludes municipalities at its own level:
- **Okla. Const. art. 9 §1:** "the term "corporation" or "company" shall ... exclude all municipal corporations and public institutions owned or controlled by the State"
- **Art. 9 §18b:** "'Company' shall include ... all corporations except municipal corporations"
- **Art. 9 §34:** "The term "public service corporation" shall include all transportation and transmission companies, all gas, electric, heat, light and power companies, and all persons, firms, corporations ... engaged in said businesses"

**Commission rule scope:**
- **OAC 165:45-1-4(a):** "This Chapter shall apply to the operations of any gas utility ... operating within the State of Oklahoma subject to the jurisdiction of the Commission."
- **OAC 165:45-1-2:** "'Natural gas utility' means a natural gas utility as defined in 17 O.S. § 151 et seq." The same section defines "Consumer" to include a "municipality", but only as a *customer* receiving gas.

**Cooperatives.** 18 O.S. §441-105(b) (Limited Cooperative Association Act): "A limited cooperative association may be organized for any lawful purpose ... except for supplying electric energy or natural gas in rural areas." I found no gas-cooperative enabling act in Title 18. The rural electric cooperative carve-outs in 17 O.S. §158.27 are electric-only.

**Propane / LP.** The Oklahoma Liquefied Petroleum Gas Regulation Act (52 O.S. §420.1 et seq.) creates an LP Gas Administrator and Board. Its sections cover permits, fees, container and inspection safety, and product specifications (§§420.2–420.9). The definitions (§420.1(B)) and the section titles contain nothing on retail customer service, deposits or termination.

**Summary:**
- **Municipal:** OUT, by the express words "except cities, towns, or other bodies politic" in §151 and the constitutional definitions.
- **Municipal public trusts (60 O.S. §176 trusts):** not named in §151. Whether a trust is an "other bod[y] politic" is UNVERIFIED. Several statutes list "a municipal utility, or a public trust which has as its beneficiary the municipality" *alongside*, and distinct from, utilities "subject to the jurisdiction of the Corporation Commission" (17 O.S. §151.1(A) and §161.1(A), the electric/natural-gas resale section).
- **Cooperative:** n.a. for gas. No gas-cooperative act was found, and §441-105 bars limited cooperative associations from rural gas supply.
- **District/authority:** "other bodies politic" are excluded. No gas utility district statute was found.
- **Small-system threshold:** none for gas in §151.
- **Propane/LP:** §151 says "furnishing of heat or light with gas" without limiting it to natural gas. Whether a piped LP distribution system is a §151 "public utility" is UNVERIFIED. Bottled or tank LP retail falls under the LPG Act, which is safety and licensing only.

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

**11 O.S. §35-107**, "Utility deposit — Refund — Notice — Forfeiture — Waiver for domestic violence victims". Municipal-specific and binding. Amended through Laws 2023, c. 171.
- (A): "Money in the municipal treasury which has been acquired as a utility deposit from a customer of a municipal utility shall be refunded or credited to the customer upon termination of the utility service and payment of all charges due and connected with the service, or at an earlier date as may be allowed by the municipality."
- (B): "If a utility deposit is to be refunded ... instead of being credited ..., a refund check or warrant payable to the customer shall be issued by the municipal utility within thirty (30) days following the termination of the utility service."
- (C): checks of "$5.00 or less" that are uncashed after one year are cancelled. The money goes "into the fund of the municipal utility for which the deposit was collected, or into the general fund as may be determined by the municipal governing body."
- (D): for checks over $5.00 that are uncashed after one year, the municipality must send written notice to the last-known address. The deposit is forfeited if the check is not cashed "within ninety (90) days of the date the notice is mailed".
- (E): "notwithstanding other provisions of law, a municipally owned public utility shall waive any initial credit and deposit requirements for a customer or applicant that has been determined to be a victim of domestic violence, stalking, or harassment". Proof is a protective order, a law-enforcement statement, or a certified DV-shelter or program statement. The "certification letter expires after ninety (90) days" and is confidential.

**11 O.S. §35-102.1** (meter deposit investment):
> "The proceeds from any investments of meter deposit funds ... shall be placed in the fund from which the operation and maintenance expenses of the utility ... are paid. The investment of such funds by the municipality shall in no manner impair its obligation ... to refund in full any or all deposits".

This statute imposes no duty to pay interest on municipal deposits.

**17 O.S. §180.12** is the parallel domestic-violence deposit waiver for a "public utility". In context it means a Commission-jurisdictional utility. It adds paragraph 4, tribal domestic-violence programs, which the municipal §35-107(E) does not list.

**60 O.S. §654** (Uniform Unclaimed Property Act): "A deposit ... made by a subscriber with a utility to secure payment ... that remains unclaimed by the owner for more than one (1) year after termination of the services" is presumed abandoned. I did not determine whether §35-107(C)–(D) displaces this for municipal utilities. §35-107 is the specific statute and sends forfeited amounts to municipal funds.

**Searched with no result:**
- I searched Titles 11, 17, 18, 52, 60 and 74 for disconnection, termination, shut-off, cold or extreme weather, medical certificates and temperature. Title 11 has no winter moratorium, medical-certificate rule, notice-before-termination rule or deposit-interest statute for municipal utilities.
- The only termination provision in Title 11 is §22-112.5, which deals with water shutoff for a delinquent sewer account held by another entity. It is not gas.
- 17 O.S. §285 lets a "utility" give delinquent and termination notices orally. It is a direction to the Corporation Commission, so in context it reaches jurisdictional utilities only.

**Commission rules:** OAC 165:45 applies only to utilities "subject to the jurisdiction of the Commission" (165:45-1-4). It therefore does not reach municipal systems.

**Pipeline safety.** This reaches municipal systems for safety only. 52 O.S. §5(A): "The Corporation Commission is hereby authorized ... to promulgate, adopt and enforce reasonable rules establishing minimum state safety standards for the design, construction, maintenance and operation of **all pipelines used for the transmission and distribution of natural gas** in this state." OAC 165:20-1-1 gives the chapter's purpose as "minimum safety standards for the transportation of gas".

### 3. Who governs municipal customer practices instead

The municipal governing body, or the governing board of a municipal public trust.
- **Okla. Const. art. 18 §6:** "Every municipal corporation within this State shall have the right to engage in any business or enterprise which may be engaged in by a person, firm, or corporation by virtue of a franchise from said corporation."
- **11 O.S. §35-107** leaves the timing of early refunds and the disposition of forfeited deposits to "the municipality" and "the municipal governing body".
- **Okla. Const. art. 9 §18** keeps the rights of a city or town "to prescribe rules, regulations, or rates of charges to be observed by any public service corporation ... under a municipal or county franchise ... so far as such services may be wholly within the limits of the city, town, or county granting the franchise". This concerns the city's power over a *franchised private* utility, not over its own system.
- **State agencies:** the Corporation Commission for pipeline safety only (52 O.S. §5). I found no state agency with authority over municipal gas deposits, billing or disconnection beyond the statutory duties in §35-107.

### 4. Other applicability dimensions

**Outside city limits.**
- **11 O.S. §35-101:** a municipality "may extend its lines, mains, and channels ... beyond the corporate limits of the municipality ... and do all other things necessary and proper in carrying on the business outside of the corporate limits of the municipality to the same effect as it may now do within the corporate limits ... and may sell such service to any person, firm or corporation outside of the limits of the municipality."
- I found no statute giving the Corporation Commission jurisdiction over a municipal gas system's customers outside city limits. The §151 exclusion is by owner ("cities, towns, or other bodies politic"), not by location.
- Applicability key: owner type. Location makes no difference for OK municipal gas.

**Rate-regulated vs not.** 74 O.S. §9052(5), the Winter Storm Uri financing act, defines an "Unregulated utility" as "any utility ... or any public trust designated for the benefit of a utility or municipality, which is not a regulated utility subject to the regulatory jurisdiction of the Oklahoma Corporation Commission with respect to its rates, charges and terms and conditions of service". This confirms that the legislature treats municipal and public-trust gas systems as outside the Commission's "terms and conditions of service".

**Customer-count threshold:** none for gas.

**Opt-in election:** none found for gas. The opt-in mechanisms in 17 O.S. §158.27 are for electric cooperatives and member-consumer petitions.

**Other:** the landlord-resale limit in 17 O.S. §161.1 ("electric current or natural gas from a municipality") caps a reseller's markup at 10% of cost. It binds landlords who resell, not the municipal utility.

### Row (one line per utility type)
- `municipal gas system -> 11 O.S. §35-107 deposit refund/forfeiture + DV deposit waiver; 11 O.S. §35-102.1 deposit investment; 52 O.S. §5 / OAC 165:20 pipeline safety; NOT OAC 165:45 (17 O.S. §151 "except cities, towns, or other bodies politic") [verified]`
- `municipal public trust (60 O.S. §176) gas system -> treated as non-OCC-regulated (74 O.S. §9052(5)); whether §35-107 binds a trust rather than "the municipality" is unverified [secondary/unverified]`
- `investor-owned / private gas utility -> OAC 165:45 (incl. 165:45-11 deposits, interest, customer service) under 17 O.S. §§151-152; 17 O.S. §180.12 DV deposit waiver; 17 O.S. §285 oral notices [verified]`
- `cooperative (gas) -> n.a.; no gas-co-op enabling act found; 18 O.S. §441-105 bars LCAs from rural gas supply [verified for LCA bar; absence of other co-op route unverified]`
- `utility district/authority (gas) -> excluded as "other bodies politic" if such exists; no gas district statute found [unverified]`
- `propane/LP retail (tank/cylinder) -> 52 O.S. §420.1 et seq. LP Gas Act (safety/licensing only); no customer-protection rules found [verified for Act scope]`
- `piped LP distribution system (private) -> possibly §151 "furnishing of heat or light with gas" -> OAC 165:45 [unverified]`

### Could not verify
- Whether a municipal public trust (60 O.S. §176) is an "other bod[y] politic" excluded by §151. This needs case law or an AG opinion.
- Whether 11 O.S. §35-107 (written for "municipal utility" and "municipal treasury") binds a public trust that operates the gas system.
- Whether a private piped-propane distribution system is a §151 public utility subject to OAC 165:45.
- Whether 60 O.S. §654 (unclaimed property, one year) or 11 O.S. §35-107 governs uncashed municipal deposit refunds. I believe §35-107 controls as the specific statute, but this is inference.
- OCC pipeline-safety scope was read from 52 O.S. §5 and OAC 165:20-1-1 only. I did not read OAC 165:20-5's adoption of 49 CFR 192 or its operator definition.
- OSCN (oscn.net) was unreachable because of Cloudflare Turnstile. All statute text came from the Legislature's official RTFs instead.


---

## Louisiana — partly verified

Sources fetched (raw files in `put/src/`, prefix `LA_`). Statutes come from legis.la.gov `Law.aspx?d=<id>`. LPSC orders come from lpsc.louisiana.gov and its document portal.

### 1. Regulated utility definition

**Constitution, art. IV §21(B)–(C)** (https://www.legis.la.gov/legis/Law.aspx?d=206438; file `LA_const4-21.txt`):
- (B): "The commission shall regulate all common carriers and public utilities and have such other regulatory authority as provided by law."
- (C) Limitation: "The commission shall have no power to regulate any common carrier or public utility owned, operated, or regulated on the effective date of this constitution by the governing authority of one or more political subdivisions, except by the approval of a majority of the electors voting in an election held for that purpose; however, a political subdivision may reinvest itself with such regulatory power in the manner in which it was surrendered. This Paragraph shall not apply to safety regulations pertaining to the operation of such utilities."

**R.S. 45:1163(A)(1)** (https://www.legis.la.gov/legis/Law.aspx?d=99809): "The commission shall exercise all necessary power and authority over any street railway, gas, electric light, heat, power, waterworks, or other local public utility for the purpose of fixing and regulating the rates charged or to be charged by and service furnished by such public utilities."
- (A)(2) carves out direct sales of natural gas to industrial users for fuel or manufacturing, and to CNG vehicle users.

**R.S. 45:1164** (https://www.legis.la.gov/legis/Law.aspx?d=99813):
- "A. The power, authority, and duties of the commission shall affect and include all matters and things connected with, concerning, and growing out of the service to be given or rendered by such public utility, except in the parish of Orleans."
- "B. The provisions of this Section and R.S. 45:1163 shall not apply to any public utility, the title to which is in the state or any of its political subdivisions or municipalities, unless the electors of such are customers of the public utility have manifested their approval of being under the jurisdiction of the public service commission as is required by Article IV, Section 21(C) ... in the manner provided by R.S. 45:1164.1 through R.S. 45:1164.13."

**R.S. 45:1161(1)** (https://www.legis.la.gov/legis/Law.aspx?d=99803). This definition applies only for §§1168–1175: "'Public utility' means any person, public or private, subject to the general jurisdiction of the commission but not including ... public utilities municipally owned, or operated, or regulated, unless the electors of such municipality, and electors residing outside the municipality, who are customers of the municipally owned utility, have manifested their approval of such jurisdiction ..."

**The general "furnisher" statutes, R.S. 45:845–849.** These include the deposit-interest rule in §848.
- §845 (d=100155) and §848 (d=100158) reach "Every person engaged in the business of furnishing natural or artificial gas" and "any person engaged in furnishing gas, electricity or water".
- **They are expressly excluded for public systems by R.S. 45:850** (https://www.legis.la.gov/legis/Law.aspx?d=100160): "§850. Meters and deposits; law inapplicable to public-owned utilities. Nothing in R.S. 45:845 through 45:849 applies to water, gas or electric power plants owned by any municipality or political subdivision of Louisiana."
- This answers the open question in the prior survey. **§848 (5% deposit interest; return on demand; 10% penalty) does NOT bind municipal or other political-subdivision gas systems.** It binds non-public "furnishers" only.

**Gas utility districts (R.S. 33:4301 et seq.):**
- §4306 (d=90728): "Any gas utility district created pursuant to this Subpart shall be a political subdivision".
- §4305(C) (d=90727): "The board of commissioners shall have the right and power to fix the rates and charges at which it will supply gas distributed by the district and such rates and charges shall not be subject to review or change by any other agency or instrumentality of the state of Louisiana or of any political subdivision therein."
- §4307 (d=90729): "A 'gas public utility' for the purposes of this Sub-part shall consist of a natural gas distribution system or a natural gas transmission and distribution system."

**Summary of the definition by utility type:**
- **Municipal: out.** This holds unless the electors elect LPSC regulation (Const. IV §21(C); R.S. 45:1164(B)). Municipal systems are also out of R.S. 45:845–849 in all cases (R.S. 45:850).
- **Cooperative: n.a. for gas.** No gas-cooperative provision was found. R.S. 45:1163(A)(3)/(B) concern electric cooperatives only.
- **District/authority: out.**
  - Gas utility districts are political subdivisions (33:4306). They are covered by 45:1164(B) and 45:850, and their rates are unreviewable by any state agency (33:4305(C)).
  - The Louisiana Municipal Natural Gas Purchasing and Distribution Authority (R.S. 33:4546.1 et seq.) sells natural gas "at wholesale to and for the benefit of participating political subdivisions" (33:4546.3(A)(6), d=90911). It is not a retail entity.
- **Small-system threshold: none found.**
- **Propane/LP:** not addressed in the LPSC statutes read. R.S. 33:1377 (d=1296158) treats "regulation of a liquefied petroleum gas dealer's authority to operate and serve customers" as "a matter of statewide concern" and bars parishes and municipalities from restricting it. Whether the LPSC or the LP-Gas Commission governs piped LP systems is **unverified**.

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

**None found.**
- R.S. 45:848 (deposit interest) is excluded by R.S. 45:850 (quoted above).
- The LPSC customer orders bind only jurisdictional utilities. Each one says so:
  - **General Order 10-5-07 (R-29706)**, Disconnection of Service: Electric and Gas Utilities. Source: https://lpscpubvalence.lpsc.louisiana.gov/portal/PSC/ViewFile?fileId=46j1cnIKxpM%3d, file `LA_GO_1.txt`. "An electric or natural gas utility shall not disconnect service for a residential customer in a parish on a day when the following extreme weather conditions exist within that parish: ... Winter: The previous day's highest temperature did not exceed 32 degrees Fahrenheit, and the temperature is predicted to remain at or below that level for the next 24 hours ... Summer: The nearest NWS issues a heat advisory". Footnote 4: "Natural gas utilities are not subject to this prohibition unless the customer uses natural gas to cool his or her home." The order is a Commission rulemaking, so it reaches only Commission-jurisdictional utilities.
  - **General Order 12/13/93**, 3-year limit on denying or disconnecting service over old written-off accounts (`LA_GO_2.txt`): "all jurisdictional utilities to adhere to a three year prescriptive period".
  - **General Order 7/12/76**, amending the 2/20/73 order (`LA_GO_3.txt`): "No utility shall disconnect a subscriber for non-payment of any principal amount without 5 days written notice". The 1973 order it amends limits late penalties to 5% and applies to "all utilities subject to the jurisdiction of this Commission" (`LA_GO_4.txt`).
- A Revised Statutes full-text search on legis.la.gov for "disconnect", "shut off", "cut off", "customer deposits" and "termination of utility service" found no statute imposing disconnection or deposit duties on municipal gas systems. The only gas hit was R.S. 45:302(C), which concerns pipeline-to-distribution-system shutoffs (see §4).

### 3. Who governs municipal customer practices instead

The municipality's (or political subdivision's) governing authority.
- **R.S. 33:4163** (d=90656): "The municipal corporation, parish, political subdivision, or taxing district may sell and distribute the commodity or service of the public utility within or without its corporate limits and may establish rates, rules, and regulations with respect to the sale and distribution."
- **R.S. 33:4162(A)** (d=90655): a political subdivision "may construct, acquire, extend, or improve any revenue-producing public utility ... either within or without its boundaries, and may operate and maintain the utility in the interest of the public."
- **Gas utility districts:** their own board of commissioners (33:4305(C), quoted in §1).
- **Safety is the exception.** Const. IV §21(C), last sentence: the municipal limitation "shall not apply to safety regulations pertaining to the operation of such utilities". The LPSC can therefore impose safety rules on municipal systems. Which pipeline-safety statute it uses was not read.
- **Orleans Parish:** R.S. 45:1164(A) excludes service jurisdiction "in the parish of Orleans". Const. IV §21(C) preserves regulation by "the governing authority" of a political subdivision that regulated a utility in 1974. That this authority is the New Orleans City Council is **secondary**: it is the hint, and I read no primary text naming the council.

### 4. Other applicability dimensions

**Election to opt in (and back out).**
- R.S. 45:1164.2 (d=99819): on a petition of "not less than twenty-five percent of or seven thousand five hundred of the qualified electors ... whichever is lesser, ... the governing authority shall order a referendum election to be held to determine whether or not any public utility owned by such political subdivision shall be under the jurisdiction and control of the commission." There is no repeat election within 2 years.
- R.S. 33:4491 et seq. covers a town, city or parish that itself regulates a "local public utility" and surrenders that power to the LPSC (d=90829). Under §4495 (d=90833) it "may reinvest itself with such power" by a later election.

**Inside vs outside city limits.**
- Customers outside the city vote in the opt-in election. R.S. 45:1164.3 (d=99820): the ballot goes "to the qualified electors of [municipality] ... and other electors who are customers of the public utility, wherever they may reside". R.S. 45:1161(1) likewise names "electors residing outside the municipality, who are customers of the municipally owned utility".
- The exclusion in 45:1164(B) turns on title ("the title to which is in the state or any of its political subdivisions or municipalities"), not on where the customer lives. Absent an election, the LPSC has no jurisdiction over a municipal system's outside-limits customers either.
- R.S. 33:4163 expressly lets the municipality set rules "within or without its corporate limits".
- No mileage limit was found.

**1974 date in the Constitution.** §21(C) protects utilities "owned, operated, or regulated on the effective date of this constitution". Systems acquired later are excluded by statute instead (45:1164(B) has no date limit).

**Rate-exempt sales.** Direct sales of natural gas to industrial users and for CNG vehicles are outside LPSC regulation (45:1163(A)(2)).

**Supply-side protection for municipal systems.** R.S. 45:302(C) (d=99987): "the supply of natural gas by pipelines to a local distribution system shall not be disconnected or shut off unless the local distribution system is given at least ninety days written notice ... and at least one public hearing is held by the Louisiana Public Service Commission". This protects the municipal LDC as a pipeline customer. It does not govern the LDC's own customers.

**Customer-count threshold:** none found.

### Row (one line per utility type)

- `municipal (no election) -> no state customer-protection rule set; R.S. 45:845-849 (incl. 848 deposit interest) excluded by R.S. 45:850; LPSC GOs (R-29706 weather, 12/13/93, 1973/76 notice/penalty) do not apply (Const. IV §21(C); R.S. 45:1164(B)); own governing authority rules (R.S. 33:4163); LPSC safety rules only (§21(C) last sentence) [verified]`
- `municipal (elected LPSC regulation under R.S. 45:1164.1-.13 or 33:4491) -> LPSC General Orders R-29706, 12/13/93, 7/12/76, 2/20/73 [verified]; R.S. 45:848 still excluded (45:850 turns on ownership, not regulation) [verified]`
- `investor-owned gas utility (outside Orleans) -> LPSC General Orders R-29706, 12/13/93, 7/12/76, 2/20/73 + R.S. 45:845-848 (5% deposit interest, return on demand, 10% penalty) [verified]`
- `investor-owned gas utility in Orleans Parish -> R.S. 45:845-848 [verified]; LPSC service jurisdiction excluded (45:1164(A)) [verified]; New Orleans City Council rules [secondary]`
- `gas utility district (R.S. 33:4301) -> own board; rates unreviewable (33:4305(C)); 45:845-849 excluded (45:850 "political subdivision"); LPSC excluded (45:1164(B)) [verified]`
- `municipal gas authority (R.S. 33:4546.1) -> wholesale only; n.a. for retail customer rules [verified]`
- `gas cooperative -> no provision found [unverified]`
- `propane/LP system -> R.S. 33:1377 (statewide concern; local governments may not restrict dealers); LPSC/LP-Gas Commission coverage [unverified]`

### Could not verify

- The LPSC deposit rules for gas (cap, triggers, refunds) were not located. This was carried over from the prior survey; the deposit-related order found was only R-29900 (waiver for family-violence victims), which was not fetched.
- The identity of the New Orleans City Council as regulator, and the council's own rules: hint only.
- Whether LP/propane piped systems fall under the LPSC or the LP-Gas Commission (R.S. 40:1841 et seq. not read).
- Whether any Louisiana gas cooperative exists or has a governing statute.
- Which pipeline-safety statute or rule applies to municipal systems under the §21(C) safety carve-out.
- Whether any later LPSC order amends or supersedes R-29706 (the consumer page still lists it as current).


---

## New Mexico — verified (statutes); NMAC scope reused from the prior survey's cached Cornell LII copies

Sources fetched: the official NMOneSource chapter PDFs.
- Chapter 62: https://nmonesource.com/nmos/nmsa/en/4407/1/document.do, saved as `put/src/NM_ch62.pdf` and `NM_ch62_full.txt`.
- Chapter 3: https://nmonesource.com/nmos/nmsa/en/4362/1/document.do, saved as `NM_ch3.pdf` and `NM_ch3.txt`.
- Chapter 27: https://nmonesource.com/nmos/nmsa/en/4358/1/document.do, saved as `NM_ch27.pdf` and `NM_ch27.txt`.

The PDFs include compiler annotations. Annotations (AG opinions, case notes) are marked as such below and are not statute.

NMAC scope sections come from the cached `scratchpad/src/nm2.txt` and `nmg2.txt` (Cornell LII).

### 1. Regulated utility definition

**NMSA 62-3-3(E)** ("person"):
- "'Person' means an individual, firm, partnership, company, rural electric cooperative organized under ... the Rural Electric Cooperative Act ..., corporation or lessee, trustee or receiver appointed by any court. 'Person' does not mean a class A county ... or a class B county ..."
- "'Person' does not mean a municipality as defined in this section unless the municipality has elected to come within the terms of the Public Utility Act as provided in Section 62-6-5 NMSA 1978. In the absence of voluntary election by a municipality to come within the provisions of the Public Utility Act, the municipality shall be expressly excluded from the operation of that act and from the operation of all its provisions, and no such municipality shall for any purpose be considered a public utility".
- (D): "'municipality' means a municipal corporation organized under the laws of the state, and H-class counties".

**NMSA 62-3-3(G)(2)** ("public utility"): "every person not engaged solely in interstate business ... that may own, operate, lease or control ... any plant, property or facility for the manufacture, storage, distribution, sale or furnishing to or for the public of natural or manufactured gas or mixed or liquefied petroleum gas for light, heat or power or other uses; but 'public utility' or 'utility' shall not include any plant, property or facility used for or in connection with the business of the manufacture, storage, distribution, sale or furnishing of liquefied petroleum gas in enclosed containers or tank truck for use by others than consumers who receive their supply through any pipeline system operating under municipal authority or franchise and distributing to the public".

**NMSA 62-3-4(A)(1)** excludes self-supply to "that person or that person's employees or tenants" and "retail distribution of natural gas or electricity for vehicular fuel".

**NMSA 62-6-4(A):** "Nothing in this section, however, shall be deemed to confer upon the commission power or jurisdiction to regulate or supervise the rates or service of any utility owned and operated by any municipal corporation either directly or through a municipally owned corporation or owned and operated by any H class county, by a class B county ... or by a class A county ..."

**Natural gas associations, NMSA 3-28-20:** "No association organized under the provisions of Chapter 3, Article 28 NMSA 1978 is subject to the jurisdiction of the New Mexico public utility commission [public regulation commission] or the terms and provisions of the Public Utility Act". The associations are formed by two or more municipalities with the county, or by the county for rural communities (3-28-1).

**NMAC scope:**
- 17.5.410.2: "This rule applies to electric, rural electric cooperative and gas utilities subject to the jurisdiction of the New Mexico public regulation commission."
- 17.10.650.2: "17.10.650 NMAC shall apply to any gas utility operating within the state of New Mexico under the jurisdiction of the New Mexico public regulation commission."

**Summary of the definition by utility type:**
- **Municipal: out** unless the municipality elects in (62-6-5). This covers municipally owned corporations and H/A/B-class county systems.
- **Cooperative: in.** "Person" includes "company" and "corporation" and names rural electric cooperatives. There is no gas-cooperative exclusion, and no gas-specific cooperative statute was found.
- **District/authority:**
  - Chapter 3 Art. 28 water or natural gas associations are **out** (3-28-20) unless they elect in (3-28-21).
  - Class A/B/H county systems are **out** (62-3-3(D),(E); 62-6-4(A)).
- **Small-system threshold:** none for gas. 62-8-7.1 (≤1,500 service connections, rates take effect without hearing) applies only to water and sewer utilities under 62-3-3(G)(3) and (5).
- **Propane/LP:** pipeline LPG distribution "to or for the public" is **in**. LPG "in enclosed containers or tank truck" is **out**.

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

**Yes. The Low Income Utility Assistance Act binds municipal gas utilities.**
- **NMSA 27-6-13(A)(2):** "'utility' means a publicly, privately or municipally owned utility or a distribution cooperative utility for the rendition of electric power or gas."
- **NMSA 27-6-17(A)** (winter notice procedure): "Unless requested by the customer, no gas or electric utility shall discontinue service to any residential customer for nonpayment during the period from November 15 through March 15 unless the following procedures are followed:"
  - (1) at least 15 days' notice, mailed or hand-delivered, "printed in both English and Spanish and in simple language", stating "(a) utility service shall stop on a specific date; (b) the customer may be eligible for financial assistance ...; and (c) for assistance, the customer should contact the utility or the authority";
  - (2) advise customers about the assistance programs;
  - (3) provide application forms at billing offices;
  - (4) "before the service is actually discontinued, the utility shall attempt to make contact in person or by telephone".
- **27-6-17(B):** no winter discontinuance "until at least fifteen days after the date scheduled for discontinuance of service if the authority has certified to the utility that a customer is eligible ... and that payment ... will be made within the fifteen-day period."
- **NMSA 27-6-18.1(A)** (LIHEAP winter moratorium): "no utility shall discontinue or disconnect service to a residential customer during the heating season for nonpayment of the customer's utility bill if the customer meets the qualifications to receive assistance pursuant to the low-income home energy assistance program ... during the program's current heating season."
  - (B): "The utility shall make payment plan options available to the customer pursuant to rules adopted by the public regulation commission."
  - (C)/(D) set the requalification and reconnection terms. (F) requires public information.
  - (G)(3): "'heating season' means the period beginning November 15 and continuing through March 15".
- Open question: how 27-6-18.1(B) ("payment plan options ... pursuant to rules adopted by the public regulation commission") applies to a municipal system that is otherwise outside PRC jurisdiction. Not resolved from text.

**Deposits:**
- **NMSA 3-23-1(A):** "A municipality ... may require a reasonable payment in advance or a reasonable deposit for water, electricity, gas, sewer service, geothermal energy, refuse collection service, street maintenance or storm water service." The only constraint is "reasonable". There is no interest rule.
- **NMSA 62-13-13** (deposit interest at the federal five-year Treasury rate) reaches "any public utility as defined in Section 62-3-3 NMSA 1978", telephone companies, and Art. 2 waterworks. Municipalities are "for any purpose" not a public utility (62-3-3(E)). So **62-13-13 does not reach municipal gas** absent an election.

**Not reaching municipal systems:**
- **NMSA 62-8-10** (seriously ill): "Utility service shall not be discontinued to any residence where a seriously or chronically ill person is residing if ..." It sits in Art. 8 of the Public Utility Act, which municipalities are "excluded from the operation of ... all its provisions" (62-3-3(E)). So it does **not** reach municipal systems despite its generic wording. This is my reading of the text; no case was read.
- **17.5.410 / 17.10.650 NMAC:** scope is limited to commission-jurisdictional utilities (quoted in §1).

**Municipal discontinuance statute:** NMSA 3-23-1(B) authorizes discontinuing **water** service after 30 days' nonpayment. There is no corresponding gas provision.

### 3. Who governs municipal customer practices instead

The municipal governing body. The utility can also be placed under a board of utility commissioners (3-23-10; heading seen, text not read).
- The PRC's role over municipal gas is limited to two things: approving the acquisition price and revenue-bond terms (3-23-3), and authorizing distribution inside another municipality (3-25-3(B)(1)).
- The Health Care Authority administers LIUAA. Under 27-6-17(C), the Authority and the PRC "shall coordinate and adopt ... either separate or joint rules necessary to implement" §27-6-17.
- Annotation to 62-6-4 (City of Sunland Park v. N.M. PRC, 2004-NMCA-024): "the public regulation commission has no jurisdiction over public utilities that are owned and operated by a municipal corporation, unless they agree otherwise." This is a case note, i.e. secondary.

### 4. Other applicability dimensions

**Election to opt in.**
- Municipalities, NMSA 62-6-5: on a petition of 25% of the votes cast for governor, an election is held. If the majority favors regulation, "it is subject to all the provisions of the Public Utility Act". There is no repeat election within 2 years (62-6-5(C)).
- Gas associations, NMSA 3-28-21: the board "may elect by resolution ... to become subject to the jurisdiction of the ... commission in matters of rates, security issues, jurisdictional area and industrial service and to all of the terms and provisions of the Public Utility Act".

**Inside vs outside city limits.**
- 62-6-4(A) has no inside/outside qualifier. The compiler's annotation cites 1943 Op. Att'y Gen. No. 43-4395: "The commission is not empowered to regulate or supervise the service and rates set by municipally owned utilities either in or outside the corporate limits." That is secondary.
- Distribution reach is capped by statute. NMSA 3-25-3(A)(2) permits gas distribution facilities "in the municipality and within five miles of the municipal boundary". 3-25-1(A)(1) states the intent to supply "inhabitants and others within five miles of the municipal boundary". The annotation (City of Las Cruces v. Rio Grande Gas Co., 1967-NMSC-190) holds there is no authority beyond five miles.
- Distribution inside another municipality requires a PRC order plus that municipality's ordinance (3-25-3(B)).

**Associations' territory:** a gas association "shall not provide gas service to any customers of a gas utility regulated by the ... commission within any area described in the utility's jurisdictional certificate" (3-28-1).

**Customer-count threshold:** none for gas (see §1).

### Row (one line per utility type)

- `municipal (no election; incl. municipally owned corp.) -> LIUAA winter rules NMSA 27-6-17 + 27-6-18.1 [verified]; deposit "reasonable" per NMSA 3-23-1(A) [verified]; NOT 62-13-13 interest, 62-8-10, 17.5.410, 17.10.650 (62-3-3(E), 62-6-4(A)) [verified]; own governing body rules [verified]`
- `municipal (elected under 62-6-5) -> all Public Utility Act incl. 62-13-13, 62-8-10; 17.5.410 + 17.10.650 NMAC; LIUAA [verified]`
- `investor-owned gas utility -> 17.5.410 + 17.10.650 NMAC; 62-13-13 deposit interest; 62-8-10 seriously ill; LIUAA 27-6-17/27-6-18.1 [verified]`
- `gas cooperative -> treated as a public utility under 62-3-3(E)/(G) ("company", "corporation") -> as investor-owned; LIUAA expressly ("distribution cooperative utility ... gas") [verified text; whether any gas co-op exists unverified]`
- `county (H/A/B class) system -> as municipal: outside the PUA (62-3-3(D),(E); 62-6-4(A)); LIUAA "publicly ... owned" [verified text; LIUAA reach is my reading]`
- `natural gas association (NMSA 3-28) -> outside PRC/PUA (3-28-20) unless it elects in (3-28-21) [verified]; LIUAA probably applies as "publicly ... owned utility" [unverified reading]`
- `propane/LP pipeline system serving the public -> public utility (62-3-3(G)(2)) -> as investor-owned [verified]; bottled/tank-truck LPG -> outside the PUA [verified]; LIUAA reach to LPG pipeline systems [unverified]`

### Could not verify

- Whether LIUAA reaches Chapter 3 Art. 28 gas associations and LP pipeline systems. The text says "publicly, privately or municipally owned utility ... for the rendition of ... gas"; no case was found.
- How 27-6-18.1(B) (PRC payment-plan rules) applies to non-jurisdictional municipal systems.
- The 62-8-10 exclusion for municipalities rests on my reading of 62-3-3(E). No case or AG opinion was read.
- The full text of 3-23-10 (board of utility commissioners) and the LPG Act (NMSA 70-5).
- Whether any New Mexico gas cooperative exists.
- 17.5.410 and 17.10.650 scope text came from Cornell LII copies, not the official NMAC site.


---

## Arkansas — partly verified

**Sources and their status:**
- Arkansas Code text is from **law.justia.com, "2025 Arkansas Code"**. It is a publisher mirror, not the official code. Lexis is the State's free official host, and it requires JavaScript. curl gets a 403 from Justia, so I read the sections in a real Chrome tab. Verbatim extracts are saved in `put/src/AR_justia_extracts.txt`. Quotes below are mirror text and should be treated as **verified-against-mirror**. The section history lines run to 2019–2025 acts, which is consistent with a current edition.
- APSC General Service Rules are from Cornell LII, 126.04.16 Ark. Code R. 001, cached in `scratchpad/src/ar16.txt`: https://www.law.cornell.edu/regulations/arkansas/126-04-16-Ark-Code-R-001

### 1. Regulated utility definition

**Ark. Code § 23-1-101(9)(A)** (https://law.justia.com/codes/arkansas/title-23/subtitle-1/chapter-1/section-23-1-101/):
> "'Public utility' includes persons and corporations, or their lessees, trustees, and receivers, owning or operating in this state equipment or facilities for: (i) Producing, generating, transmitting, delivering, or furnishing gas, electricity, steam, or another agent for the production of light, heat, or power to or for the public for compensation; (ii) ... water ... However, nothing in this subdivision (9) shall be construed to include water facilities and equipment of cities and towns in the definition of public utility."

The definition expressly carves out city water (9)(A)(ii) and city sewer (9)(A)(vi). It does **not** carve out city *gas* in § 23-1-101. The municipal-gas exclusion comes from the provisions below.

**Ark. Code § 23-2-302(a)(1)(C)** (APSC jurisdiction):
> "Further, nothing in this act shall vest the commission with jurisdiction as to any improvement district or municipality furnishing gas or electricity for any purpose".

**Ark. Code § 14-200-112:**
> "Municipalities owning or operating any public utilities are exempt from any supervision or regulation by the Arkansas Transportation Commission and the Arkansas Public Service Commission."

**Ark. Code § 23-4-201(b)** (APSC exclusive rate jurisdiction):
> "This term shall not include those utilities owned or operated by municipalities or leased by them to a nonprofit corporation."

**Other carve-outs in § 23-1-101(9):**
- (9)(C): no self-supply.
- (9)(H): "does not include a person or corporation that furnishes compressed natural gas as a motor fuel".
- The Class-B revenue threshold and the petition opt-in in (9)(A)(ii)(b), (9)(A)(vi)(b) and (9)(G) apply to **water and sewer only**. There is no gas size threshold.

**APSC rule scope.** General Service Rules, Rule 1.01: "These Rules shall apply to all whose activities bring them under the jurisdiction of the Commission except for telecommunications providers." "Utility Service" is defined as "Service provided by a public utility and subject to regulation by the Commission."

**Summary:**
- **Municipal:** OUT (§ 23-2-302(a)(1)(C); § 14-200-112; § 23-4-201(b)). This includes a municipal system "leased ... to a nonprofit corporation", for rates.
- **Cooperative:** for gas, n.a. or unverified. I found no gas-cooperative statute. The cooperative references in Title 23 that I scanned concern electric cooperatives.
- **District/authority:** improvement districts furnishing gas are OUT (§ 23-2-302(a)(1)(C)). § 14-200-101(a) also excludes "a consolidated utility district under ... § 14-217-101 et seq." from the city-franchise definition.
- **Small-system threshold:** none for gas. The thresholds are water and sewer only.
- **Propane/LP:** the definition says "furnishing gas", which is not limited to natural gas. Whether a piped LP system is an APSC public utility is UNVERIFIED. The LP Gas Board Act (§ 15-75-101 et seq.) is a safety and licensing statute. Under § 15-75-207 the Board "may adopt ... the National Fire Protection Association standards". None of the 53 sections mention "public utility", the "Public Service Commission" or municipalities.

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

**Ark. Code § 23-4-206** (deposit interest) is a potential municipal reach. Its scope is UNRESOLVED.
- (a): "Whenever any person, company, or corporation furnishing patrons or consumers with power, gas, water, electricity, or telephone service shall require a deposit from the consumer ... the person putting up the deposit, when the deposit is taken down or meter removed, shall receive interest on the deposit until it is returned ..., provided all bills due for service furnished have been paid".
- (b)(1)–(3): simple interest at "such annual rates as the commission shall determine from year to year", with the APSC order issued "no later than December 31", effective January 1, and capped at "not more than ten percent (10%)".
- (c): "This section shall not apply to cities or towns of a population of less than three thousand (3,000) persons that have granted franchises for electric current for lighting ... furnished by manufacturing establishments".
- The text contains no municipal exclusion, and its subject is "any ... corporation", which arguably includes a municipal corporation. The (c) carve-out for small cities implies the legislature considered city-linked service.
- Against that, § 14-200-112 exempts municipal utilities from "any supervision or regulation by ... the Arkansas Public Service Commission". The section is enforced through the APSC-set rate, but the duty itself is statutory.
- I found no AG opinion or case resolving this. It is the closest Arkansas analogue to Kansas K.S.A. 12-822.

**Ark. Code § 23-4-204** (no disconnect charge). Reach is UNRESOLVED.
- "It shall be unlawful for any public utility furnishing water, gas, or electricity to the general public to make a charge for disconnecting service." The fine is $100–$500 per violation, under Acts 1957, No. 275.
- "Public utility" is not defined for this act. Whether it reaches municipal systems is UNVERIFIED.

**Ark. Code § 23-4-203(a)** (bills must show units). Reach is UNRESOLVED.
- "All water, gas, or electric companies shall base their charges for their commodities upon the reading of the meters ... The bills or statements rendered to patrons shall show the number of units charged for."
- The civil-sanction subsection (b) applies only to "jurisdictional" utilities. Subsection (a)'s reach to municipal "companies" is UNVERIFIED.

**APSC General Service Rules.** These include the Cold Weather Rule 6.15 ("Electric and gas utilities may not suspend residential service on a day when the National Weather Service forecasts ... 32 degrees Fahrenheit or lower"), the gas low-income moratorium "November 1 to March 31", and the Medical Need certificate rule. They apply only to entities under Commission jurisdiction (Rule 1.01). Municipal systems are not bound.

**§ 23-2-304(a)(9)** directs the APSC to "Assure that retail customers should have access to safe, reliable, and affordable electricity, including protection against service disconnections in extreme weather or in cases of medical emergency". It covers electricity only and APSC-jurisdictional utilities only.

**Title 14 municipal law.**
- Subtitle 12 (public utilities generally, chapters 199–208, 196 sections) has no municipal customer deposit, disconnection, cold-weather or medical provision.
- The search terms were deposit, disconnect, shut off, terminat*, weather, medical, outside, beyond the corporate limits and Public Service Commission. Every "deposit" hit concerned bond proceeds or public funds.
- Chapter 205, "Natural Gas Distribution Systems", is municipal revenue-bond financing only.
- **Title 14 Subtitle 3** (chapters 42–45, 54 and 58; 223 sections scanned): no municipal-utility deposit, disconnection or outside-limits provision found. This is partial coverage; see "Could not verify".

### 3. Who governs municipal customer practices instead

- **The municipal governing body.** § 14-200-112 removes APSC supervision. For a municipal electric system, § 14-200-111(b)(1) says rates and rules "shall be established ... by the city council, board of directors, or local water and light commission". I found no parallel gas-specific text, so the governing body by default.
- **Water/light commissions** (§ 14-201-110(b)(1)) are "empowered to establish rates for water, or electricity, or both". Gas is not listed.
- **Over a private franchised gas utility inside city limits:**
  - § 14-200-101(b)(1)(A) gives every city "jurisdiction to ... determine the terms and conditions upon which the public utility may be permitted to occupy the streets ... including ... (a) The rates, quality, and character of each kind of product or service". This is "Except as provided in § 23-4-201".
  - § 23-4-201(a) vests rates for gas public utilities exclusively in the APSC: "Cities and towns ... shall have no authority ... to fix and determine rates charged ... by electric, gas, or telephone public utilities".
  - The older § 23-4-101(c) and § 23-2-302(a)(1)(B) leave in-city "rule, regulation ... or other matter" of a gas company to municipal councils. How these 1919/1921 provisions interact with the APSC's General Service Rules for IOUs inside cities is NOT resolved here.
- **State agency for specific topics:** I found no statute giving the APSC customer-practice authority over municipal gas. Pipeline safety jurisdiction over municipal gas systems was not researched and is UNVERIFIED.

### 4. Other applicability dimensions

**Owner type** is the primary key: municipality, improvement district, nonprofit lessee of a municipality, or private/IOU.

**Location, inside or outside city limits:**
- **Electric:** a municipal system may extend into contiguous rural territory "upon order of the Arkansas Public Service Commission". Its city council still sets the rural rates and rules "without the approval of the Arkansas Public Service Commission". Rural rates are capped at in-city rates, except "where the municipality serves less than three thousand (3,000) customers outside its corporate limits, rates may be ten percent (10%) higher" (§ 14-200-111).
- **Gas:** I found no equivalent outside-limits provision. § 23-2-302(a)(1)(C) excludes "any ... municipality furnishing gas ... for any purpose", with no location limit. A municipal gas system's customers outside city limits are therefore not APSC-jurisdictional on the statute's face (verified-against-mirror).
- **Private gas company:** the in-city/out-of-city split matters historically (§ 23-2-302(a)(1)(B); § 23-4-101(c)). Rates are now APSC-exclusive everywhere (§ 23-4-201).

**Lease to a nonprofit.** § 23-4-201(b) excludes municipal utilities "leased by them to a nonprofit corporation" from APSC rate jurisdiction.

**Customer-count or revenue threshold, and opt-in by petition:** water and sewer only (§ 23-1-101(9)(A)(ii)(b), (vi)(b), (9)(G)). Not gas.

**Small-city exception to deposit interest.** § 23-4-206(c) excludes "cities or towns of a population of less than three thousand (3,000)" with electric franchises to manufacturing establishments. This is a population-based selector, but narrow and electric-specific.

### Row (one line per utility type)
- `municipal gas system -> no APSC rules (Ark. Code §§ 23-2-302(a)(1)(C), 14-200-112, 23-4-201(b)); governing-body ordinance governs; § 23-4-206 deposit interest at APSC rate possibly applies ("any ... corporation") [mirror-verified text; municipal reach unverified]; § 23-4-204 no-disconnect-charge possibly applies [unverified]`
- `municipal gas system leased to nonprofit -> excluded from APSC rate jurisdiction (§ 23-4-201(b)); other APSC jurisdiction unclear [mirror-verified text / scope unverified]`
- `improvement district furnishing gas -> no APSC jurisdiction (§ 23-2-302(a)(1)(C)) [mirror-verified]`
- `investor-owned / private gas utility -> APSC General Service Rules (126.04.16-001: deposits §4, Cold Weather 6.15, Medical Need), § 23-4-206 deposit interest, §§ 23-4-202/203/204 [verified (rules: Cornell), statutes mirror-verified]`
- `cooperative (gas) -> n.a.; no gas-co-op statute found [unverified]`
- `propane/LP (tank/cylinder) -> LP Gas Board Act § 15-75-101 et seq. (safety/licensing; NFPA standards) only [mirror-verified]`
- `piped LP distribution (private) -> possibly APSC "furnishing gas" public utility [unverified]`

### Could not verify
- **Official text.** All Arkansas statute quotes are from the Justia mirror (2025 Arkansas Code). The official Lexis host requires JavaScript and could not be reached.
- **Whether § 23-4-206 (deposit interest) binds municipal gas systems.** It turns on whether "any person, company, or corporation" includes a municipal corporation, and on its interaction with § 14-200-112. No AG opinion or case was read.
- **Whether §§ 23-4-203(a) and 23-4-204 (no disconnect charge) reach municipal systems.**
- **Title 14 Subtitle 3 (municipal government).** I ran an automated scan of 223 sections the crawler listed under chapters 42–45, 54 and 58 (Justia mirror). It used a regex for utility/water/gas/electric near deposit, disconnect, shut-off, cut-off, discontinue or terminate, plus outside or beyond city limits near gas/utility. It found NO hits. The crawl may not have reached every subchapter. Chapters 37–41, 46–53 and 55–62 were not scanned. A municipal deposit or cutoff statute elsewhere in Title 14 is therefore not ruled out.
- **Pipeline safety jurisdiction over municipal gas systems in Arkansas** was not researched.
- **Gas cooperatives and piped-propane systems:** the absence of a statute is unverified.
- **How the 1919/1921 in-city municipal-council jurisdiction (§§ 23-2-302(a)(1)(B), 23-4-101(c)) coexists with APSC General Service Rules for IOUs inside city limits.**
- **Currency of the APSC General Service Rules.** They are verified only as of the 2016 Cornell codification. The APSC website was not reachable earlier.


---

## Kansas — partly verified

Sources (raw files in `put/src/KS_*`). All statute text is from ksrevisor.gov, fetched 2026-10-06. Exceptions: K.S.A. 12-822 is the cached copy at `scratchpad/src/ks12822.txt`, and the KCC Billing Standards are the cached copy at `scratchpad/src/ks_billing.txt`.

### 1. Regulated utility definition

- **K.S.A. 66-104(a)** (https://ksrevisor.gov/statutes/chapters/ch66/066_001_0004.html):
  - "'public utility' means every corporation, company, individual, association of persons, their trustees, lessees or receivers, that now or hereafter may own, control, operate or manage, except for private use, any equipment, plant or generating machinery ... or the conveyance of oil and gas through pipelines in or through any part of the state, except pipelines less than 15 miles in length and not operated in connection with or for the general commercial supply of gas or oil, and all companies for the production, transmission, delivery or furnishing of heat, light, water or power."
  - The only cooperative exclusion in (a) is for single-line telephone cooperatives.
- **K.S.A. 66-104(b)**:
  - "'Public utility' includes that portion of every municipally owned or operated electric or gas utility located in an area outside of and more than three miles from the corporate limits of such municipality, but regulation of the rates, charges, terms and conditions of service of such utility within such area shall be subject to commission regulation only as provided in K.S.A. 66-104f".
  - "Nothing in this act shall apply to a municipally owned or operated utility, or portion thereof, located within the corporate limits of such municipality or located outside of such corporate limits but within three miles thereof."
- **K.S.A. 66-104(c)**: "the power and authority to control and regulate all public utilities and common carriers situated and operated wholly or principally within any city or principally operated for the benefit of such city or its people, shall be vested exclusively in such city, subject only to the right to apply for relief to the corporation commission as provided in K.S.A. 66-133 ... and to the provisions of K.S.A. 66-104e". This covers private utilities operating principally within a city.
- **K.S.A. 66-1,200(a)** (https://ksrevisor.gov/statutes/chapters/ch66/066_001_0200.html): "'Natural gas public utility' means any public utility defined in K.S.A. 66-104 ... which supplies natural gas."
- **K.S.A. 66-104c**, small nonprofit utilities (https://ksrevisor.gov/statutes/chapters/ch66/066_001_0004c.html):
  - "(a) ... no nonprofit public utility shall be subject to the jurisdiction ... of the state corporation commission if the utility meets the following conditions: (1) Every customer, shareholder, household or meter owner is an owner of the utility and has an equal vote on matters concerning the utility; (2) the utility employs no full-time employees; and (3) the utility has no more than 100 customers".
  - "(b) The state corporation commission shall retain jurisdiction and control over the service territory ... and over all matters concerning natural gas pipeline safety."
- **K.S.A. 66-104d**, the cooperative deregulation election (https://ksrevisor.gov/statutes/chapters/ch66/066_001_0004d.html):
  - It covers only electric cooperatives: "'cooperative' means any: (1) Corporation organized under the electric cooperative act, K.S.A. 17-4601 et seq. ..."
  - "a cooperative may elect to be exempt from the jurisdiction ... by complying with the provisions of subsection (c)" (member mail-ballot vote).
  - **K.S.A. 66-104b** is also electric-only. It exempts out-of-state-headquartered electric cooperatives.
- **K.S.A. 66-105a(a)** (https://ksrevisor.gov/statutes/chapters/ch66/066_001_0005a.html): "'public utility' ... shall not include any gas gathering system ... which provides gas gathering services". Under **(b)–(c)**, the KCC may still regulate health- or safety-related curtailment for end users directly connected to a gathering system, and requires 30 days' notice of curtailment except in an emergency.

Summary:
- **Municipal:** OUT inside city limits and within 3 miles. IN for the portion more than 3 miles outside, but only on the limited 66-104f terms (section 4).
- **Cooperative:** gas cooperatives are IN by default. No gas-cooperative exclusion or election was found; 66-104b and 66-104d are electric-only. The 66-104c exemption applies if the cooperative is member-owned with equal votes, has no full-time employees and has 100 or fewer customers.
- **District/authority:** no gas-district category exists in Ch. 66. K.S.A. 12-808c treats "water district, improvement district or other political or taxing subdivision" as a "municipality" (section 2).
- **Small-system threshold:** 100 or fewer customers, combined with owner-member and no-employee conditions (66-104c). Separately, pipelines under 15 miles that are "not operated in connection with or for the general commercial supply of gas" are excluded (66-104(a)).
- **Propane/LP:** not addressed in the text read. Whether a piped-propane system is a "company for ... furnishing of heat, light ... or power" is unverified.

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

- **K.S.A. 12-822**, deposits and interest (https://ksrevisor.gov/statutes/chapters/ch12/012_008_0022.html):
  - "It shall be unlawful for any public or municipally owned utility doing business in the state of Kansas to receive or collect a deposit ... unless such public or municipally owned utility shall keep a separate account ... and shall pay to the customer making the deposit interest at the rate determined by the state corporation commission. Such interest shall be credited once a year or credited on January 1 ..."
  - "The amount of deposit required shall at all times be reasonable, and shall be based upon the value of the maximum service rendered".
  - The section also sets municipal-only rules on investing deposits and on 3-year escheat to the operating fund, with publication.
- **K.S.A. 12-823**, penalty (https://ksrevisor.gov/statutes/chapters/ch12/012_008_0023.html): "Any public or municipally owned utility violating any of the provisions of this act shall be subject to a penalty of not less than five dollars ($5) nor exceeding twenty-five dollars ($25)".
- **K.S.A. 12-808c**, lien, tenant service and deposit cap (https://ksrevisor.gov/statutes/chapters/ch12/012_008_0008c.html):
  - "(a) ... if any person ... using or operating on property to which is provided utility services by a utility owned or operated by a municipality, neglects, fails or refuses to pay the fees or charges for such service, the unpaid fees or charges shall constitute a lien upon the property ... certified ... to the county clerk ... to be placed on the tax roll ... The governing body may refuse the delivery of such utility service as otherwise permitted by law until such time as such charges are fully paid."
  - "(b) A lien shall not attach ... when the utility service has been contracted for by a tenant and not by the landlord or owner".
  - "(c) ... no municipality which provides utility services shall refuse to contract with a tenant for provision of such services to property occupied by such tenant. A municipality shall not be required to contract with any person if such person has outstanding or unpaid charges for utility services provided by such municipality."
  - "(d) A municipality may require a single deposit to be paid by a customer for all utility services, except that such deposit shall not exceed an amount equal to the expected average bills for a three month period for such utility services."
  - "(e)(1) 'Municipality' means any city, county, township, water district, improvement district or other political or taxing subdivision of the state or any agency or instrumentality of a municipality which provides utility services but does not include any rural water district ... (2) 'Utility services' means ... sewer, water, gas and electric power services."
- **Cold Weather Rule:**
  - This is a KCC order (Billing Standards Section V), not a statute. The ch. 66 index (https://ksrevisor.gov/statutes/ksa_ch66.html) has no cold-weather or disconnection section.
  - Two bills to codify it were found, 1997 SB 272 and 2003 HB 2186. Neither appears in the current statutes.
  - The HB 2186 supplemental note says: "The bill would impact only those electric and gas utilities that are not specifically exempt by statute from jurisdiction of the KCC. (In general, municipal utilities and cooperatives would not be covered by the bill.)"
  - KCC news release, 2023-10-30 (secondary): "The Cold Weather Rule applies only to residential customers of electric and natural gas utility companies under the KCC's jurisdiction, however many municipal utilities and cooperatives have similar winter weather policies."
  - **No statute extending the Cold Weather Rule to municipal systems was found.**
- **Pipeline safety:** the KCC retains pipeline safety authority over municipal utilities (66-104f(c), quoted in section 4) and over small nonprofit utilities (66-104c(b)).

### 3. Who governs municipal customer practices instead

- The city governing body, or its board of public utilities.
  - K.S.A. 66-104(b): "Nothing in this act shall apply to a municipally owned or operated utility ... located within the corporate limits ... or ... within three miles thereof."
  - K.S.A. 12-829 (https://ksrevisor.gov/statutes/chapters/ch12/012_008_0029.html), for cities with a managing board: "the governing body shall by ordinance fix such rates for water, fuel, power or light as are recommended by said board".
- The statutory overlays are 12-822 (deposit interest), 12-808c (3-month deposit cap, liens, tenants) and KCC pipeline safety.
- No state agency oversees municipal disconnection or winter practices; none was found.

### 4. Other applicability dimensions

- **Distance from city limits** (66-104(b) and 66-104f, https://ksrevisor.gov/statutes/chapters/ch66/066_001_0004f.html):
  - "(a) The rates, charges and terms and conditions of service of a municipally owned or operated electric or natural gas public utility for retail services provided outside of and more than three miles from the corporate limits of the municipality shall not be subject to the jurisdiction ... of the state corporation commission, except as provided in subsection (b), if: (1) The customers served in such area number no more than 40% of the total number of customers served by such utility; (2) the rates and charges for customers in such area are no greater than the rates and charges for the customers served by such utility within the corporate limits ... and the terms and conditions of service are the same ... (3) not less than 10 days in advance of any meeting at which changes ... will be considered, the municipal entity ... provides customers in such area both notice ... and a description of the changes ... [and] a statement concerning the right to petition the commission ...; (4) ... furnishes, within 21 days ... names, addresses and rate classifications ...; and (5) ... provides to the commission an annual report on or before May 1".
  - "(b) If, not more than one year after a change ... there is filed with the commission a petition signed by not less than 25% of the customers in such area protesting such change, the commission shall investigate all rates, charges and terms and conditions of service for services in such area."
  - "(c) Nothing in this act shall be construed to affect ... the authority of the commission ... over such utility with regard to service territory, ... pipeline safety and underground utility damage prevention".
  - K.S.A. 12-808a: "Subject to the approval of the corporation commission, every such utility shall have ... the power and authority to determine the rate for service within any area located outside of and more than three (3) miles from the corporate limits of a city." This is older text; 66-104f now conditions it.
  - Selector: a municipal utility's customers more than 3 miles outside its limits fall under KCC terms-of-service jurisdiction **unless** all five 66-104f(a) conditions hold, including the 40% cap and parity with in-city terms. Even then they remain subject to a 25%-customer protest petition.
- **City relinquishment, private systems only** (66-104e, https://ksrevisor.gov/statutes/chapters/ch66/066_001_0004e.html): "Any city by ordinance may relinquish to the state corporation commission the city's power and authority ... to control and regulate any privately owned and operated natural gas or water public utilities situated and operated wholly or principally within the city". The city may reassert it, no more than once every 2 years.
  - Selector: a private gas utility operating principally within one city is city-regulated under 66-104(c) unless the city has relinquished to the KCC.
- **Electric cooperative election** (66-104d): this does not apply to gas.
- **Small nonprofit threshold** (66-104c): 100 customers plus the other conditions (section 1).

### Row (one line per utility type)

- `municipal (in city or within 3 mi) -> city ordinance + K.S.A. 12-822 deposit interest at KCC rate + 12-808c (3-month deposit cap, tax lien, tenant contracting) + KCC pipeline safety; NOT KCC Billing Standards / Cold Weather Rule (66-104(b)) [verified]`
- `municipal (portion >3 mi outside city) -> same as above + KCC rates/terms jurisdiction unless 66-104f(a)(1)-(5) all met; 25%-customer protest petition (66-104f(b)) [verified]`
- `investor-owned/private gas utility -> KCC Billing Standards incl. Cold Weather Rule (66-104(a), 66-1,200) + 12-822 ("public ... utility") [verified]; if operating principally within one city, city regulates unless relinquished under 66-104e (66-104(c)) [verified]`
- `cooperative (gas) -> treated as a public utility under 66-104(a), with no gas-coop exclusion found; 66-104c exemption if member-owned, no full-time staff, <=100 customers [verified]`
- `small nonprofit (<=100 customers, owner-members, no FT staff) -> KCC service territory + pipeline safety only (66-104c) [verified]`
- `district/authority -> no gas-district statute found; any political subdivision supplying gas is a "municipality" under 12-808c(e) [verified]; 66-104(b) municipal exclusion wording covers "municipally owned or operated" only [verified text; application to non-city subdivisions unverified]`
- `propane/LP piped system -> unverified`
- `gas gathering system serving end users -> not a public utility (66-105a(a)); KCC curtailment protections (66-105a(b)-(c)) [verified]`

### Could not verify

- **Propane/LP:** whether a piped propane distribution system is a 66-104 "public utility". No text was read on this.
- **KCC Cold Weather Rule order:** the scope language was read only in a KCC press release (secondary) and in the HB 2186 supplemental note. The Billing Standards PDF contains no scope paragraph. That no statute extends the rule to municipal systems is based on the ch. 66 index and on the two failed bills, not on a full-text search.
- **Non-city subdivisions:** whether 66-104(b)'s "municipally owned" exclusion covers counties, townships or improvement districts that operate gas systems.
- **Case law:** whether a municipal utility counts as "public ... utility" under 12-822. This is moot, because the section names "municipally owned utility" expressly.


---

## Ohio — partly verified

Sources (raw files in `put/src/OH_*`): codes.ohio.gov, fetched 2026-10-06. The text of 4901:1-17-01 and -02 is the cached Cornell copy at `scratchpad/src/oh01.txt` and `oh02.txt`.

### 1. Regulated utility definition

- **R.C. 4905.02(A)** (https://codes.ohio.gov/ohio-revised-code/section-4905.02): "'public utility' includes every corporation, company, copartnership, person, or association ... defined in section 4905.03 of the Revised Code, including any public utility that operates its utility not for profit, except the following:"
  - "(1) An electric light company that operates its utility not for profit;"
  - "(2) A public utility, other than a telephone company, that is owned and operated exclusively by and solely for the utility's customers, including any consumer or group of consumers purchasing, delivering, storing, or transporting ... natural gas exclusively by and solely for the consumer's or consumers' own intended use as the end user or end users and not for profit;"
  - "(3) A public utility that is owned or operated by any municipal corporation;"
- **R.C. 4905.03(E)** (https://codes.ohio.gov/ohio-revised-code/section-4905.03):
  - "A natural gas company, when engaged in the business of supplying natural gas for lighting, power, or heating purposes to consumers within this state."
  - "'natural gas' includes natural gas that ... has been blended with propane, hydrogen, biologically derived methane gas, or any other artificially produced or processed gas."
  - Under 4905.03(D), a "gas company" supplies "artificial gas".
- **R.C. 4929.01(G)** (https://codes.ohio.gov/ohio-revised-code/section-4929.01): "'Natural gas company' means a natural gas company, as defined in section 4905.03 ... that is a public utility as defined in section 4905.02 ... and excludes a retail natural gas supplier." 4929.01(N) also excludes "an entity described in division (A)(2) or (3) of section 4905.02" from "retail natural gas supplier".
- No customer-count threshold appears in 4905.02 or 4905.03. **No small-system exemption was found in the statute.**
- **OAC 4901:1-13-01** (https://codes.ohio.gov/ohio-administrative-code/rule-4901:1-13-01):
  - "(N) 'Natural gas company' means a company that meets the definition of a natural gas company set forth in section 4905.03 ... and that also meets the definition of a public utility under section 4905.02".
  - "(W) 'Small gas company' means a gas company serving seventy-five thousand or fewer customers. (X) 'Small natural gas company' ... seventy-five thousand or fewer customers." These are used as within-rule differentiators, not as an exemption.

Summary:
- **Municipal:** OUT (4905.02(A)(3), "owned or operated by any municipal corporation").
- **Cooperative:** OUT if it is "owned and operated exclusively by and solely for the utility's customers" (4905.02(A)(2)).
- **District/authority:** no gas-district category was found. The (A)(3) exclusion names only "municipal corporation". Whether a county, township or regional authority gas system is excluded is unverified.
- **Small-system threshold:** none for jurisdiction. "Small (natural) gas company" (75,000 or fewer customers) is only a rule-level category.
- **Propane/LP:** gas blended with propane is "natural gas" (4905.03). Whether a pure piped-propane system is a 4905.03 company is unverified. Pipeline safety reaches any "flammable gas" operator (section 2).

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

- **PUCO chapters exclude municipal systems through their definitions:**
  - OAC 4901:1-13-02(A)(1) (https://codes.ohio.gov/ohio-administrative-code/rule-4901:1-13-02): the gas service rules "Apply to investor-owned gas or natural gas companies".
  - OAC 4901:1-18-02(A) (termination): "The rules in this chapter apply to all electric, gas, and natural gas utility companies that provide service to residential customers". However, 4901:1-18-01(U) defines "Utility company" by reference to "section 4905.03, and division (G) of section 4929.01", and 4929.01(G) requires public-utility status (https://codes.ohio.gov/ohio-administrative-code/rule-4901:1-18-01).
  - OAC 4901:1-17-01(J) (deposits) does the same, via "division (G) of section 4929.01".
  - Result: a municipal natural-gas system is outside 4901:1-13, 1-17 and 1-18.
- **R.C. 4933.12, winter disconnection** (https://codes.ohio.gov/ohio-revised-code/section-4933.12). The statute is written to "a natural gas company or a gas company" ("the company"). Chapter 4933 does not define those terms; the 4905.03 definitions are stated "As used in this chapter" (ch. 4905).
  - "(C) The company shall not, for any reason, unless required by the consumer for safety reasons, or unless tampering ... or theft ... has occurred, stop gas from entering the premises of any residential consumer for the period beginning on the fifteenth day of November and ending on the fifteenth day of the following April, unless both of the following apply: (1) The account of the consumer is in arrears thirty days or more. (2) [tenant whose landlord pays — five days' notice to the occupant]."
  - "(D) ... unless the company, at the time it sends or delivers ... notices of termination, informs the occupant ... where to obtain state and federal aid ..."
  - "(E) [on request by a county human services department by Nov 1, 24-hour prior written notice of each winter residential termination]"
  - "(F) No company shall stop gas from entering the residential premises of any residential consumer who is deployed on active duty for nonpayment ... [repayment period at least equal to deployment; no late fees or interest] ... in the case of a company that is a public utility as defined in section 4905.02 of the Revised Code, may request the assistance of the public utilities commission". This phrasing implies that some covered "companies" are not public utilities.
  - Whether this binds a municipal gas system is **textually open**; no case law was read. Mark it **unverified**.
- **R.C. 4933.122, termination procedures** (https://codes.ohio.gov/ohio-revised-code/section-4933.122):
  - "No natural gas, gas, or electric light company shall terminate service ... to a residential consumer, except pursuant to procedures that provide for ... (A) Reasonable prior notice ... and no due date shall be established ... that is less than fourteen days after the mailing of the billing. This limitation does not apply to ... electric light companies operated not for profit or public utilities that are owned or operated by a municipal corporation. (B) A reasonable opportunity ... to dispute ... (C) [medical / life-support / extended payment plan]".
  - Carving municipal systems out of only the 14-day limit implies the rest of the section reaches them. Again, no case law was read. Mark it **unverified**. The section's rulemaking is delegated to PUCO ("The commission shall hold hearings and adopt rules"), and those rules (ch. 4901:1-18) are scoped to public utilities.
- **R.C. 5117.11(E)** (https://codes.ohio.gov/ohio-revised-code/section-5117.11): "Notwithstanding sections 4933.12 and 4933.121 ..., no energy company shall purposely discontinue heating service during the months of December, January, and February to a residential customer for nonpayment during any period for which the customer is eligible to receive a credit under this program."
  - R.C. 5117.01(D): "'Energy company' means every retail propane dealer that distributes propane by pipeline, and every electric light, rural electric, gas, or natural gas company."
  - Its reach to municipal systems is open, like 4933.12. The credit program it keys on may be dormant; that was not checked.
- **R.C. 4933.17, deposit cap and interest** (https://codes.ohio.gov/ohio-revised-code/section-4933.17):
  - "No person, firm, or corporation engaged in the business of furnishing gas, natural gas, water, or electricity to consumers shall demand or require a consumer to deposit cash as security ... (A) If the proposed consumer is a freeholder who is financially responsible or ... able to give a reasonably safe guaranty in an amount sufficient to secure the payment of bills for sixty days' supply; (B) If the security is not demanded within thirty days of the initiation of service, except ... where the account ... is in arrears."
  - "In case no such security can be furnished, a deposit not exceeding ... the monthly average of the annual consumption ... plus thirty per cent may be required, upon which deposit interest at the rate of not less than three per cent per annum shall be allowed and paid ..., provided it remains on deposit for six consecutive months."
  - The text has no municipal carve-out. Whether "corporation" includes a municipal corporation is unverified.
- **R.C. 4933.28, back-billing for undercharges** (https://codes.ohio.gov/ohio-revised-code/section-4933.28): "Whenever a gas, natural gas, or electric light company operated for profit or not for profit has undercharged any residential customer as the result of a meter ... inaccuracy ... the company may only bill ... the three hundred sixty-five days immediately prior ..." Recovery is spread over 12 months with no interest or fees. Reach to municipal systems is open; **unverified**.
- **R.C. 4933.123**, annual disconnection report to PUCO and the consumers' counsel: applies to every "energy company" (5117.01). Reach to municipal systems is unverified.
- **Pipeline safety, R.C. 4905.90(J)(3)** (https://codes.ohio.gov/ohio-revised-code/section-4905.90): "Operator" includes "A public utility that is excepted from the definition of 'public utility' under division (A)(2) or (3) of section 4905.02 ..., when engaged in supplying or transporting gas by pipeline within this state". 4905.90(B): "'Gas' means natural gas, flammable gas, or gas which is toxic or corrosive." **PUCO pipeline safety does bind municipal and customer-owned systems (verified).**

### 3. Who governs municipal customer practices instead

- **The municipal legislative authority**, under home-rule utility powers:
  - Ohio Const. art. XVIII §4 (https://codes.ohio.gov/ohio-constitution/section-18.4): "Any municipality may acquire, construct, own, lease and operate within or without its corporate limits, any public utility the product or service of which is or is to be supplied to the municipality or its inhabitants".
  - R.C. 743.36 (https://codes.ohio.gov/ohio-revised-code/section-743.36): "When a municipal corporation is the owner of a natural gas plant ... the legislative authority thereof may provide for supplying natural gas, at rates to be determined by it, to persons living outside of and in the vicinity of such municipal corporation".
  - R.C. 743.34 and 743.44 cover erecting gasworks and acting outside the city's limits.
- R.C. 743.26 lets the city regulate the price **private** gas companies charge within it. It does not apply to the city's own system.
- No PUCO customer-practice jurisdiction; the only PUCO role is pipeline safety. The statutes in section 2 may apply directly, enforced in court; unverified.
- R.C. 743.04 (water-rent collection and liens) concerns water and was not used.

### 4. Other applicability dimensions

- **Sales outside the city:**
  - Ohio Const. art. XVIII §6 (https://codes.ohio.gov/ohio-constitution/section-18.6): "Any municipality, owning or operating a public utility for the purpose of supplying the service or product thereof to the municipality or its inhabitants, may also sell and deliver to others any transportation service of such utility and the surplus product of any other utility in an amount not exceeding in either case fifty per cent of the total service or product supplied by such utility within the municipality". The 50% cap is not a PUCO-jurisdiction trigger.
  - R.C. 743.36 has outside-city gas customers served "at rates to be determined by it" (the city).
  - **No Ohio text gives PUCO jurisdiction over a municipal gas system's outside-limits customers.** Contrast Kansas's 3-mile rule.
  - The R.C. 743.13 "one tenth" outside-rate cap covers water and electricity only: "rates charged therefor shall not exceed those within the municipal corporation by more than one tenth".
- **Ownership and operation:** the 4905.02(A)(3) wording is "owned **or** operated by any municipal corporation". A municipally operated but privately owned system, or the reverse, is out.
- **Customer-owned, not-for-profit:** 4905.02(A)(2), "exclusively by and solely for the utility's customers".
- **Size:** none for jurisdiction. Within PUCO rules, "small (natural) gas company" means 75,000 or fewer customers (4901:1-13-01(W),(X)).
- **Opt-in/opt-out elections:** none found for gas.
- **Producer/gatherer relief** (4905.03(E)): PUCO "may relieve any producer or gatherer of natural gas ... so long as the producer or gatherer does not engage in the distribution of natural gas to consumers." Pipeline safety still applies (4905.90(J)(1)).
- **Master-meter systems** (4905.90(K)): "An operator of a master-meter system is not a public utility under section 4905.02 or a gas or natural gas company under section 4905.03". Pipeline safety applies only.

### Row (one line per utility type)

- `municipal -> city ordinance (Const. XVIII §4, R.C. 743.36) + PUCO pipeline safety (4905.90(J)(3)) [verified]; NOT OAC 4901:1-13/-17/-18 (4905.02(A)(3), 4929.01(G)) [verified]; possibly R.C. 4933.12 winter rule, 4933.122 procedures (minus 14-day due date), 4933.17 deposit cap/3% interest, 4933.28 back-billing, 5117.11(E) [unverified]`
- `investor-owned natural gas company -> OAC 4901:1-13 (service), 4901:1-17 (deposits), 4901:1-18 (termination/PIPP) + R.C. 4933.12/.122/.17/.28 + 5117.11(E) [verified]`
- `cooperative / customer-owned not-for-profit -> excluded from "public utility" (4905.02(A)(2)) [verified]; PUCO pipeline safety [verified]; 4933.x statutes as for municipal [unverified]`
- `county/township/other district gas system -> not named in 4905.02(A)(3) exclusion [verified text]; status unverified`
- `propane/LP piped system -> pipeline safety as "flammable gas" operator (4905.90) [verified]; 5117 "energy company" includes "retail propane dealer that distributes propane by pipeline" [verified]; PUCO customer rules unverified`
- `master-meter operator -> not a public utility; pipeline safety only (4905.90(K)) [verified]`

### Could not verify

- Whether R.C. 4933.12, 4933.122, 4933.17, 4933.28 and 5117.11(E) bind municipal or cooperative gas systems. The text suggests 4933.122 does (its municipal carve-out covers only the 14-day due date), but no case law or AG opinion was read.
- Whether a county, township or regional authority gas system falls within the 4905.02(A)(3) exclusion.
- Whether a pure piped-propane distributor is a 4905.03 "gas company" (artificial gas).
- Whether the R.C. 5117 credit program, the trigger for 5117.11(E), is currently funded or operative.
- R.C. 4905.02's page shows a 2017 amendment as its latest entry. Later amendments were not checked.


---

## Illinois — verified (statutes read on ilga.gov; propane and the reach of 8-205 are interpretation, flagged below)

Sources fetched 2026-10-06 and saved under `put/src/IL_*.html|txt`. Official URL pattern: `https://www.ilga.gov/Documents/legislation/ilcs/documents/<DocName>.htm`. The old `fulltext.asp?DocName=` URLs now return an error page.

### 1. Regulated utility definition

220 ILCS 5/3-105 (DocName 022000050K3-105; history line "Source: P.A. 97-1128, eff. 8-28-12", which matches the cached il3105.txt):

- (a) "'Public utility' means and includes, except where otherwise expressly provided in this Section, every corporation, company, limited liability company, association, joint stock company or association, firm, partnership or individual ... that owns, controls, operates or manages, within this State, directly or indirectly, for public use, any plant, equipment or property used ... for or in connection with ... (1) the production, storage, transmission, sale, delivery or furnishing of heat, cold, power, electricity, water, or light ... (3) the conveyance of oil or gas by pipe line."
- (b) "'Public utility' does not include, however:
  - (1) public utilities that are owned and operated by any political subdivision, public institution of higher education or municipal corporation of this State, or public utilities that are owned by such political subdivision ... or municipal corporation and operated by any of its lessees or operating agents;
  - (3) electric cooperatives as defined in Section 3-119;
  - (4) the following natural gas cooperatives: (A) residential natural gas cooperatives that are not-for-profit corporations established for the purpose of administering and operating, on a cooperative basis, the furnishing of natural gas to residences for the benefit of their members ... and recognized by the Illinois Commerce Commission as such ...; and (B) natural gas cooperatives that are not-for-profit corporations ... that, prior to 90 days after the effective date of this amendatory Act of the 94th General Assembly, either had acquired or had entered into an asset purchase agreement to acquire all or substantially all of the operating assets of a public utility or natural gas cooperative ...;
  - (8) the ownership or operation of a facility that sells compressed natural gas at retail to the public for use only as a motor vehicle fuel".

The rule follows the statute:
- 83 Ill. Adm. Code 280 (deposits, billing, disconnection) cites as its authority the "Small Business Utility Deposit Relief Act [220 ILCS 35] and Sections 8-101, 8-206 and 8-207 of the Public Utilities Act" (cached `src/il280.txt`).
- 220 ILCS 35/2(h): "'Utility supplier' or 'utility' means a public utility as now or hereafter defined in Section 3-105 of The Public Utilities Act."
- Section 280.20 (definitions) does not define "utility" separately (checked in cached `src/il280.20.txt`).

How each type comes out:
- **Municipal:** OUT, under 3-105(b)(1). This also covers a city-owned system run by a lessee or operating agent.
- **Cooperative:** split.
  - OUT if it is a natural gas cooperative under (b)(4)(A), meaning residential, not-for-profit and ICC-recognised, or under (b)(4)(B), the grandfathered asset purchasers.
  - Any other gas cooperative is IN. (b)(3) excludes only electric cooperatives.
- **District/authority:** OUT when it is a "political subdivision", under (b)(1).
- **Small-system threshold:** none in the definition. There is a case-by-case exemption instead: 83 IAC 280.10 lets "Any entity ... file a petition requesting modification of or exemption from any Section of this Part".
- **Propane/LP:** not mentioned anywhere in 3-105. The definition turns on "heat ... light" furnished "for public use" and on "conveyance of oil or gas by pipe line". Whether a piped LP system serving the public is a public utility is UNVERIFIED, since no primary text addresses it. Bottled or tank delivery has no explicit exclusion either.

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

**65 ILCS 5/11-117-12.1** (DocName 006500050K11-117-12.1) sets a municipal cold-weather disconnection rule with its own threshold (20 °F, not the 32 °F in 8-205):

> "No gas or electric service furnished to residential users by a municipality shall be terminated for nonpayment of bills on: (i) any day when the National Weather Service forecast for the following 24 hours covering the area in which the residence is located includes a forecast that the temperature will be 20 degrees Fahrenheit or below; or (ii) any day preceding a holiday or a weekend when such a forecast indicates that the temperature will be 20 degrees Fahrenheit or below during the holiday or weekend. This amendatory Act of 1979 applies to all municipalities that own or operate a public utility, including home rule units. However, nothing in this Section shall prevent any municipality from establishing more stringent measures." (Source: P.A. 81-986.)

**65 ILCS 5/11-117-12.2** protects military service members:

> "(b) No municipality owning a public utility shall stop gas or electricity from entering the residential premises of which a service member was a primary occupant immediately before the service member entered military service for nonpayment for gas or electricity supplied to the residential premises. (c) Upon the return from military service ... the municipality shall offer the residential consumer a period equal to at least the period of the residential consumer's military service to pay any arrearages ..."

Eligibility under (d) requires a copy of orders for military service "in excess of 29 consecutive days" plus documentation that the service "materially affects his or her ability to pay". Under (e), "A violation of this Section constitutes a civil rights violation under the Illinois Human Rights Act." (Source: P.A. 97-913, eff. 1-1-13.)

**65 ILCS 5/11-117-12** allows a late-payment charge:

> "The corporate authorities of any municipality owning and operating a municipal utility plant shall, in addition to fixing utility rates, have the power to establish a service charge for the late payment of rates charged."

**305 ILCS 20/13** (Energy Assistance Act, DocName 030500200K13) sets an Energy Assistance Charge billing line, which municipal and cooperative systems must opt into. Under (b), "each public utility, electric cooperative ... and municipal utility, as referenced in Section 3-105 of the Public Utilities Act, that is engaged in ... the distribution of natural gas ... shall ... assess each of its customer accounts a monthly Energy Assistance Charge". This is limited by (k):

> "The charges imposed by this Section shall only apply to customers of municipal electric or gas utilities and electric or gas cooperatives if the municipal electric or gas utility or electric or gas cooperative makes an affirmative decision to impose the charge."

The same section also has a partial-payment allocation election:

> "a public utility, municipal utility, or electric cooperative may elect either: (i) to apply such partial payments first to amounts owed to the utility ... or (ii) ... on a pro-rata basis".

**Not reaching municipal systems** (these PUA sections are addressed to "public utility" or "public utility company"):
- 8-202 (winter termination notices, Nov–Mar)
- 8-203 (customer-requested shutoff, Oct–Mar)
- 8-206 (Dec 1–Mar 31 winter termination and deferred payment arrangement)
- 8-207 (winter reconnection)
- 8-209 (credit reporting)

Each of these says "public utility", or "electric or gas public utility" in 8-206.

8-205 is different. Its operative text says "Termination of gas and electric utility service to all residential users ... is prohibited" for the 32 °F forecast, and "(b) ... a utility may not terminate" for the 90 °F forecast. It does not use the word "public". Two things suggest it does not bind municipal systems:
- It sits inside the Public Utilities Act, whose subject is the 3-105 "public utility".
- The legislature enacted a separate, weaker 20 °F rule for municipalities (11-117-12.1).

That conclusion is INTERPRETATION, not verified text. No primary text was found that applies 8-205 to municipalities.

No deposit-interest, deposit-cap, medical-certificate or notice statute for municipal gas utilities was found in 65 ILCS 5/Div. 11-117. Sections 1–14 were read, plus 1.1 and 7.1, which deal with electric service areas. The search did not cover all of the ILCS.

### 3. Who governs municipal customer practices instead

The municipality's corporate authorities do. 65 ILCS 5/11-117-1 says "any municipality may ... (4) fix the rates and charges for the product sold and the services rendered by any such public utility; and (5) make all needful rules and regulations in relation thereto."

The ICC's role is limited to territorial agreements. 11-117-6(d): "The Illinois Commerce Commission's jurisdiction and authority over municipalities under this subsection shall be strictly limited to the approval of the agreement." Disputes go to circuit court under 11-117-6(e).

Each utility's accounts must be kept separately and audited annually by a CPA (11-117-13).

The governing statute caps protections from below only: municipalities may adopt "more stringent measures" than the 20 °F rule (11-117-12.1).

Pipeline safety is not researched here.

### 4. Other applicability dimensions

- **Cooperative carve-outs:** the (b)(4)(A) exclusion depends on ICC recognition, and (b)(4)(B) depends on a historic acquisition date. Both are facts about the specific entity.
- **Lessee-operated municipal systems** remain excluded under (b)(1) ("operated by any of its lessees or operating agents").
- **Inside vs outside city limits:**
  - 3-105 excludes municipal systems wholesale. No text gives the ICC jurisdiction over a municipal system's customers outside its limits.
  - 11-117-6(c): "A municipality that owns or operates a municipal natural gas utility shall have the exclusive right to provide natural gas service to all customers at metered locations that it is serving on the effective date of this amendatory Act of 1996, whether those customers are within the municipal limits of the municipality or at metered locations outside the municipal limits."
- **Opt-in:** the Energy Assistance Charge (305 ILCS 20/13(k)) applies to municipal and cooperative systems only on "an affirmative decision to impose the charge".
- **Customer class:**
  - Part 280's small-business deposit cap is keyed to "50 or less full-time employees" (220 ILCS 35/2(b)).
  - 8-205 and 8-206 key on gas being "the only source" or "primary source" of space heating.
- **Exemption by petition:** 83 IAC 280.10, for public utilities.

### Row (one line per utility type)

- `municipal -> 65 ILCS 5/11-117-12.1 (20°F no-termination), 11-117-12.2 (service-member no-stoppage + arrears period), 11-117-12 (late charge power), 305 ILCS 20/13 Energy Assistance Charge only if adopted; own ordinances otherwise; NOT 83 IAC 280 / PUA Art. 8 (3-105(b)(1)) [verified]`
- `investor-owned public utility -> 83 IAC 280 + 220 ILCS 35 + PUA 8-202..8-209 (incl. 8-205 32°F/90°F, 8-206 Dec1–Mar31) + 305 ILCS 20/13 [verified]`
- `gas cooperative (non-(b)(4)) -> same as public utility (3-105(a); only electric coops and (b)(4) gas coops excluded) [verified text; no ICC-regulated gas coop confirmed]`
- `gas cooperative under 3-105(b)(4)(A)/(B) -> not PUA/Part 280; 305 ILCS 20/13 only if adopted; own bylaws [verified]`
- `district/authority (political subdivision) -> not PUA/Part 280 (3-105(b)(1)); municipal-code 11-117 sections do not name districts [verified exclusion; no district-specific statute found]`
- `propane/LP piped system -> unclear whether a 3-105 "public utility" [unverified]`

### Could not verify

- Whether 8-205 (32 °F / 90 °F) reaches municipal systems. Its text says "utility", but it sits in the PUA.
- Whether a piped LP/propane system serving the public is a 3-105 public utility.
- Whether any ICC-regulated gas cooperative exists outside (b)(4).
- Whether any Illinois statute outside 65 ILCS 5/11-117 sets deposit, interest, medical or notice duties for municipal gas systems. Searched only Div. 11-117 and 305 ILCS 20/13.
- Political-subdivision gas districts: no specific statute was located.


---

## New York — partly verified (statute text read in a browser on nysenate.gov; raw files not saved; some reach questions unresolved)

**Source note.** nysenate.gov sits behind a Cloudflare challenge, so curl gets only "Just a moment..." and the API needs a key. The statute text below was read from the live pages at https://www.nysenate.gov/legislation/laws/PBS/<sec>, https://www.nysenate.gov/legislation/laws/GMU/<sec> and https://www.nysenate.gov/legislation/laws/PBA/1005 through a Chrome session on 2026-10-06. Copies could not be written to disk. Every quote is verbatim, with the site's line-wrap word joins repaired.

The 16 NYCRR quotes come from the cached Cornell LII copies `src/ny11.2.txt` and `src/ny13.1.txt`:
- https://www.law.cornell.edu/regulations/new-york/16-NYCRR-11.2
- https://www.law.cornell.edu/regulations/new-york/16-NYCRR-13.1

### 1. Regulated utility definition

**PSL §2(10) "gas plant":** "includes all real estate, fixtures and personal property operated, owned, used or to be used for or in connection with or to facilitate the manufacture, conveying, transportation, distribution, sale or furnishing of gas (natural or manufactured or mixture of both) for light, heat or power, but does not include property used solely for or in connection with the business of selling, distributing or furnishing of gas in enclosed containers."

**PSL §2(11) "gas corporation":** "includes every corporation, company, association, joint-stock association, partnership and person, their lessees, trustees or receivers appointed by any court whatsoever, owning, operating or managing any gas plant or thermal energy network". It then lists exceptions:
- "(a) except where gas is made or produced and distributed by the maker on or through private property solely for its own use or the use of its tenants and not for sale to others,
- (b) except where compressed natural gas is sold, distributed or furnished solely as a fuel for use in motor vehicles,
- (c) [manufactured gas sold to a gas corporation, 30% cap] ...
- (d) except where gas is made or produced solely from one or more alternate energy production facilities or distributed solely from one or more of such facilities to users located at or near a project site".

**PSL §2(16) "municipality":** "includes a city, village, town or lighting district, organized as provided by a general or special act, provided, however, that the counties of Nassau, Rockland, Suffolk and Westchester shall each be deemed a 'municipality' ...".

The PSL reaches municipalities by naming them in the operative sections:
- **§5(1)(b):** jurisdiction "shall extend ... To the manufacture, conveying, transportation, sale or distribution of gas ... and electricity for light, heat or power, to gas plants and to electric plants and to the persons or corporations owning, leasing or operating the same."
- **§65(1):** "Every gas corporation, every electric corporation and every municipality shall furnish and provide such service ... ." In §65(2)-(3): "No gas corporation, electric corporation or municipality shall ..." (discrimination, preference).
- **§66(2):** "Investigate and ascertain ... the quality of gas supplied by persons, corporations and municipalities".
- **§66(5):** "Examine all persons, corporations and municipalities under its supervision ... Whenever the commission shall be of opinion ... that the rates, charges or classifications or the acts or regulations of any such person, corporation or municipality are unjust, unreasonable ..."
- **§66(7):** "Require each municipality engaged in operating any works or systems for the manufacture and supplying of gas or electricity to make an annual report to the commission".

**HEFPA (PSL Art. 2):**
- **§30:** "This article shall apply to the provision of all or any part of the gas, electric or steam service provided to any residential customer by any gas, electric or steam and municipalities corporation or municipality." The phrase is garbled exactly like this on the official site.
- **§31(1):** "Every gas corporation, electric corporation or municipality shall provide residential service upon the oral or written request of an applicant".
- **§32(1):** "Any termination of residential utility service by utility corporations or municipalities shall be in accordance with all relevant provisions of this article."
- **§53:** "a reference to a gas corporation ... shall include ... any entity that, in any manner, sells or facilitates the sale or furnishing of gas or electricity to residential customers. No provision of this article ... [authorizes] the commission to waive compliance with any requirement of this article for any such corporation or other entity."

**Rules:**
- **16 NYCRR 11.2(a)** (Part 11, residential HEFPA rules) "governs the rights, duties and obligations of every gas corporation, electric corporation, gas and electric corporation, steam corporation and municipality subject to the jurisdiction of the commission by virtue of articles 2, 4 and 4-A of the Public Service Law". (a)(1)(i): "The term utility means any such gas corporation ... municipality, or any entity that, in any manner, sells or facilitates the sale, furnishing or provision of gas or electric commodity to residential customers; provided, however, that the term does not include any municipality that is exempt from commission regulation by virtue of section 1005(5)(g) of the Public Authorities Law."
- **16 NYCRR 13.1(a)(1)** (nonresidential) has the same structure, for "every gas, electric and steam corporation or municipality subject to the jurisdiction of the commission by virtue of articles 4 and 4-A". 13.1(b)(1) carries the same 1005(5)(g) carve-out.

**PBA §1005, the "g." clause.** It is located in the subdivision-5 contract terms on the official page; the exact subdivision numbering was not confirmed in the flattened text. It reads: "That the rates, services and practices of the purchasing, transmitting and/or distributing public agencies or companies in respect to the power generated by such projects shall be governed by the provisions and principles established in the contract, and not by regulations of the public service commission or by general principles of public service law regulating rates, services and practices". The clause concerns NYPA **power**, i.e. electricity. It does not touch a municipal gas system.

How each type comes out:
- **Municipal:** IN. A city, village, town or lighting district, or one of the four named counties, is a "municipality" named in §§30-32, 65 and 66. Part 11 and Part 13 cover it unless it is 1005(5)(g)-exempt, which is electric only.
- **Cooperative:** IN. §2(11) covers any "association ... owning, operating or managing any gas plant". There is no cooperative exclusion.
- **District/authority:** a "lighting district" is a municipality, so IN. No text was found on other districts or authorities running gas.
- **Small-system threshold:** none in the definitions. §66(13) allows an Article 4 exemption only (quoted in §4 below). It does not reach HEFPA, Article 2.
- **Propane/LP:** gas "in enclosed containers" (bottled or tank delivery) is OUT under §2(10). A piped propane distribution system is UNVERIFIED. Nothing read says whether LP is "gas (natural or manufactured or mixture of both)".

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

In New York, municipal gas systems are inside the PSC framework rather than outside it, so the HEFPA statute (§§30-53) and 16 NYCRR Parts 11 and 13 apply directly. The quotes are in §1.

The one carve-out found is the 1005(5)(g) exemption in 11.2 and 13.1, which is tied to NYPA power contracts. It is not a gas carve-out.

### 3. Who governs municipal customer practices instead

The PSC governs, concurrently with the local legislative body:
- **GML §360(7):** "The method of operation of and the rates, rentals and charges for such service and the procedure for their collection shall be fixed by the legislative body of the municipal corporation."
- **PSL §66(5):** the PSC may find a municipality's "rates, charges or classifications or the acts or regulations" unjust after a hearing "upon its own motion or upon complaint".

How the two powers fit together (whether the PSC sets municipal gas rates in advance or reviews them only on complaint) was NOT resolved from primary text. For customer practices, HEFPA and Part 11 bind directly.

### 4. Other applicability dimensions

**Small gas corporations, PSL §66(13):** "Where the permission granted such corporation pursuant to section sixty-eight is to supply gas only to less than twenty customers specified by the commission, the commission may, if the public interest permits, exempt such corporation from compliance with all or any of the provisions of this article except those affecting matters of public safety and the provisions of sections sixty-five, sixty-eight and seventy-four."
- This is discretionary.
- It covers Article 4 only. §53 bars waiving Article 2 for the entities it covers.
- It applies to a "corporation", so whether it reaches a municipality is unverified.

**Residential vs nonresidential:** Part 11 (HEFPA) covers residential customers, via Articles 2, 4 and 4-A. Part 13 covers nonresidential customers, via Articles 4 and 4-A.

**Outside the territorial limits:**
- GML §361(1): a municipality "may sell such surplus outside the municipal corporation". Extending service into another municipality that is already served "shall not be effected without the approval of the public service commission."
- No inside/outside distinction in PSC customer-rule jurisdiction was found. HEFPA §30 attaches to "any residential customer" of the municipality.

**NYPA-power municipals:** exempt under PBA §1005(5)(g) as carried into 11.2 and 13.1. This is electric only.

**Self-use gas:** gas made and distributed on private property "solely for its own use or the use of its tenants" is excluded under §2(11)(a).

### Row (one line per utility type)

- `municipal (city/village/town/lighting district) -> HEFPA PSL §§30-53 + 16 NYCRR Part 11 (residential) + Part 13 (nonresidential) + PSL §§65-66; rates fixed locally (GML §360(7)) subject to PSC §66(5) review [verified text; rate-setting interplay unverified]`
- `investor-owned gas corporation -> HEFPA + Parts 11/13 + Art. 4 [verified]`
- `cooperative/association -> same as gas corporation (§2(11) "association") [verified text]`
- `gas corporation <20 customers (§68 permission) -> HEFPA + Parts 11/13; Art. 4 exemptible except §§65, 68, 74 + safety (§66(13)) [verified]`
- `propane/LP in enclosed containers -> outside PSL (§2(10)) [verified]; piped LP system -> [unverified]`
- `other district/authority gas -> [unverified]`

### Could not verify

- Saved raw files of PSL, GML or PBA. Cloudflare blocked curl; the text was read in a browser only.
- How PSC and local rate-setting fit together for municipal gas (GML §360(7) vs PSL §66(5)).
- Whether piped propane counts as "gas" under §2(10)/(11).
- Whether §66(13) applies to municipalities.
- The exact subdivision numbering of PBA §1005(5)(g).
- Gas districts or authorities other than lighting districts.
- Whether any municipal gas utility operates in New York today. Not researched.


---

## California — verified

Sources. All text below was read on leginfo.legislature.ca.gov, the official site. curl gets a Cloudflare 403 there, so I read the pages in a browser and checked each quoted phrase against the official page. I read the full text on the california.public.law mirror; raw copies are in `src/CA_pl_*.txt`. Every quote marked "verified" matched the official text exactly.
URL pattern: `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=PUC&sectionNum=<n>.`

### 1. Regulated utility definition

**PUC §216(a)(1)** (verified): "'Public utility' includes every common carrier, toll bridge corporation, pipeline corporation, gas corporation, electrical corporation, ... where the service is performed for, or the commodity is delivered to, the public or any portion thereof."

**PUC §222** (verified): "'Gas corporation' includes every corporation or person owning, controlling, operating, or managing any gas plant for compensation within this state, except where gas is made or produced on and distributed by the maker or producer through private property alone solely for his own use or the use of his tenants and not for sale to others."

The definitions behind "corporation" and "person" leave out public entities:
- **§204** (verified): "'Corporation' includes a corporation, a company, an association, and a joint stock association."
- **§205** (verified): "'Person' includes an individual, a firm, and a copartnership."
- Neither definition names municipalities or districts.

**Cal. Const. art. XII, §3** (verified, leginfo CONS) makes *private* operators the public utilities: "Private corporations and persons that own, operate, control, or manage a line, plant, or system for ... the production, generation, transmission, or furnishing of heat, light, water, power ... directly or indirectly to or for the public ... are public utilities subject to control by the Legislature."

**PUC §221** (verified) defines "gas plant" as plant for "furnishing of gas, natural or manufactured, except propane, for light, heat, or power." Propane plant is therefore not "gas plant", and a propane operator is not a "gas corporation".

**Propane distribution systems: safety only.** PUC Ch. 4.1, §4451 et seq.
- **§4451(b)** (verified): "'Distribution system' means a system of pipes, operated by a person or corporation other than a public utility, serving 10 or more customers, within a citywide area, an apartment house, ... a mobilehome park with two or more customers, or any system if a portion of the system is located in a public place".
- **§4452(a)** (mirror text; the (c)(2) phrase verified): a "propane safety inspection and enforcement program ... to ensure compliance with the federal pipeline standards".
- **§4452(c)** excludes "(1) Single customers served by single tanks. (2) Distribution systems, other than mobilehome parks, that serve less than 10 customers, unless any portion of the system is located in a public place".
- Nothing in Ch. 4.1 regulates billing, deposits or disconnection (mirror read of §§4451-4459).

Summary:
- **Municipal: out.** §§204/205 do not reach municipal corporations, and Const. art. XII §3 says "private". Municipal utilities are governed by PUC Div. 5 instead.
- **Cooperative: n.a.** No gas-cooperative category was found. A private association would come within "corporation" (§204), so a gas co-op would be **in** by text. *Unverified* as applied.
- **District/authority: out of CPUC jurisdiction.** Municipal utility districts (PUC Div. 6) and public utility districts (Div. 7) have their own customer statutes (§2 below).
- **Small-system threshold:** none in §§216/222. The only count threshold is the propane safety threshold of 10 customers (§4452(c)). §10011.5 has a 10,000-connection test, but it applies to municipal *water* only.
- **Propane/LP: out** of "gas corporation" (§221). CPUC covers propane distribution systems for safety only, at 10 or more customers or any mobilehome park (§§4451-4452).

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

California writes parallel statutes for each type of public owner. Each set copies the IOU rules in PUC §§777-779.5 almost word for word.

**Municipal corporations — PUC Div. 5, Ch. 1, Art. 1 [§§10001-10014].**
- **Scope, §10001** (verified): "'Public utility' as used in this article, means the supply of a municipal corporation alone or together with its inhabitants, or any portion thereof, with water, light, heat, power ...". Gas is reached through "heat".
- §10011 (verified) names gas outright: "No electrical, gas, heat, or water public utility shall ...".
- **Termination, §10010(a)-(b)** (verified): "No public utility furnishing light, water, power, or heat may terminate residential service for nonpayment of a delinquent account unless the public utility first gives notice ... as provided in Section 10010.1." It bars termination "During the pendency of an investigation ...", "When a customer has been granted an extension ...", and "On the certification of a licensed physician and surgeon that to do so will be life threatening to the customer ...".
  - Amortization is "not to exceed 12 months" (§10010(c), (e)).
  - **Appeal, §10010(d)** (verified): "may appeal the determination to the governing body of the municipal corporation."
- **Notice, §10010.1** (verified):
  - 10-day mailed notice, sent "not earlier than 19 days from the date of mailing the public utility's bill for services". The 10-day period starts 5 days after mailing.
  - 24-hour contact attempt, or a 48-hour posted or mailed notice.
  - A "third-party notification service" for customers aged 65 or older and dependent adults.
  - Required notice contents, at (d)(1)-(7) (mirror).
  - "Any service wrongfully terminated shall be restored without charge" (f) (mirror).
- **Timing, §10011** (verified): no cessation "on any Saturday, Sunday, legal holiday, or at any time during which the business offices of the public utility are not open to the public."
- **Deposits, §10009.6** (verified):
  - (a) the deposit decision "shall be based solely upon the creditworthiness of the applicant".
  - (b) "No municipal corporation owning or operating a public utility furnishing services for residential use to a tenant ..." may collect a prior tenant's arrears from a subsequent tenant or the owner. It "may collect a deposit from the tenant service applicant".
  - (c) the utility "may not demand or receive security in an amount that exceeds twice the estimated average periodic bill or three times the estimated average monthly bill."
  - (d) the deposit is applied to the final bill. (e) the section does not apply to master-metered apartments.
- **Landlord-customer notices** (mirror text; same article):
  - §10009: individually metered service; 10-day notice to occupants and their right to become customers.
  - §10009.1: master-metered service; 15-day posted notice, and no termination when a health officer certifies a threat, (e)(5).
- **§10011.5** (verified): offer an alternative to in-person transactions during business hours. Applies to municipal gas with no size floor; the 10,000-connection floor applies to water only.

**Municipal utility districts — PUC Div. 6 (Municipal Utility District Act), Art. 5 [12801-…]** (mirror text; §12823(a) verified):
- §12823(a): "A district furnishing its inhabitants with light, water, power, or heat shall not terminate residential service for nonpayment ... unless the district first gives notice ...".
- Medical-certificate and dispute bars appear as in §10010. §12823(c) differs: amortization is "generally within 12 months, but a district may grant a longer period".
- Landlord notices are in §§12822-12822.1.

**Public utility districts — PUC Div. 7 (Public Utility District Act), Art. 3** (mirror text; §16482(a) verified):
- §16482(a): "No district furnishing its inhabitants with light, water, power, heat, or means for the disposition of garbage ... may terminate residential service for nonpayment ... unless ...".
- Notice rules are in §16482.1; landlord notices in §§16481-16481.1.

**All other special districts — Gov. Code Title 6, Div. 1, Ch. 9.6 "District Utility Services" [60370-60375.5]** (verified on leginfo):
- §60370: "'district' means any agency of the state, formed pursuant to general law or special act, for the local performance of governmental or proprietary functions within limited boundaries. 'District' shall not include the state, any city, city and county, county, or school district."
- §60372(a): "No district furnishing its inhabitants with light, water, power, or heat may terminate residential service for nonpayment ... unless the district first gives notice ...".
- §60373: 10-day mailed notice, sent "not earlier than 19 days from the date of mailing", plus a 48-hour contact attempt and listed notice contents.
- §60374: "No district shall, by reason of delinquency in payment for any electric, gas, heat, or water services, cause cessation ... on any Saturday, Sunday, legal holiday ...".
- §60375.5: the deposit decision rests "solely upon the credit worthiness".
- §60371: landlord and master-meter notices.

**For comparison, IOU statutes (gas corporations)** (verified):
- §779(a): "No electrical, gas, heat, or water corporation may terminate residential service ... unless ...". Appeal goes to "the commission" (§779(d), mirror).
- §779.5: the deposit decision "shall be based solely upon the credit worthiness".

No California statute found in this search requires municipal or district gas utilities to pay interest on deposits. No statute found sets a winter or cold-weather moratorium for municipal or district gas.

### 3. Who governs municipal customer practices instead

- **Municipal:** the governing body.
  - Cal. Const. art. XI §9(a) (verified): "A municipal corporation may establish, purchase, and operate public works to furnish its inhabitants with light, water, power, heat ...".
  - Disputes under §10010(d) are appealed to "the governing body of the municipal corporation".
  - The statutory floor is PUC Div. 5 Art. 1, enforced by private action. Nothing found gives an agency enforcement role.
- **MUD, PUD and other districts:** the district board. The appeal clauses in §§12823/16482 were not read in full.
- **Propane systems:** CPUC handles safety only (§4452). Customer practices for LPG in mobilehome parks may fall under the Mobilehome Residency Law (Civ. Code §798.x). *Unverified, not researched.*
- **Federal pipeline safety for municipal natural-gas systems:** not researched for California.

### 4. Other applicability dimensions

- **Outside city limits:**
  - Const. art. XI §9(a) (verified): a municipal corporation "may furnish those services outside its boundaries, except within another municipal corporation which furnishes the same service and does not consent."
  - PUC §10004 (mirror): it "may operate a public utility within or without the corporate limits".
  - No statute found that gives CPUC jurisdiction over a municipal's customers outside its limits. *Unverified either way*; the case law, e.g. County of Inyo v. PUC, was not read.
- **Privatized local-agency projects:** §10013 (mirror) requires a privatizer to get a CPUC determination "that the proposed privatization project is not a public utility within the meaning of Section 216".
- **Master-metered vs individually metered** service changes which notice applies (§§10009/10009.1). §10009.6 deposit rules exclude master-metered apartment buildings.
- **Customer-count thresholds:**
  - Gas: none for the municipal or district statutes.
  - Propane safety: 10 or more customers, or any mobilehome park, or any part of the system in a public place (§4452(c)).
  - §10011.5 (10,000 connections) applies to water only.

### Row (one line per utility type)
- `municipal (city/county) -> PUC Div.5 Art.1: §§10009, 10009.1, 10009.6 (deposit cap 2x periodic / 3x monthly; creditworthiness only), 10010, 10010.1, 10011, 10011.5; governing body hears appeals; NOT CPUC GOs/tariff rules (PUC §§204/205/222; Const XII §3) [verified]`
- `investor-owned gas corporation -> CPUC jurisdiction (PUC §§216, 222) + PUC §§777, 779, 779.1, 779.5, 779.6 + CPUC tariffs/decisions [verified; tariff rules per prior survey]`
- `municipal utility district (Div. 6) -> PUC §§12822, 12822.1, 12823, 12823.1 [§12823(a) verified; rest secondary-mirror]`
- `public utility district (Div. 7) -> PUC §§16481, 16481.1, 16482, 16482.1 [§16482(a) verified; rest secondary-mirror]`
- `other special district (any general/special-act district; not city/county/school) -> Gov. Code §§60370-60375.5 [verified]`
- `cooperative -> n.a. (no gas co-op class found); by text a private association is a "corporation" under §204, so it would be a gas corporation [unverified as applied]`
- `propane/LP distribution system -> not a gas corporation (§221 "except propane"); CPUC propane safety program only, ≥10 customers / any mobilehome park (§§4451-4459); no customer-protection statute found [verified for safety scope]`

### Could not verify
- CPUC jurisdiction over municipal customers outside city limits. No statute found; the case law was not read.
- Whether Div. 6/7 districts appeal disputes to their board. §§12823(d) and 16482(d) were not read in full.
- Whether any CPUC General Order or rule, beyond propane safety, reaches municipal or district gas. None found.
- Customer protections for propane customers in mobilehome parks (Civ. Code Mobilehome Residency Law). Not researched.
- Whether federal or state pipeline-safety oversight applies to municipal natural-gas systems in California. Not researched.


---

## Georgia — partly verified

Sources:
- **O.C.G.A. statutes are secondary.** I read them on the law.onecle.com mirror (page dated 2016; raw copies in `src/GA_oc_*.txt`). I then checked each quoted phrase against the Justia 2025 Georgia Code mirror, read in a browser (curl gets a 403). Every quote matched both mirrors. No official Georgia code text was reachable, so every statute claim is **secondary**, from two mirrors that agree.
- **PSC rules are treated as verified.** I read them on Cornell LII (Ga. Comp. R. & Regs.), saved in `src/GA_r_*.txt`, the same standard the prior survey used.

### 1. Regulated utility definition

**O.C.G.A. §46-2-20(a)** (secondary): the commission "shall have the general supervision of all ... gas or electric light and power companies".

**§46-2-21(b)(5)** (secondary): jurisdiction extends to "Gas and electric light and power companies, or persons owning, leasing, or operating public gas plants or electric light and power plants furnishing service to the public."

**§46-1-1** (secondary) defines:
- (5) "'Gas company' means any person certificated under Article 2 of Chapter 4 of this title to construct or operate any pipeline or distribution system ... for the transportation, distribution, or sale of natural or manufactured gas."
- (6) "'Person' means any individual, partnership, trust, private or public corporation, municipality, county, political subdivision, public authority, cooperative ...".
- (9) "'Utility' means any person who is subject in any way to the lawful jurisdiction of the commission."
- So in Georgia, "gas company" turns on holding a certificate.

**Certificate article, Ch. 4 Art. 2 (§§46-4-20 to 46-4-35)** (secondary):
- §46-4-21(a): no person may "construct or operate ... any pipeline or distribution system ... for the transportation, distribution, or sale of natural or manufactured gas without first obtaining from the commission a certificate".
- §46-4-21(c): "As to distribution and sales in intrastate commerce, all gas pipeline systems shall be subject to the regulation and jurisdiction of the commission in all respects, including, but not limited to, rates, charges, rules, regulations, service, ... and such other matters involving a privately owned gas public utility distribution system as are subject to the regulation or jurisdiction of the commission."
- **§46-4-33, the municipal exclusion:** "Notwithstanding any other statute or ordinance to the contrary, the requirements of this article for a certificate of public convenience and necessity shall apply to each and every individual and to each and every firm or corporation, whether public or private, excepting only municipal corporations and counties of this state."
- §46-4-30, on extension disputes: "This Code section shall not apply to extensions of gas distribution systems by municipalities and counties of this state."
- **§46-4-32, LPG:** "Nothing in this article shall be construed to apply to liquefied petroleum gas sold in liquid form under pressure."

**Natural Gas Competition and Deregulation Act, Ch. 4 Art. 5 (§§46-4-150 to -166)** (secondary):
- §46-4-152(14): "'Person' means any corporation, whether public or private; ... including a cooperative or an electric membership corporation."
- (13): "'Marketer' means any person certificated by the commission to provide commodity sales service or distribution services pursuant to Code Section 46-4-153".
- (10): "'Electing distribution company' means a gas company which elects to become subject to the provisions of this article".
- (11.1): "Gas activities" "shall not mean the production, transportation, marketing, or distribution of liquefied petroleum gas."

**Municipal Gas Authority of Georgia, §46-4-80 et seq.** (secondary):
- §46-4-80: the authority exists to secure supply for "political subdivisions of this state [that] now own and operate gas distribution systems" and "to assist in the financing of ... municipal gas systems".
- §46-4-95: its purpose is supply "to those political subdivisions ... identified in Code Section 46-4-100".
- It is a wholesale and joint-action supplier, not a retail utility. Nothing read places it under PSC customer rules.

Summary:
- **Municipal: out** of certificate and rate/service regulation (§46-4-33), except for safety (§46-2-20(i), section 3 below). The same holds for **counties**.
- **Cooperative:** an EMC may sell gas only as or through a certificated marketer. An "EMC gas affiliate" is defined in §46-4-152(10.4) and applies for a certificate under §46-4-153. Such a seller is **in**, as a marketer. No retail gas-cooperative category was found.
- **District/authority:**
  - Not excepted by §46-4-33, whose only exceptions are "municipal corporations and counties". A gas authority created by local act would therefore be **in** by text. *Unverified* as applied; I read no local-act authorities.
  - MGAG itself is wholesale (n.a.).
- **Small-system threshold:** none found.
- **Propane/LP: out** (§46-4-32; §46-4-152(11.1)).

### 2. Customer rules reaching municipal (or other non-jurisdictional) systems anyway

**PSC gas disconnection rules (Ch. 515-3-3, verified on Cornell) bind only jurisdictional sellers:**
- 515-3-3-.04, "Seasonal Restrictions": "Other rules notwithstanding, a LDC, EDC, Regulated Provider, or marketer shall not discontinue service to a residential consumer for an unpaid bill between November 15 and March 15 if:" the consumer signs an installment agreement, keeps current, and "(c) The forecasted local low temperature for a 48-hour period beginning at 8:00 A.M. on the date of the proposed disconnection is below 32° Fahrenheit."
- 515-3-3-.02(A) requires an LDC to give "written notice of the proposed disconnection at least five (5) days prior".
- 515-3-3-.03 sets a medical hold for "serious illness" with a physician statement: one month, renewable once.
- 515-3-3-.10 sets penalties for "any person, firm, or corporation subject to the jurisdiction of the Commission".
- 515-3-1-.01 defines "Company" as entities "subject by law to the jurisdiction or control of the Commission".
- Ch. 515-3-2 is the older electric-and-gas chapter. Its text now speaks of electric utilities: 515-3-2-.01 says "No residential electric utility service ...", and 515-3-2-.04 has a 24-hour freezing test. Gas is handled in 515-3-3.
- None of these reach a municipal or county gas system. Those systems sit outside PSC rate and service jurisdiction (§46-4-33; §46-4-21(c) "privately owned").

**Municipal-specific customer statutes:** none found for gas.
- O.C.G.A. §36-60-17 (secondary, title read only) is water-only: "Water Supplier's Cut Off of Water to Premises Because of Indebtedness of Prior Owner ...".
- No section in Title 36 Ch. 60 or Title 46 Chs. 1, 2 or 4 sets deposit, disconnection, medical or winter duties for municipal gas systems.

### 3. Who governs municipal customer practices instead

- **The governing body (city council or county commission)** sets rates and customer practices by ordinance. This is an inference from the exclusions above; *secondary*. I did not read the constitutional or home-rule grant (Ga. Const. art. IX §II ¶III).
- **The PSC for pipeline safety only.** §46-2-20(i) (secondary): "The commission shall have the power and authority to prescribe rules and regulations for the safe installation and safe operation of all natural gas transmission and distribution facilities within this state, including, without limitation, all natural gas transmission and distribution facilities which are owned and operated by municipalities within this state." §46-4-1 allows civil actions to enforce those safety rules.

### 4. Other applicability dimensions

- **Certificate status is the switch.** Every non-municipal, non-county retail gas seller needs a certificate (§46-4-33) and comes under PSC rules. Inside that group, the 515-3-3 rules split obligations among LDC, EDC (Atlanta Gas Light), Regulated Provider and marketer. Marketer deposit rules (§46-4-156(h); 515-7-9-.04) are in the prior survey.
- **Election:** a gas company can opt in to Art. 5 as an "electing distribution company" (§46-4-152(10)). That changes which provisions apply to it (EDC/marketer vs LDC).
- **Outside city limits:** the municipal exception in §46-4-33 contains no territorial limit. No statute was found that extends PSC jurisdiction to a municipal's customers outside its boundaries. *Unverified either way.*
- **Customer-count thresholds:** none found.

### Row (one line per utility type)
- `municipal (city) or county gas system -> no PSC customer rules (O.C.G.A. §46-4-33 exception; §46-4-21(c) "privately owned"); PSC pipeline-safety rules only (§46-2-20(i)); customer practices by local ordinance [secondary]`
- `investor-owned LDC (e.g., Atmos) -> PSC jurisdiction (§§46-2-20(a), 46-4-21) + Ga. Comp. R. & Regs. 515-3-3 (.01, .02(A), .03, .04, .10 read; .05(A), .06(A) LDC titles only) [rules verified; statutes secondary]`
- `electing distribution company (AGL) / marketer / regulated provider -> Art. 5 (§§46-4-150 to -166, e.g. §46-4-156(h) deposit) + 515-3-3 (.02(B), .04, .07-.09) + 515-7 [rules verified; statutes secondary]`
- `cooperative / EMC gas affiliate -> only as a certificated marketer (§46-4-152(10.4),(14); §46-4-153) -> marketer rules [secondary]`
- `gas authority/district (non-municipal, non-county) -> by text not excepted from certificate requirement (§46-4-33) -> PSC rules would apply [unverified as applied]; MGAG = wholesale, n.a. [secondary]`
- `propane/LP -> outside Art. 2 and Art. 5 (§46-4-32; §46-4-152(11.1)); no PSC customer rules found [secondary]`

### Could not verify
- Official O.C.G.A. text. Every statute quote comes from two mirrors (onecle, dated 2016; Justia 2025) and is secondary.
- Ga. Const. home-rule and utility-service grants to cities and counties. Not read.
- Whether local-act gas authorities exist and whether the PSC treats them as jurisdictional.
- PSC jurisdiction over municipal customers outside city limits. No text found.
- Which agency regulates LPG safety (likely the Safety Fire Commissioner). Not researched.
- Any municipal-gas deposit or disconnection statute outside Title 36 Ch. 60 and Title 46. I did not search exhaustively; full-text search of the official code was unavailable.
- The Ga. PSC consumer page's citation of "Rule 515-3-1-.10(2)(3)" for LDC deposits. Per the prior survey, it is still unverified and looks stale.


---


---

# Summary table: utility type × state → rule sets that apply

**Abbreviations**
- **Comm:** the state commission's customer-service, deposit and disconnection rules.
- **Safety:** commission pipeline-safety jurisdiction only.
- **Own:** the governing body's ordinance or board rules.
- **—:** no class or statute found.

Labels: [v] verified, [m] mirror, [s] secondary, [u] unverified.

| State | Municipal (city/town) | Investor-owned / private | Cooperative | District / authority / other public body | Propane / LP |
|---|---|---|---|---|---|
| **OK** | Own + 11 O.S. §35-107 (deposit refund/forfeiture, DV waiver) + §35-102.1; Safety (52 O.S. §5). Not OAC 165:45 (17 O.S. §151 "except cities, towns, or other bodies politic") [v] | OAC 165:45 + 17 O.S. §180.12 [v] | n.a. (18 O.S. §441-105 bars LCAs from rural gas) [v] | Public trust: out of OCC (74 O.S. §9052(5)) [v]; whether §35-107 binds a trust [u] | Tank: LP Gas Act, safety only [v]; piped [u] |
| **LA** | No election: Own (R.S. 33:4163), LPSC safety only (Const. IV §21(C)); 45:845-848 deposit interest excluded (45:850) [v]. Elected LPSC (45:1164.1+ / 33:4491): LPSC General Orders; 45:848 still excluded [v] | Outside Orleans: LPSC General Orders (R-29706 weather etc.) + 45:845-848 [v]. Orleans: 45:845-848 + city council [council s] | — [u] | Gas utility district (33:4301): own board, rates unreviewable (33:4305(C)), outside LPSC and 45:845-849 [v] | 33:1377 only [u] |
| **NM** | No election: LIUAA winter rules (27-6-17, 27-6-18.1) + "reasonable" deposit (3-23-1(A)); not 62-13-13, 62-8-10, 17.5.410 or 17.10.650 NMAC (62-3-3, 62-6-4) [v]. Elected (62-6-5): full Public Utility Act + NMAC + LIUAA [v] | NMAC 17.5.410 + 17.10.650, 62-13-13, 62-8-10, LIUAA [v] | Same as investor-owned (62-3-3; LIUAA names "distribution cooperative") [v] | County system: as municipal [v; LIUAA reach u]. Gas association (NMSA 3-28): out unless it elects in (3-28-21) [v]; LIUAA [u] | Piped LP serving the public = public utility [v]; bottled LP out [v] |
| **AR** | Own; not APSC (Ark. Code §§23-2-302(a)(1)(C), 14-200-112, 23-4-201(b)) [m]; §23-4-206 deposit interest and §23-4-204 may reach [u] | APSC General Service Rules (deposits §4, Cold Weather 6.15, Medical) + §§23-4-202..206 [v rules / m statutes] | — [u] | Improvement district: out (§23-2-302) [m]. Leased to a nonprofit: rate-exempt (§23-4-201(b)) [m] | Tank: LP Gas Board Act only [m]; piped [u] |
| **KS** | Own + K.S.A. 12-822 (deposit interest at the KCC rate, separate account, escheat) + 12-808c (3-month deposit cap, lien, tenants) + Safety. Not KCC Billing Standards or Cold Weather Rule (66-104(b)) [v]. More than 3 mi outside: KCC terms jurisdiction unless 66-104f(a)(1)-(5) all met; 25% petition [v] | KCC Billing Standards + Cold Weather Rule + 12-822 [v; Cold Weather scope s]. Principally in one city: city regulates unless relinquished (66-104(c), 66-104e) [v] | As investor-owned [v]. Exempt if member-owned, no full-time staff, ≤100 customers (66-104c) [v] | Any political subdivision = "municipality" for 12-808c [v]; 66-104(b) exclusion for non-city bodies [u] | [u] |
| **OH** | Own (Const. XVIII §4, R.C. 743.36) + Safety (4905.90). Not OAC 4901:1-13/-17/-18 (4905.02(A)(3)) [v]. R.C. 4933.12 winter, 4933.122, 4933.17 deposit/3% interest, 4933.28 may reach [u] | OAC 4901:1-13/-17/-18 + R.C. 4933.x + 5117.11(E) [v] | Customer-owned not-for-profit excluded (4905.02(A)(2)) + Safety [v] | County/township: not named in the exclusion [u] | Piped: safety + 5117 "energy company" [v]; PUCO customer rules [u]. Master meter: safety only (4905.90(K)) [v] |
| **IL** | 65 ILCS 5/11-117-12.1 (no shutoff at ≤20 °F), 11-117-12.2 (service members), 11-117-12 (late charge), 305 ILCS 20/13 charge if opted in; otherwise Own. Not 83 IAC 280 or PUA Art. 8 (3-105(b)(1)) [v]; 8-205 (32 °F) reach [u] | 83 IAC 280 + 220 ILCS 35 + PUA 8-202..8-209 [v] | Not under (b)(4): as investor-owned [v text]. Under (b)(4)(A)/(B): out; 305 ILCS 20/13 opt-in [v] | Political subdivision: out (3-105(b)(1)) [v] | Piped [u] |
| **NY** | IN: HEFPA PSL §§30-53 + 16 NYCRR Part 11 (residential) + Part 13 (nonresidential) + PSL §§65-66; rates set locally (GML §360(7)) [v text; rate interplay u] | Same + Art. 4 [v] | Same as gas corporation (§2(11) "association") [v] | Lighting district = "municipality" [v]; others [u] | Enclosed containers out (§2(10)) [v]; piped [u]. Under 20 customers: Art. 4 waivable except §§65, 68, 74 and safety (§66(13)) [v] |
| **CA** | PUC Div. 5 Art. 1: §§10009, 10009.1, 10009.6 (deposit cap 2× periodic / 3× monthly), 10010, 10010.1, 10011, 10011.5; appeals to governing body. Not CPUC (§§204/205/222; Const. XII §3) [v] | CPUC + §§777, 779-779.6 + tariffs [v] | No class; by text a §204 "corporation" [u] | Municipal utility district §§12822-12823.1 [12823(a) v, rest m]; public utility district §§16481-16482.1 [16482(a) v, rest m]; other districts Gov. Code §§60370-60375.5 [v] | Not a gas corporation (§221 "except propane"); CPUC safety at ≥10 customers or any mobilehome park (§§4451-4452) [v] |
| **GA** | Own; no PSC customer rules (O.C.G.A. §46-4-33 exception); PSC safety (§46-2-20(i)) [m] | LDC: PSC + Rule 515-3-3 (Nov 15-Mar 15 / below 32 °F, medical, notice) [rules v, statutes m]. AGL (electing distribution company) / marketers: Art. 5 (§46-4-156(h)) + 515-3-3 + 515-7 [rules v, statutes m] | EMC: only as a certificated marketer [m] | Non-municipal authority: not excepted, so PSC by text [u]. MGAG: wholesale, n.a. [m] | Excluded (§46-4-32, §46-4-152(11.1)) [m] |

**What the table says, in brief**
- **Municipal systems are outside the commission's customer rules in 9 of 10 states.**
  - New York is the exception: its municipal gas systems sit inside the Public Service Law (HEFPA, Parts 11 and 13).
  - Louisiana and New Mexico municipals can opt in by election.
- **Six states impose specific customer-protection duties on municipal gas systems by separate statute** (verified):
  - Kansas: 12-822 deposit interest; 12-808c deposit cap.
  - Illinois: 20 °F shutoff ban; service-member protections.
  - New Mexico: LIUAA winter rules; "reasonable" deposits.
  - Oklahoma: §35-107 deposit refund and forfeiture.
  - California: Div. 5 deposit cap, notices and appeals.
  - New York: the whole HEFPA set.
- **Possible but unverified** for municipals: Arkansas §23-4-206 and Ohio R.C. 4933.x.
- **Confirmed none** for municipals: Louisiana (45:850 excludes them). Georgia: none found, but the search was not exhaustive.

# Dimensions a law row's applicability key must carry

1. **Owner/operator type**, at least:
   - municipal (city or town; "owned **or operated**" — OH 4905.02(A)(3), IL 3-105(b)(1));
   - county or other political subdivision;
   - special district or authority, typed by enabling act (LA 33:4301 gas utility district; CA Div. 6 MUD, Div. 7 PUD, Gov. Code §60370 districts; NM 3-28 gas association; OK public trust);
   - investor-owned/private;
   - cooperative or customer-owned not-for-profit;
   - propane/LP piped system;
   - master-meter operator.

   A single "municipal vs IOU" flag is not enough. Kansas 12-808c reaches "any political subdivision", while Ohio's exclusion names only municipal corporations.
2. **Commission-jurisdiction status as a fact of the utility, separate from its type, with an effective date.** Elections change it without changing ownership:
   - LA R.S. 45:1164.2 (municipal referendum) and 33:4491/4495 (surrender and later reinvestment);
   - NM 62-6-5 (municipal election), 3-28-21 (association resolution);
   - KS 66-104e (a city hands its regulation of a private utility to the KCC, revocable every 2 years);
   - GA "electing distribution company".

   One law can still key on ownership after an opt-in: LA 45:850 excludes municipal plants even when they are LPSC-regulated. So rows need **both** owner type and jurisdiction status.
3. **Customer location relative to the municipal boundary.**
   - Kansas: more than 3 miles outside the corporate limits flips the KCC terms-of-service jurisdiction, subject to the 66-104f conditions, including the 40% customer share, and to a 25% customer petition.
   - New Mexico: 5-mile service cap (3-25-3).
   - Location changed nothing in OK, AR, OH, IL, LA or NY [v]; CA and GA [u].

   The key must allow per-premise, not per-utility, applicability.
4. **Size thresholds,** carried as data per law:
   - KS 66-104c: ≤100 customers, plus member-owned and no full-time staff;
   - NY §66(13): <20 customers, waiver at PSC discretion;
   - CA §4452: propane safety at ≥10 customers or any mobilehome park;
   - AR §23-4-206(c): city population <3,000, narrow and electric only.
5. **Local opt-in adoption flags,** where a law applies only if the governing body adopts it: IL 305 ILCS 20/13(k) Energy Assistance Charge. Kansas 66-104e is a city-level choice that affects private utilities.
6. **Regulator identity per rule set,** because the regulator is not always the commission:
   - city council (New Orleans);
   - the utility's own governing body as appeal forum (CA §10009 et seq.);
   - a human-services agency (NM LIUAA, administered by the health care authority);
   - pipeline safety, which binds municipals even where customer rules do not (KS, OH, OK, LA, GA).
7. **Customer class and service attributes the rules already key on:** residential vs nonresidential (NY Part 11 vs Part 13); space-heating source (IL 8-205/8-206); master-metered vs individually metered (CA §10009.1, §10009.6); service member or DV status (IL 11-117-12.2, OK §35-107).
8. **Retail role in unbundled markets** (Georgia): LDC vs electing distribution company vs marketer vs regulated provider carry different rules for the same customer.

# Could not verify

**Cross-state**
- Whether a private **piped-propane** distribution system is a commission-jurisdictional utility: OK, AR, LA, KS, OH, IL, NY. It is verified only for NM (in) and CA (out).
- Whether **gas cooperatives** exist or are governed: LA, AR.

**Oklahoma**
- Whether a municipal public trust is an "other bod[y] politic" under §151.
- Whether §35-107 binds a trust.
- 60 O.S. §654 vs §35-107 for uncashed refunds.
- oscn.net was blocked by Cloudflare; the official legislature RTFs were used instead.

**Louisiana**
- The LPSC gas deposit rule.
- The New Orleans council's role and rules.
- Whether piped propane falls under the LPSC or the LP-Gas Commission.
- Whether R-29706 has been amended.

**New Mexico**
- Whether LIUAA reaches gas associations and LP pipeline systems.
- How 27-6-18.1(B) applies to non-jurisdictional municipals.
- That 62-8-10 excludes municipals is a reading only.
- The NMAC scope comes from Cornell copies.

**Arkansas**
- All statute text is from mirrors (Justia/vLex); the official Lexis site was unreachable.
- Whether §23-4-206 (deposit interest) and §23-4-204 bind municipal systems.
- Title 14 was only partly scanned.
- APSC rules are current only to 2016.

**Kansas**
- The KCC Cold Weather Rule scope was read only in a press release and a bill note.
- Whether the 66-104(b) exclusion covers counties and townships.

**Ohio**
- Whether R.C. 4933.12/.122/.17/.28 and 5117.11(E) bind municipal or cooperative systems.
- County and township systems.
- Whether pure propane counts as a "gas company".
- Amendments to 4905.02 after 2017.

**Illinois**
- Whether PUA 8-205 (32 °F / 90 °F) binds municipals.
- Municipal deposit, interest or medical statutes beyond 11-117 and 305 ILCS 20/13.

**New York**
- No raw files were saved (browser-read only).
- The GML §360(7) vs PSL §66(5) rate interplay.
- Whether §66(13) covers municipalities.
- Gas districts other than lighting districts.
- Whether any municipal gas utility operates today.

**California**
- CPUC jurisdiction over municipal customers outside city limits.
- The full district appeal clauses (§§12823(d), 16482(d)).
- Customer rules for mobilehome-park propane.
- Municipal pipeline-safety oversight.

**Georgia**
- All statute text is from mirrors (onecle 2016, Justia 2025).
- The home-rule grant.
- Local-act gas authorities.
- Jurisdiction over municipal customers outside city limits.
- The LPG safety agency.
- A full search for municipal-gas customer statutes.
- The stale PSC citation for the LDC deposit rule.
