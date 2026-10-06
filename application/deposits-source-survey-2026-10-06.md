<!-- Source survey for the deposits inventory, 2026-10-06. Written by a research agent from primary texts where marked; spot-checked by the main session (K.S.A. 12-822, OAC 165:45-11-1). Fetched texts were kept in the session scratchpad, not the repo; each section gives its URL. -->
# Customer security-deposit rules: source inventory (gas, 10 states)

Surveyed 2026-10-06. "Verified" means I read the primary text myself: the codified rule, the statute, or a utility's filed tariff sheet. "Secondary" means a commission consumer page, a statute mirror, or a search summary. Where I could not reach the text, the section says so. I filled nothing in from memory.

Raw fetched text for each source is saved under `scratchpad/src/` (`*.txt`).

How to read the "Fit" lines: **holdable** means the schema described in the brief can hold the rule. **GAP** means it cannot, and every GAP is gathered with its quote in the final section.

---

## Oklahoma — verified

- **Citation:** OAC 165:45-11-1, "Deposits and interest". https://www.law.cornell.edu/regulations/oklahoma/OAC-165-45-11-1
- **Scope:** OAC 165:45-1-4 says the chapter covers "any gas utility ... subject to the jurisdiction of the Commission". OAC 165:45-1-2 defines "Natural gas utility" as "a natural gas utility as defined in 17 O.S. § 151 et seq." I did not fetch 17 O.S. §151, so the exclusion of municipal utilities is **secondary only**. Note that the "Consumer" definition includes a "municipality" as a *customer*.
- **Structure:** each utility files a deposit *plan* for Commission approval. The residential plan must conform to every subsection. The nonresidential plan is exempt from (b), (c), (d) and (k).
- **Cap:** "(c) No utility shall require a deposit of more than one-sixth (1/6) the estimated annual bill." This is residential only, because (c) is excluded for nonresidential. Fit: holdable.
- **Exemption:** "(b) No utility shall require a deposit of a residential consumer who has received the same or similar type and classification of service for twelve (12) consecutive months and service was not terminated for nonpayment nor was payment late more than twice nor was a check for payment dishonored. The twelve (12) month service period shall have been within eighteen (18) months prior to the application." Fit: holdable as a good-payment-history waiver, provided the 12-in-18 test is evaluated outside the schema.
- **Additional-deposit triggers:**
  - Residential: "(d) ... delinquent ... in two (2) out of the last twelve (12) billing periods or if the consumer has had service disconnected during the last twelve (12) months ... or has presented a check subsequently dishonored."
  - Nonresidential: "(e) ... two (2) out of the last twenty-four (24) billing periods ... disconnected during the last twenty-four (24) months".
  - Fit: the NSF and disconnection legs are holdable. The *late-payment* event type is a GAP (G1). The window is counted in billing periods rather than months.
- **Interest rate (f):**
  - "(1) For all consumer deposits returned within one (1) year or less, the interest rate shall be ... the average of the weekly percent annual yields of one (1) year U.S. Treasury Securities for September, October, and November of the preceding year."
  - "(2) For all consumer deposits held by the utility for more than one (1) year, the interest rate shall be ... 10-year U.S. Treasury Securities ... The utility may pay the average of the one (1) year Treasury Security ... for the first year the deposit is held."
  - "(3) ... the interest rate(s) shall not change unless the application of the formula ... results in a change ... greater than fifty (50) basis points."
  - The rate is a floor: "at no less than the rate calculated".
  - Fit: GAP (G2).
- **Interest hold and retroactivity:** "(g) If refund of deposit is made within thirty (30) days of receipt of deposit, no interest payment is required. If the utility retains the deposit more than thirty (30) days, payment of interest shall be made retroactive to the date of deposit. No interest shall accrue on a deposit after final discontinuance of service." Fit: holdable (30 hold days, retroactive). The stop-on-discontinuance event is GAP G14.
- **Interest crediting:** "(p) ... payment of accrued interest for all consumers annually by negotiable instrument or by credit against current billing." Fit: holdable.
- **Return:**
  - Residential: "(l) ... automatically refund the deposit for residential service, with accrued interest, after twelve (12) months satisfactory payment of undisputed charges and where payment was not late more than twice; provided, however, that service has not been disconnected within the twelve (12) month period." Fit: holdable.
  - Nonresidential: "(m) The utility shall automatically refund non-residential service deposits of less than $20,000, with accrued interest, after twenty-four (24) months' satisfactory payment ... Non-residential consumers ... must have a minimum of five (5) years continuous service at the service location with the utility before a deposit will be refunded." Fit: GAP (G3).
  - Review: "(n) ... review of all residential deposits at least annually and deposits for non-residential service at least every twenty-four (24) months".
  - On close: "(o) ... applied to any unpaid charges at the time of a discontinuance of service. The balance ... returned ... within thirty (30) days". Fit: holdable.
  - Dispute hold: "(q) The utility may withhold refund ... pending the resolution of a dispute". Fit: GAP (G13).
- **Instalments:** "(c) ... The utility plan may allow consumers to pay deposits in installments. The utility may also require consumers to pay the entire deposit prior to initiating service." This is optional and has no schedule. Fit: holdable as "none / utility tariff".
- **Other rules:**
  - "(j) If the deposit is not paid by the due date, the amount of the deposit will become a part of the past due amount owed and monies paid shall be applied to the oldest past due amount."
  - "(t)" sale or transfer of the utility requires a verified depositor list.
  - "(u)" says the deposit is not an advance payment.

## Louisiana — statute verified; Commission rule NOT located

- **Citation:** La. R.S. 45:848. https://www.legis.la.gov/legis/Law.aspx?d=100158 (verified)
- **Text:** "Whenever any person engaged in furnishing gas, electricity or water shall demand of its patrons a cash security ... the furnisher shall pay to that patron, interest at the rate of five per cent per annum upon the amount of the deposit so long as it continues to hold or exact the deposit. The balance of the deposit together with earned interest shall be returned to the depositor, on demand whenever the service is discontinued, and any refusal or neglect to return the balance shall subject the furnisher of gas, water or electricity to the penalty of paying the consumer ten per cent per annum interest upon the deposit so retained after demand."
- **Correction, 2026-10-06 (places inventory):** La. R.S. 45:850 excludes plants "owned by any municipality or political subdivision" from §§845–849, so §848's 5% interest does **not** bind municipal systems. See `application/places-sources/utility-type-10-states.md`.
- **Scope (as first written):** the text says "any person engaged in furnishing gas". It contains no municipal exemption. R.S. 45:849 lets municipalities appoint inspectors to carry out §§845–848. Whether §848 binds municipal gas systems is **not determined**; it needs an AG opinion or case law. This matters for Louisiana municipal systems.
- **Interest:**
  - The rate is fixed by statute at 5%, and there is no hold period. Fit: holdable only if the state's rate can be *binding*. The brief describes the state rate as a reference only (G4).
  - The 10% penalty rate that applies after a refused demand is a GAP (G5).
- **Return:** "on demand whenever the service is discontinued". This is a return on close, conditioned on the customer's demand. Fit: partly a GAP (G5).
- **Missing:** I could not find the LPSC rules on deposit caps, triggers, refunds or waivers (a General Order). Searches returned only tariffs and news. Cap, triggers, waivers and instalments are **unverified for Louisiana**.

## New Mexico — verified

- **Citations:**
  - Residential: 17.5.410.16–.20 NMAC. https://www.law.cornell.edu/regulations/new-mexico/N-M-Admin-Code-SS-17.5.410.18 (sibling URLs .16, .17, .19, .20)
  - Nonresidential gas: 17.10.650.11(B) NMAC. https://www.law.cornell.edu/regulations/new-mexico/N-M-Admin-Code-SS-17.10.650.11
  - Interest statute: NMSA 1978 §62-13-13, as amended by 2005 SB 178. https://www.nmlegis.gov/Sessions/05%20Regular/final/SB0178.html (enrolled bill text, verified)
- **Scope:**
  - 17.5.410.2: "applies to electric, rural electric cooperative and gas utilities subject to the jurisdiction of the New Mexico public regulation commission."
  - 17.10.650.2: "any gas utility operating within the state ... under the jurisdiction of the ... commission."
  - §62-13-13 reaches "any public utility as defined in Section 62-3-3", telephone companies, and waterworks under Ch. 62 Art. 2. I did not fetch the §62-3-3 definition, so the municipal exclusion is **secondary only**.
- **When a deposit is allowed (17.5.410.16(A)):** only (1) a new customer without acceptable credit; (2) a customer who "has on three or more occasions, within a 12-month period, received a final notice"; (3) reconnection after discontinuance; (4) tampering or diversion. Fit: the final-notice event type is a GAP (G1); the count-in-window shape is holdable.
- **Low-income consideration:** "(B) ... meets the qualifications of LIHEAP ... the utility shall give special consideration ... in determining whether or in what amount a security deposit will be charged or if payment by an installment agreement is appropriate." This is discretionary. Fit: holdable as a LIHEAP waiver class whose effect is set by the utility.
- **Cap:** "(A) ... shall not exceed an amount equivalent to one sixth (1/6) of that residential customer's estimated annual billings ... based upon the most recent available prior 12-month corresponding period at the same service location". The nonresidential cap is the same. Fit: holdable.
- **Interest:**
  - 17.5.410.18(B): "Simple interest on deposits at a rate not less than the rate required by law shall accrue annually ... The deposit shall cease to draw interest on the date it is returned, on the date service is terminated, or on the date the refund is sent".
  - §62-13-13: "Interest on deposits shall be set annually at a rate equal to the federal five-year treasury note rate as reported on the first day of the calendar year by the federal reserve board of governors".
  - 17.10.650.11(B)(4)(b): "by January 15 of each year the commission shall post on its website the minimum rate".
  - Fit: holdable (state reference rate, simple, annual). The stop events are G14.
- **Return:**
  - 17.5.410.19(A): "Any residential customer who has not been chronically delinquent for the twelve-month period from the date of deposit ... shall promptly receive a credit or refund ... If the amount of the deposit exceeds the amount of the current bill, the residential customer may request a refund in the amount of the excess if such excess exceeds twenty five dollars ($25)." After that, the account is reviewed at least annually.
  - "Chronically delinquent" (17.5.410.7): "disconnected by that utility for nonpayment or who on three (3) or more occasions during the prior twelve months has not paid a bill by the date a subsequent bill is rendered".
  - Nonresidential uses "has not received a final notice" for 12 months.
  - Fit: the 12-month return with a delinquency limit is holdable. The excess-over-current-bill partial refund with a $25 minimum is a GAP (G6).
- **Instalments:** only "if payment by an installment agreement is appropriate", with no schedule. Fit: holdable as none / tariff.

## Arkansas — verified (2016 General Service Rules)

- **Citation:** APSC General Service Rules, Section 4, codified as Ark. Code R. 126.04.16-001. https://www.law.cornell.edu/regulations/arkansas/126-04-16-Ark-Code-R-001 I also read the 2002 Arkansas Register version (126.03.02-004), and its Section 4 is substantively identical. I could not reach the APSC website, so the current text is verified only as of the 2016 codification.
- **Interest statute:** Ark. Code Ann. §23-4-206(b) is cited by the rules ("Interest rate set annually by the Commission"). I did **not** retrieve the statute text.
- **Scope:** "Rule 1.01 ... These Rules shall apply to all whose activities bring them under the jurisdiction of the Commission except for telecommunications providers." That municipal systems fall outside APSC jurisdiction is **secondary only**.
- **Applicant triggers (4.01.A(2)):**
  - "c. the applicant did not pay bills ... by the close of business on the due date 2 times in a row or any 3 times in the last 12 months."
  - "d. ... 2 or more checks ... within the most recent 12 month period ... returned unpaid".
  - "e. ... service ... suspended during the last 24 months for ... nonpayment ... misrepresentation ... failure to reimburse ... damages ... diverting".
  - "f." material misrepresentation within 2 years.
- **Customer triggers (4.02.A):**
  - (1) "failed to pay a bill before the close of business on the shut-off date within the last 12 months".
  - (2) 2 or more NSF in 12 months.
  - (3) "2 times in a row or any 3 times in the last 12 months".
  - (4) misrepresentation in 24 months.
  - (5) tampering in 2 years.
  - (6) "The customer used more service than the estimate on which the utility based the deposit. The utility may not charge any additional deposit under Subsection A. (6) after the first 12 months of service unless the customer moves the service to a new location or expands the business".
  - (7) 11 U.S.C. §366.
  - Fit: the consecutive-OR-count shape (G7), the late-payment event (G1), and the usage trigger's time limit (G8) are GAPs.
- **Cap (applicant, 4.01.B):**
  - "(1) ... not more than 2 average bills ... if payment for utility service is due after service begins; EXCEPTION: ... from a landlord a deposit which shall not exceed the estimated bill for 3 average billing periods."
  - "(2) ... not more than 1 average bill ... if payment for utility service is due before service begins".
  - "(3) [tampering] ... not more than 6 average bills, plus the potential damage to utility equipment. The utility may not charge this deposit if the customer has received more than 2 years cumulative service since the utility discovered the unauthorized use or tampering".
  - "(4) [misrepresentation] ... not more than twice the maximum bill".
  - "(6) If the applicant has previously left the utility's service owing a bill ... a deposit equal to twice the maximum billing."
- **Cap (customer, 4.02.B):** "the total amount on deposit at any time shall not be more than the total of the customer's 2 highest bills during the last 12 months." This is a combined scope. Tampering: "6 average billing periods plus the cost of potential damage".
- **Average bill (4.03):**
  - "Seasonal Customers ... the total of the monthly bills during the 'season' as defined in the utility's tariff ... divided by the number of months of usage during the season."
  - "Non-Seasonal ... the total of the last 12 months' bills divided by 12."
  - "Inadequate history ... not more than the average monthly usage for that class".
- **Cap fit:** 2 average bills is holdable (months of billing). The highest/maximum bill bases, the seasonal average, the "+ potential damage" add-on and the tampering sunset are GAPs (G9, G10, G8).
- **Instalments:**
  - 4.01.C: "applicants shall be allowed to pay the deposit in 2 installments - 1/2 of the deposit before receiving service and the remaining 1/2 with the first bill." This excludes tampering deposits.
  - 4.02.D: "a customer may pay 1/2 of any new or additional deposit in equal installments with the next 2 bills."
  - Fit: these schedules are anchored to bills, not days. GAP (G11).
- **Guaranty (4.04):** a qualified residential guarantor must have no deposit on file, at least 12 months of service, no more than 2 late payments in 12 months, and no suspension in 12 months. "Liability ... limited to the amount required for a deposit when the guaranty was made". Fit: guarantor liability caps are G15.
- **Interest (4.05):** "A. A utility shall pay interest annually on deposits pursuant to Ark. Code Ann. § 23-4-206. B. Interest shall not accrue on any deposit after the date the utility has made and documented a good faith effort to return the deposit". Fit: holdable apart from the stop event (G14).
- **Return (4.06):**
  - "A. If a residential customer has paid all bills by the due date for the last 12 months, a utility must promptly refund the deposit. Utilities are not required to refund deposits on business or commercial accounts until the account is closed."
  - Exceptions: tampering deposits are kept until close; bankruptcy deposits follow the Code.
  - "B." on close, the deposit is applied and the balance refunded.
  - Fit: holdable, since return is keyed by class and deposit basis.
- **Other:**
  - "4.08 ... shall not charge an additional deposit if a customer requests that his service end at one location and ... begin at another location and the change takes 90 days or less." Fit: GAP (G12).
  - 4.07: no deposit merely for a name change.

## Kansas — verified (KCC Billing Standards and K.S.A. 12-822)

- **Citations:**
  - KCC "Electric, Natural Gas and Water Billing Standards", effective Jan 20, 2012, Section III. https://www.kcc.ks.gov/images/PDFs/pi/billing_2012.pdf (verified; the PDF text layer is partly garbled, but the quoted passages are clean)
  - K.S.A. 12-822. https://ksrevisor.gov/statutes/chapters/ch12/012_008_0022.html (verified)
- **Scope:**
  - The Billing Standards apply to KCC-regulated utilities.
  - **K.S.A. 12-822 expressly binds municipal utilities:** "It shall be unlawful for any public or municipally owned utility doing business in the state of Kansas to receive or collect a deposit ... unless such public or municipally owned utility shall keep a separate account ... and shall pay to the customer making the deposit interest at the rate determined by the state corporation commission."
  - This is the most direct municipal hit in the survey.
- **Statutory interest crediting (12-822):** "Such interest shall be credited once a year or credited on January 1 succeeding such deposit and on each January 1 thereafter, to such customer's outstanding account, unless, prior to January 1, such customer shall request the payment of such interest in cash ... Any interest credited shall be subject to call and payment at any time, but shall not draw interest." Fit: simple interest at the KCC rate is holdable. The calendar-date anchor and the customer's choice of cash are GAPs (G16).
- **Statutory cap (12-822):** "The amount of deposit required shall at all times be reasonable, and shall be based upon the value of the maximum service rendered". This is qualitative.
- **Municipal investment and escheat (12-822):**
  - "Any municipally owned utility ... may invest money received as customers' deposits ... in investments authorized by K.S.A. 12-1675 ... or in bonds of the state of Kansas ... or in savings accounts of commercial banks."
  - Unclaimed municipal deposits go to the operating fund after "(a) ... more than three years from the date service was discontinued; (b) no demand ...; (c) whereabouts ... unknown ...; (d) ... published, once each week for two consecutive weeks ... a demand ... must be made within 60 days."
  - Fit: GAP (G17).
- **Billing Standards III.A(1), initial deposit:**
  - Unsatisfactory credit.
  - An unpaid account accrued "within the last five (5) years if the service agreement was signed, or three (3) years if service was provided after an oral agreement".
  - Diversion within 5 years.
- **Billing Standards III.B, new or modified deposit "upon five (5) days written notice":**
  - "(1) ... fails to pay an undisputed bill before the bill due date for three (3) consecutive billing periods, one of which is at least 30 days in arrears".
  - "(3) ... disconnected for non-payment two or more times within the most recent twelve month period".
  - "(4) ... defaulted on a payment agreement(s) two or more times within the most recent twelve month period".
  - "(5) ... tendered two or more insufficient funds payments within the most recent twelve month period".
  - "(6) ... bankruptcy ... Within 60 days after the bankruptcy has been discharged, if the deposit on file is less than the maximum ... the utility may recalculate".
  - Fit: (3), (4) and (5) are holdable. (1) is a GAP (G7). (6) is a GAP (G18).
- **Cap (III.D):**
  - "shall not exceed the amount of that customer's projected average two (2) months' bill(s) for residential and small nonresidential customers. For other customers, such deposit shall not exceed the amount of that customer's projected largest two (2) months' bill(s)."
  - Cooperatives with turn-around billing: 3 average, or 3 largest.
  - "If a customer has been documented to be diverting service ... an additional deposit based on one (1) months' average use may be assessed."
  - "a small nonresidential customer is one which uses no more than ... 50 Mcf of natural gas in an average month."
  - Fit: 2 average months is holdable. "Largest two months" is G9. The diversion add-on above the cap is G10. Defining a class by usage is holdable if the class is assigned outside the schema.
- **Instalments (III.D):** "payment of any required residential or small nonresidential deposit in equal installments over a period of at least four (4) months when deposits are based on two (2) average months' usage and a period of at least six (6) months when deposits are based on three (3) average months' usage. An additional two (2) months shall be given to customers who have been assessed an additional deposit due to documented diversion". Fit: GAP (G11).
- **Return (III.G):**
  - Residential: "credited with interest ... or, if requested, refunded, after 12 months if the customer has paid ten (10) out of the last twelve (12) bills on time and no undisputed bill was unpaid after 30 days beyond due date."
  - Small nonresidential: "after 24 months ... twenty (20) of the last twenty-four (24) bills".
  - "The month(s) of a disputed bill(s) shall be ignored in this calculation."
  - "Large nonresidential customer security deposits will be retained by the utility until termination of service. Large nonresidential customers will have their deposit requirements recalculated every three years ... The maximum deposit requirement shall be increased or decreased as appropriate".
  - Fit: the 10-of-12 rule is holdable. Ignoring disputed bills is G13. The periodic two-way recalculation is G19.
- **Interest (III.G–H):** "accrued simple interest at a rate not less than that provided by K.S.A. 12-822 ... H. Interest payments ... shall be credited to the customer's bill or refunded at least once a year." Fit: holdable.
- **Guarantor (III.J(1)):** the utility "shall accept the written guarantee" of a residential customer with 10 of 12 on time. "The utility shall not hold the guarantor liable for sums in excess of the maximum amount of the required cash deposit". Fit: G15.

## Ohio — verified

- **Citations:** Ohio Adm. Code 4901:1-17-01 through -06. https://www.law.cornell.edu/regulations/ohio/Ohio-Admin-Code-4901-1-17-05 (siblings -01 to -06)
- **Scope:**
  - "4901:1-17-02(A) The rules in this chapter apply to all electric, gas, natural gas, waterworks, and sewage disposal utility companies who provide service to residential customers."
  - "Utility company" (-01(J)) is defined by R.C. 4905.03 and 4929.01. That municipally owned utilities fall outside PUCO jurisdiction is **secondary only** (R.C. 4905.02 not fetched).
  - The chapter is residential only.
- **Establishing credit (-03(A)):**
  - Owner of the premises.
  - Credit check.
  - "had the same class and a similar type of utility service within a period of twenty-four consecutive months preceding the date of application, unless ... disconnected for nonpayment during the last twelve consecutive months of service, or ... received two consecutive bills with past due balances during that twelve-month period".
  - A cash deposit.
  - A guarantor "in an amount sufficient for a sixty-day supply".
  - "Utility companies are prohibited from requiring percentage of income payment plan customers to pay a security deposit."
  - Fit: the PIPP waiver is holdable as a class waiver with excuse effect. The guarantor's 60-day amount is G15.
- **Triggers (-04):**
  - "(B) ... a utility company may require a deposit if the customer has not made full payment or payment arrangements for any given bill two consecutive bills containing a previous past due balance". The Cornell rendering shows strike-through and insert markup mixed together.
  - "(C) ... if the applicant ... during the preceding twelve months ... had service disconnected for nonpayment, a fraudulent act, tampering, or unauthorized reconnection."
  - Fit: the consecutive-bills shape is a GAP (G7).
- **Cap (-05(A)):** "in an amount in excess of one-twelfth of the estimated charge for regulated service(s) ... for the ensuing twelve months, plus thirty per cent of the monthly estimated charge." This equals 1.3 months of estimated billing. Fit: holdable if entered as a single part of 1.3 months. Note that the rule is written as a **sum** of parts, and the schema offers only lesser-of and greater-of.
- **Interest (-05(B)–(C)):** "accrue interest at a rate of at least three per cent per annum per deposit held for one hundred eighty days or longer. Interest shall be paid to the customer when the deposit is refunded or deducted from the customer's final bill. ... not ... required to pay interest on a deposit it holds for less than one hundred eighty days." Fit: holdable (a 3% floor as the state reference, 180 hold days, credited at refund). Whether interest is retroactive to posting is implied but not stated.
- **Return (-06):**
  - "(A) ... promptly refund ... unless the amount of the refund is less than one dollar. A transfer of service ... within the service area ... does not prompt a refund".
  - "(B) ... review each account ... every twelve months and promptly refund ... if (1) ... paid ... bills ... for twelve consecutive months without having had service disconnected for nonpayment. (2) ... not had more than two occasions in the preceding twelve months on which his/her bill was not paid by the due date. (3) ... not then delinquent".
  - "(C) ... upon the customer's request at any time the customer's credit has been otherwise established".
  - Fit: holdable, except the $1 minimum refund (G6).

## Illinois — verified

- **Citations:**
  - 83 Ill. Adm. Code 280.40 ("Deposits") and 280.45 ("Deposits for Low Income Customers"). https://www.ilga.gov/commission/jcar/admincode/083/083002800C00400R.html and https://www.ilga.gov/commission/jcar/admincode/083/083002800C00450R.html
  - The Cornell copy drops the fraction glyphs (⅙ ⅓ ⅕ ⅘) as "?". Use the JCAR text.
- **Scope:** Part 280 covers gas, electric, water and sewer "utilities". 220 ILCS 5/3-105(b)(1): "'Public utility' does not include ... public utilities that are owned and operated by any political subdivision ... or municipal corporation of this State". **Municipal utilities are exempt** (verified, https://www.ilga.gov/legislation/ilcs/fulltext.asp?DocName=022000050K3-105).
- **Notice deadline (b)(1):** "A utility shall make an initial notice of a deposit ... no later than 45 days after the applicant's application for service is approved or after the event that justifies the deposit. A deposit shall not be assessed until the initial notice is given." Fit: GAP (G20).
- **Cap (c):** "(1) Residential and small business customer deposits shall not exceed ⅙ of the estimated annual charges ... (2) Non-residential, other than small business, ... shall not exceed ⅓". "Small Business" means 50 or fewer full-time Illinois employees. Fit: holdable.
- **Applicant triggers (d):**
  - Prior disconnection for nonpayment.
  - Unpaid final bill.
  - A "credit score fails to meet the minimum standard of the credit scoring system described in the utility's tariff".
  - Nonresidential credit references.
  - Tampering.
  - Payment avoidance by location.
- **Present-customer triggers (e):**
  - "(1) ... if both of the following conditions occur: A) The customer has paid late four times in the past 12 months; and B) The customer's account has an undisputed past due balance that has remained unpaid for over 30 days beyond the due date."
  - "(2) A present residential customer may avoid the requirement to pay a deposit under subsection (e)(1) by entering into and keeping current with a DPA for the unpaid balance, so long as the customer enters the DPA prior to the assessment of the deposit."
  - Fit: the AND-composite (G7), the late-payment event (G1) and the DPA cure (G21) are GAPs.
- **Instalments:**
  - (f): "A utility may require payment of ⅓ of an applicable deposit by including that amount on the first bill statement sent to the customer after the issuance of the deposit. The remaining ⅔ of the deposit shall be paid in equal installment amounts included on the next two bill statements."
  - Low income, 280.45(b)(4): "payment of ⅕ of an applicable deposit within a minimum of 12 days after the issue date of a deposit notice ... with the remaining ⅘ to be paid in equal installments over the next four billing cycles."
  - Fit: GAP (G11).
- **Interest (g):** "(1) Interest shall be paid ... on all deposit amounts, including installments ... The rate of interest will be the same as the rate existing for the average one year yield on U.S. Treasury Securities for the last full week in November. The interest rate will be rounded to the nearest 0.5 %. In December each year, the Commission shall announce the rate ... (2) After 12 consecutive months of accumulated interest, when a customer is not entitled to a refund of the deposit, the utility shall automatically credit the customer's account with the interest only." Fit: holdable (state reference, credited annually on the bill). Interest accrues on instalments as they are paid.
- **Return (h):**
  - "(1) ... automatically refund ... once the customer completes 12 consecutive months of service with fewer than four late payments, no disconnections for nonpayment and no tampering ... if the customer has no past due balance owing at the time of the deposit refund."
  - "(2) ... when the customer voluntarily ends service and is not transferring service".
  - "(3) ... 30 days after disconnection of service for non-payment when the former customer has not paid the full balance owing or otherwise made arrangements".
  - Fit: (1) and (2) are holdable. (3) is a GAP (G22).
- **Refund method (i)(2):** "The utility shall not be obliged to issue the refund by separate payment instead of a credit if the amount to be refunded does not exceed 125% of the customer's average monthly bill amount." Fit: GAP (G6).
- **Low income (280.45):**
  - Deposits are allowed only for tampering or a prior disconnection for nonpayment.
  - No deposits based on credit scoring; credit-score deposits are "returned ... upon certification as a low income customer".
  - No (e)(1) deposits.
  - "(b)(3) ... may assess a deposit for a low income applicant if the applicant failed to pay a final bill ... and that final bill was greater than 20% of the average annual billing for the residential customers of the utility for the calendar year preceding".
  - Fit: the waivers by class are holdable. Returning a deposit when the customer enters a class (G23) and the class-average threshold (G24) are GAPs.

## New York — verified

- **Citations:**
  - Residential (HEFPA): 16 NYCRR 11.12. https://www.law.cornell.edu/regulations/new-york/16-NYCRR-11.12
  - Scope: 16 NYCRR 11.2.
  - Nonresidential: 16 NYCRR 13.7. https://www.law.cornell.edu/regulations/new-york/16-NYCRR-13.7
- **Scope (11.2):** Part 11 applies to every "gas corporation ... and **municipality** subject to the jurisdiction of the commission ... provided, however, that the term does not include any municipality that is exempt from commission regulation by virtue of section 1005(5)(g) of the Public Authorities Law." **Commission-jurisdictional municipal systems are covered.**
- **Residential (11.12):**
  - Default prohibition:
    - "(b) ... no utility shall require any new residential customer to post a security deposit ... unless such new customer is a seasonal or short-term customer."
    - "(c)(2) ... no utility shall ... require a current residential customer, other than a delinquent customer, to post a security deposit".
  - Delinquency definition, (d)(2): a current customer is delinquent if the customer "(i) accumulates two consecutive months of arrears without making reasonable payment, defined as one half of the total arrears ... before the time that a late payment charge ... would become applicable, or fails to make a reasonable payment on a bimonthly bill within 50 days after the bill is due, provided that the utility requests such deposit within two months of such failure to pay; or (ii) had utility service terminated, disconnected or suspended for nonpayment during the preceding six months." It also requires "written notice, at least 20 days before it may assess a deposit". Fit: (ii) is holdable. (i) is a GAP (G7, G20, G25).
  - Instalments, (d)(3): "permit such customer to pay the deposit in installments over a period not to exceed 12 months." Fit: GAP (G11).
  - Waivers:
    - "(f) No utility shall require any person it knows to be a recipient of public assistance, supplemental security income, or additional State payments, to post a security deposit."
    - "(g) No utility shall demand or hold a deposit from any new or current residential customer it knows is 62 years of age or older unless such customer has had service terminated ... for nonpayment of bills within the preceding six months."
    - Fit: (f) is holdable. (g) is a waiver with its own disqualifier, a GAP (G26). Age 62 also differs from the schema's 65+ class; holdable only if the age is data.
  - Cap, (h): "not greater than twice the average monthly bill for a calendar year, except in the case of electric or gas space heating customers, where deposits may not exceed twice the estimated average monthly bill for the heating season". Fit: the calendar-year part is holdable. The heating-season part is a GAP (G9).
  - Interest, (h): "at a rate prescribed annually by the commission ... Such interest shall be paid to the customer upon the return of the deposit, or where the deposit has been held for a period of one year, the interest shall be credited to the customer on the first billing ... after the end of such period." Fit: holdable.
  - Return, (h): "If any customer is not delinquent ... during the one-year period from the payment of the deposit, the deposit shall be refunded promptly". Fit: holdable, given the delinquency definition caveat (G25).
- **Nonresidential (13.7):**
  - Triggers: new customer; existing customer who is delinquent, has a risky financial condition, is in bankruptcy, or has been "rendered a backbill within the last 12 months for previously unbilled charges for service that came through tampered equipment".
  - Instalments: "(a)(2) ... three installments, 50 percent down and two monthly payments of the balance." Fit: holdable as 50% / 25% at 30 days / 25% at 60 days, if "monthly" means about 30 days.
  - Cap: "(b)(1) ... shall not exceed the cost of twice the customer's average monthly usage, except ... space-heating or -cooling customers, or certain manufacturing and industrial processors, where the deposit shall not exceed the cost of twice the average monthly usage for the peak season." Fit: GAP (G9).
  - Review: "(c)(1) ... at the first anniversary ... and at least biennially thereafter ... (i) If a deposit review shows that the deposit held falls short of the amount that the utility may lawfully require by 25 percent or more, the utility may require the payment of a corresponding additional deposit ... (ii) ... exceeds ... by 25 percent or more, the utility shall refund the excess". Fit: GAP (G19).
  - Alternatives: "(d)(1) ... shall accept ... irrevocable bank letters of credit and surety bonds. (2) ... may ... accept ... a written promise to pay bills on receipt and a written waiver of the customer's right to be sent a final termination notice". Fit: holdable as instruments; the promise-to-pay instrument is new.
  - Interest: "(e)(2) ... where the deposit has been held for a period of one year or more, the interest shall be credited to the customer no later than the first bill rendered after the next succeeding first day of October and at the expiration of each succeeding one-year period. (3) Interest shall be calculated on the deposit until the day it is applied ... If the deposit is credited in part and refunded in part, interest shall be calculated for each portion". Fit: the October 1 anchor is a GAP (G16).
  - Return: "(f)(1)(ii) the issuance date of the first cycle bill rendered after a three-year period during which all bills were timely paid". Fit: holdable (36 months, zero late payments).

## California — tariff verified (PG&E); no statewide rule text located

- **Citation:** PG&E Gas Rule No. 7, "Deposits", Cal. P.U.C. Sheets 36007-G and 36008-G, effective 2020-07-16, Advice 4274-G, implementing **CPUC D.20-06-003**. https://www.pge.com/tariffs/assets/pdf/tariffbook/GAS_RULES_7.pdf (verified)
- **Also unverified:** SoCalGas Rule 7 could not be fetched (JavaScript tariff viewer). I did not read D.20-06-003 itself.
- **Scope:** CPUC tariffs bind IOUs. California municipal gas systems are not CPUC-rate-regulated (**secondary**).
- **Residential:** "Pursuant to CPUC Decision 20-06-003, PG&E is prohibited from requiring any residential customers to pay establishment of credit deposits for new service". The residential reestablishment language was deleted (marked "(D)"). Fit: holdable as no deposit allowed (cap of $0).
- **Nonresidential cap:** "may be twice the maximum monthly bill as estimated by PG&E. ... Small Business Customer account may be twice the average monthly bill". Reestablishment is "twice the maximum bill". Fit: average is holdable; maximum is a GAP (G9).
- **Return:**
  - "B.4 PG&E will review the Customer's account at the end of the first 12 months that the deposit is held and each month thereafter. After the Customer has had not more than two past due bills ... during the 12 months prior to any such review, or has not had service temporarily or permanently discontinued for nonpayment ... the deposit will be refunded".
  - "B.5 Deposits cannot be used to offset past due bills to avoid or delay discontinuance".
  - Fit: holdable.
- **Interest:**
  - "C.1 PG&E will pay interest on deposits ... calculated on a daily basis, and compounded at the end of each calendar month, from the date fully paid to the date of refund ... The interest rate applicable in each calendar month may vary and shall be equal to the interest rate on commercial paper (prime, 3 months) for the previous month as reported in the Federal Reserve Statistical Release, H.15 ... except that when a refund is made within the first fifteen (15) days of a calendar month the interest rate applicable in the previous month shall be applied".
  - "C.2 No interest will be paid if service is temporarily or permanently discontinued for nonpayment of bills."
  - Fit: GAP (G27, G28).

## Georgia — statute (mirror) and rule partly verified; LDC deposit rule secondary only

- **Context:** most Georgia gas customers buy from certificated *marketers*, with Atlanta Gas Light as the delivery-only Electing Distribution Company. Atmos is the regulated LDC elsewhere. Municipal gas systems are not PSC-regulated (**secondary**).
- **Marketer statute:** O.C.G.A. §46-4-156(h). Text read via the law.onecle.com mirror (https://law.onecle.com/georgia/title-46/46-4-156.html), so **secondary**; the mirror may be dated.
  - "A marketer may require a deposit, not to exceed $150.00, from a consumer prior to providing gas distribution service to such consumer. A marketer is not authorized to require an increase in the deposit of a consumer if such consumer has paid all bills from the marketer in a timely manner for a period of three months. ... In any case where a marketer has required a deposit from a consumer and such consumer has paid all bills from the marketer in a timely manner for a period of six months, the marketer shall be required to refund the deposit to the consumer within 60 days. In any event, a deposit shall be refunded to a consumer within 60 days of the date that such consumer changes marketers or discontinues service".
  - Fit: the $150 cap, the 6-month return and the return on close are holdable. "No increase after 3 timely months" is holdable as a good-payment-history waiver that excuses the trigger. The refund deadline in days is G29.
- **Marketer rule (verified):** Ga. Comp. R. & Regs. 515-7-9-.04(l)–(m), the disclosure statement, must state "that deposits shall not exceed $150.00 for any consumer who primarily uses gas for personal family or household purposes" and "that deposits shall not exceed twenty (20) percent of the consumer's annual estimated bill for any non-residential firm retail customer". https://www.law.cornell.edu/regulations/georgia/Ga-Comp-R-Regs-R-515-7-9-.04 Fit: holdable.
- **LDC (Atmos), secondary only:** the PSC consumer page (https://psc.ga.gov/about-the-psc/consumer-corner/natural-gas/consumer-rights/customer-deposits/) says "Commission Rule 515-3-1-.10(2)(3) limits cash deposits ... to no more than two-and-one-half twelfths of the estimated charge for the service for the next twelve months ... For seasonal service ... one-half of the estimated charge for the service for the season involved." The current codified 515-3-1-.10 on Cornell is "Accounting Requirements" and contains no deposit text, so the citation on the PSC page looks stale. **Not verified.**
- **Not located:** interest, triggers and waivers for Georgia LDC or marketer deposits. A search summary claimed a senior-citizen waiver ($100 reduced deposit) and interest after 6 months, but I could not trace either to primary text.

## Federal — 11 U.S.C. §366

The Arkansas GSR cites §366 adequate assurance directly in 4.01.B(5) and 4.02.A(7). "This deposit may be in addition to all other deposits posted with the utility before the bankruptcy filing", so its cap scope sits outside the combined cap. Kansas III.B(6) adds a recalculation "Within 60 days after the bankruptcy has been discharged".

---

# Shapes the schema cannot hold

Each entry gives the quote, the citation, and whether the text was verified from primary text or seen only in a secondary source. Where several states share a shape, they are listed together.

**G1. Trigger event types that are missing.** The schema's trigger events are NSF, disconnection, broken arrangement and usage. Several rules count other events. *Verified.*
- **Late payment:**
  - OAC 165:45-11-1(d): "a payment not received on or before the due date ... in two (2) out of the last twelve (12) billing periods".
  - 83 IAC 280.40(e)(1)(A): "paid late four times in the past 12 months".
  - Ark. GSR 4.02.A(3).
- **Final notice:** 17.5.410.16(A)(2): "on three or more occasions, within a 12-month period, received a final notice".
- **Shut-off date missed:** Ark. GSR 4.02.A(1): "failed to pay a bill before the close of business on the shut-off date".
- **Tampering, misrepresentation, bankruptcy:** Ark. GSR 4.02.A(4), (5), (7); 16 NYCRR 13.7(a)(1)(ii)(c)–(d); Kansas III.B(6).
- **Change in character of nonresidential service:** Kansas III.B(2).

**G2. Interest reference rate depends on holding period, with a change band.** *Verified.*
- OAC 165:45-11-1(f)(1)–(3): "deposits returned within one (1) year or less ... one (1) year U.S. Treasury Securities ... deposits held ... more than one (1) year ... 10-year U.S. Treasury Securities ... The utility may pay the average of the one (1) year Treasury Security ... for the first year".
- The same rule adds: "the interest rate(s) shall not change unless ... a change ... greater than fifty (50) basis points."

**G3. Return conditioned on deposit size and on minimum tenure at the location.** *Verified.*
- OAC 165:45-11-1(m): "automatically refund non-residential service deposits of less than $20,000 ... must have a minimum of five (5) years continuous service at the service location with the utility before a deposit will be refunded."

**G4. A statutory fixed rate that binds, rather than a reference.** *Verified.*
- La. R.S. 45:848: "the furnisher shall pay ... interest at the rate of five per cent per annum".
- The schema keeps the utility's rate, with the state rate only as a reference.

**G5. Penalty interest after a refused return demand, and return conditioned on demand.** *Verified.*
- La. R.S. 45:848: "returned to the depositor, on demand whenever the service is discontinued, and any refusal or neglect to return the balance shall subject the furnisher ... to the penalty of paying the consumer ten per cent per annum interest upon the deposit so retained after demand."

**G6. Minimum amounts and amount thresholds on refunds.** *Verified.*
- 17.5.410.19(A): "If the amount of the deposit exceeds the amount of the current bill, the residential customer may request a refund in the amount of the excess if such excess exceeds twenty five dollars ($25)." This is a partial refund measured against the current bill, not against the cap.
- OAC 4901:1-17-06(A): "unless the amount of the refund is less than one dollar".
- 83 IAC 280.40(i)(2): "not be obliged to issue the refund by separate payment instead of a credit if the amount to be refunded does not exceed 125% of the customer's average monthly bill".

**G7. Consecutive-run, OR-composite and AND-composite trigger thresholds.** *Verified.*
- **Consecutive:**
  - OAC 4901:1-17-04(B): "two consecutive bills containing a previous past due balance".
  - Kansas III.B(1): "three (3) consecutive billing periods, one of which is at least 30 days in arrears".
  - 16 NYCRR 11.12(d)(2)(i): "two consecutive months of arrears".
- **Either/or:** Ark. GSR 4.01.A(2)(c) and 4.02.A(3): "2 times in a row or any 3 times in the last 12 months".
- **Both:** 83 IAC 280.40(e)(1): "if both of the following conditions occur: A) ... paid late four times in the past 12 months; and B) ... past due balance ... unpaid for over 30 days beyond the due date."

**G8. Triggers that expire with account age or service time.** *Verified.*
- Ark. GSR 4.02.A(6): "may not charge any additional deposit under Subsection A.(6) after the first 12 months of service unless the customer moves ... or expands the business".
- Ark. GSR 4.01.B(3) and (4): "may not charge this deposit if the customer has received more than 2 years cumulative service since the utility discovered the unauthorized use or tampering".

**G9. Cap bases other than estimated annual billing or average months.** *Verified, except Georgia.*
- **Maximum or highest bills:**
  - Ark. GSR 4.02.B: "the total of the customer's 2 highest bills during the last 12 months".
  - Ark. GSR 4.01.B(4) and (6): "twice the maximum bill / billing".
  - Kansas III.D: "projected largest two (2) months' bill(s)".
  - PG&E Gas Rule 7 A.1.b and A.2.a: "twice the maximum monthly bill".
- **Seasonal or peak base:**
  - 16 NYCRR 11.12(h): "twice the estimated average monthly bill for the heating season".
  - 16 NYCRR 13.7(b)(1): "twice the average monthly usage for the peak season".
  - Ark. GSR 4.03.A(1): "total of the monthly bills during the 'season' ... divided by the number of months of usage during the season".
  - Georgia, *secondary only*: "one-half of the estimated charge for the service for the season involved".

**G10. Cap plus an add-on that is not a billing fraction.** *Verified.*
- Ark. GSR 4.01.B(3) and 4.02.B(1): "6 average bills, plus the potential damage to utility equipment".
- Kansas III.D: "If a customer has been documented to be diverting service ... an additional deposit based on one (1) months' average use may be assessed". This add-on sits on top of the 2-month cap.

**G11. Instalments anchored to bills, or set as a minimum or maximum term rather than a fixed schedule.** *Verified.*
- 83 IAC 280.40(f): "⅓ ... on the first bill statement ... remaining ⅔ ... in equal installment amounts included on the next two bill statements".
- 83 IAC 280.45(b)(4): "⅕ ... within a minimum of 12 days ... remaining ⅘ ... over the next four billing cycles".
- Ark. GSR 4.01.C: "1/2 of the deposit before receiving service and the remaining 1/2 with the first bill".
- Kansas III.D: "equal installments over a period of at least four (4) months when deposits are based on two (2) average months' usage and ... at least six (6) months when ... three (3) ... An additional two (2) months ... diversion". The schedule depends on the deposit's size basis.
- 16 NYCRR 11.12(d)(3): "installments over a period not to exceed 12 months".

**G12. No re-assessment on a move within N days.** *Verified.*
- Ark. GSR 4.08: "shall not charge an additional deposit if ... service end at one location and ... begin at another location and the change takes 90 days or less".
- Related: OAC 4901:1-17-06(A): "A transfer of service ... does not prompt a refund".

**G13. Disputed bills excluded from counts, and refunds withheld during a dispute.** *Verified.*
- Kansas III.G: "The month(s) of a disputed bill(s) shall be ignored in this calculation."
- OAC 165:45-11-1(q): "may withhold refund or return of the deposit pending the resolution of a dispute".

**G14. Events that stop interest, other than refund.** *Verified.* Check whether the schema's crediting model covers these; I could not tell from the brief.
- 17.5.410.18(B): "cease to draw interest ... on the date service is terminated".
- OAC 165:45-11-1(g): "No interest shall accrue ... after final discontinuance of service".
- Ark. GSR 4.05.B: "after the date the utility has made and documented a good faith effort to return the deposit".

**G15. Guarantor liability caps that differ from the cash cap.** *Verified.*
- OAC 4901:1-17-03(A)(5): "in an amount sufficient for a sixty-day supply".
- OAC 4901:1-17-03(C): the amount transferred is not "greater than the amount billed to the defaulting customer for sixty days of service or two monthly bills".
- Ark. GSR 4.04.B(1): liability "limited to the amount required for a deposit when the guaranty was made".

**G16. Interest credited on a calendar date, with a customer choice of cash.** *Verified.*
- K.S.A. 12-822, which binds municipal utilities: "credited on January 1 succeeding such deposit and on each January 1 thereafter ... unless, prior to January 1, such customer shall request the payment of such interest in cash".
- 16 NYCRR 13.7(e)(2): "no later than the first bill rendered after the next succeeding first day of October".

**G17. Separate account and investment limits for municipal deposit funds, and escheat to the operating fund.** *Verified.*
- K.S.A. 12-822: "keep a separate account ... may invest ... in investments authorized by K.S.A. 12-1675 ... or in savings accounts of commercial banks".
- Unclaimed deposits go to the "operating fund of such utility" after "more than three years ... published, once each week for two consecutive weeks ... within 60 days".

**G18. Recalculation after a bankruptcy discharge.** *Verified.*
- Kansas III.B(6): "Within 60 days after the bankruptcy has been discharged, if the deposit on file is less than the maximum ... may recalculate ... based on the most recent twelve months' of usage."

**G19. Periodic two-way recalculation, with a tolerance band.** *Verified.*
- 16 NYCRR 13.7(c)(1): "first anniversary ... and at least biennially thereafter ... falls short ... by 25 percent or more ... may require ... additional deposit ... exceeds ... by 25 percent or more ... shall refund the excess".
- Kansas III.G: "Large nonresidential customers will have their deposit requirements recalculated every three years ... increased or decreased".

**G20. A deadline for assessing a deposit after the triggering event, and a notice period before it.** *Verified.*
- 83 IAC 280.40(b)(1): "no later than 45 days after ... the event that justifies the deposit. A deposit shall not be assessed until the initial notice is given."
- 16 NYCRR 11.12(d)(2)(i): "provided that the utility requests such deposit within two months of such failure to pay ... written notice, at least 20 days before it may assess a deposit".
- Kansas III.B: "upon five (5) days written notice".

**G21. A cure by customer action that cancels a trigger.** *Verified.*
- 83 IAC 280.40(e)(2): "may avoid the requirement to pay a deposit under subsection (e)(1) by entering into and keeping current with a DPA ... so long as the customer enters the DPA prior to the assessment".

**G22. Mandatory return a set time after disconnection, without account close.** *Verified.*
- 83 IAC 280.40(h)(3): "refund ... automatically ... 30 days after disconnection of service for non-payment when the former customer has not paid the full balance owing or otherwise made arrangements".

**G23. Return of a deposit when the customer later enters a waiver class.** *Verified.*
- 83 IAC 280.45(b)(1): "Credit scoring deposits shall be returned to the customer upon certification as a low income customer."
- 280.45(c) keeps deposits taken for other reasons.

**G24. A trigger threshold relative to a utility-wide class average.** *Verified.*
- 83 IAC 280.45(b)(3): "final bill was greater than 20% of the average annual billing for the residential customers of the utility for the calendar year preceding".

**G25. Delinquency defined by a partial-payment fraction.** *Verified.*
- 16 NYCRR 11.12(d)(2)(i): "without making reasonable payment, defined as one half of the total arrears".
- 17.5.410.7, "chronically delinquent": a bill "not paid ... by the date a subsequent bill is rendered".

**G26. A waiver that has its own disqualifier and lookback.** *Verified.*
- 16 NYCRR 11.12(g): "No utility shall demand or hold a deposit from any ... customer it knows is 62 years of age or older unless such customer has had service terminated ... for nonpayment of bills within the preceding six months."
- Note "demand **or hold**": an existing deposit must also be released.

**G27. Monthly compounding and a rate that changes monthly.** *Verified (PG&E tariff).*
- PG&E Gas Rule 7 C.1: "calculated on a daily basis, and compounded at the end of each calendar month ... The interest rate applicable in each calendar month may vary and shall be equal to the interest rate on commercial paper (prime, 3 months) for the previous month ... when a refund is made within the first fifteen (15) days of a calendar month the interest rate applicable in the previous month shall be applied".

**G28. All accrued interest forfeited on disconnection for nonpayment.** *Verified (PG&E tariff).*
- PG&E Gas Rule 7 C.2: "No interest will be paid if service is temporarily or permanently discontinued for nonpayment of bills."

**G29. Refund deadlines in days after the qualifying event.** *Secondary for Georgia; verified elsewhere.* These matter if the schema's "return stays owed once due" needs a due date.
- O.C.G.A. 46-4-156(h): "refund the deposit ... within 60 days".
- OAC 165:45-11-1(o): "within thirty (30) days".
- 83 IAC 280.40(i): "within 30 days after the event that triggers it".
- 16 NYCRR 13.7(f)(1): "no more than 30 calendar days after".

**Borderline: holdable only by recasting.**
- The Ohio cap is a **sum** of parts (1/12 of annual + 30% of monthly). It reduces to 1.3 months, but there is no sum combinator. (OAC 4901:1-17-05(A), verified)
- Arkansas caps depend on whether bills are prepaid or postpaid and on landlord status (1, 2 or 3 average bills). This is holdable only if those are customer classes. (GSR 4.01.B(1)–(2), verified)
- The Illinois interest reference is "rounded to the nearest 0.5 %". (280.40(g)(1), verified)

# States not fully verified

- **Louisiana:** only R.S. 45:848 was verified. The LPSC deposit rule was not located, so the cap, triggers, refunds and waivers are unknown. Whether §848 applies to municipal systems is unresolved.
- **Georgia:** the LDC (Atmos) cap is secondary only, and its cited rule does not match the current code. The marketer statute was read via a mirror. No interest, trigger or waiver text was found.
- **California:** only PG&E's tariff was verified. CPUC D.20-06-003 and SoCalGas Rule 7 were not read.
- **Arkansas:** the text is verified as of the 2016 codification. Ark. Code §23-4-206 (interest) was not retrieved.
- **Municipal exclusion statutes not fetched:** Oklahoma 17 O.S. §151, Ohio R.C. 4905.02, New Mexico §62-3-3, and Arkansas jurisdiction statutes.
