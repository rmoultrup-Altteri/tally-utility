# The cast

The utilities, places and customers the scenarios use. Decided 2026-11-02 (DECISION-LOG: the cast is modelled on real small-city gas tariffs, under invented names). The two city systems take their structure and rates from real published Texas tariffs, cited per item from `cast-sources/texas-city-gas-tariffs-2026-11-02.md` (retrieved 2026-11-02). Anything not from a source is marked **(invented)**: a choice made so a scenario has something to test, not a claim about any real city.

A scenario names the cast member and cites only what it changes. If a scenario needs a fact the cast doesn't have, add it here first.

**What the cast does not hold.** The city's gas-cost over/under balance, its supply purchases and its year-end true-up are the city's own books, not platform records (Kyle 10-14). The platform keeps each month's gas-cost figure the city gives it, and every past one. Each utility's tariff values are its own (standing rule: the utility owns regulated values).

---

## 1. Pecan Flat Municipal Gas — the small system

Modelled on **Stinnett** (fee schedule A7.000, ordinance 339-26 of 2/11/2026). About **400 meters (invented)**; the source town has 29 miles of main and about 1,700 people.

| Item | Pecan Flat's tariff | Source |
|---|---|---|
| Classes | one: every customer on the same rate | Stinnett |
| Unit | Mcf | Stinnett |
| Minimum bill | $20.00 a month | Stinnett |
| Rate | $9.00 per Mcf, plus the city's actual gas cost per Mcf | Stinnett |
| Gas cost | the city's purchase price per Mcf, set monthly | Stinnett ("adjusted monthly as necessary") |
| Inside / outside city | same rate | Stinnett (no split) |
| Due | the 1st of the month | Stinnett |
| Late penalty | 10% of the amount due if not paid in full by the 1st | Stinnett |
| Cut-off | unpaid at 1:00 p.m. on the 10th: a $20 service charge is added and service is cut off | Stinnett |
| Deposit | residential $100, commercial $200; an extra $125 after a second disconnection for nonpayment | Stinnett |
| Deposit refund | not stated in the source. **(invented)** At move-out the deposit pays the final bill and the rest is returned; no refund while service continues | — |
| Deposit interest | not stated in the source; **none (invented)**; no state floor binds a city system | — |
| Returned check | $25, plus $7 certified mail; a $20 late fee if after the 10th | Stinnett |
| Reconnect | $30 in office hours, $45 after | Stinnett |
| Meter re-read | free once a calendar year, otherwise $5, waived if the city's read was wrong | Stinnett |
| Senior deposit | $40 for a customer aged 65 or over | borrowed from **Sealy** |
| Local sales tax on residential gas | **not adopted (invented)** | Tax Code §321.105 makes it the city's choice |
| Pipeline safety fee | **not billed (invented)** | 16 TAC §8.201 lets the operator recover it; the source is silent |
| Rate change partway through a period | **not stated in the source** (open, see below) | — |

## 2. Bluebonnet City Gas — the larger system

Modelled on **Brenham** (tariff section 500, effective 10/1/2026). About **5,000 meters**; the source serves "more than 5,100 customers". Rates are Brenham's, rounded to the nearest $0.05 or $0.01.

**Rate schedules** (per month, and per Mcf; inside the city limits is "urban", outside is "rural"):

| Schedule | Class | Who qualifies | Customer charge | Distribution |
|---|---|---|---|---|
| R-U | Residential, urban | load of 350 cubic feet an hour or less | $12.80 | $2.96 |
| SC-U | Small commercial, urban | 350 cubic feet an hour or less | $12.80 | $2.96 |
| LC-U | Large commercial, urban | over 350 cubic feet an hour | $72.10 | $2.01 |
| LI-U | Large industrial, urban | over 36,500 Mcf a year | $70.55 | $1.84 |
| R-R | Residential, rural | outside the city limits | $14.75 | $3.41 |
| SC-R | Small commercial, rural | outside the city limits | $14.75 | $3.41 |
| LC-R | Large commercial, rural | outside the city limits | $82.90 | $2.31 |
| G | Governmental | the school district, the county, the college, the state, the US, city departments | $72.10 | $1.67 |

| Item | Bluebonnet's tariff | Source |
|---|---|---|
| Unit | Mcf | Brenham |
| Gas cost | a fixed **commodity charge of $5.35 per Mcf** on every schedule, plus a monthly **gas cost adjustment** per Mcf that can be a charge or a credit | Brenham sheet 595 |
| Minimum bill | the customer charge, every month, even while service is off for the summer | Brenham |
| Due | 15 days after the bill is issued; a weekend or holiday due date moves to the next workday | Brenham |
| When a payment counts as made | **the postmark for mail, the sent date for electronic payments (invented)**; the source is silent, and the method varies by place (CI-058) | — |
| Late penalty | rates are "net"; the "gross" rate for a late payment is 10% higher | Brenham |
| Delinquency | an unpaid bill on the due date makes all the customer's city services delinquent | Brenham (the platform bills gas only; see open questions) |
| Deposit | homeowner $150; renter $250; landlord $300; commercial twice the highest monthly bill, at least $300 | Brenham |
| Deposit refund | as a bill credit after 12 months with no returned checks, no disconnect notice and no more than two late penalties. The source adds: "It is also refunded if no bill is past due" (see question 6). Applied to the final bill at disconnection | Brenham |
| Deposit interest | not stated in the source; **none (invented)** | — |
| Turn on or off at the customer's request | $50, plus $25 after hours | Brenham |
| Pilot relight | $15, or $30 after hours | Brenham |
| Taxes | "all taxes applicable to the sale of natural gas, excluding gross receipts taxes" | Brenham |
| Local sales tax on residential gas | **adopted, city rate 1% (invented)**; it applies inside the city limits only | Tax Code §321.105 |
| Pipeline safety fee | **billed once a year, $1.00 per service line, on the March bill, not to state agencies (invented timing)** | 16 TAC §8.201 |
| Rate change partway through a period | **not stated in the source** (open, see below); the 2021 release ties a change to "the October utility billing cycle" | Brenham news release 2021 |

---

## 3. Gulf Plains Gas Company — the regulated contrast

An investor-owned gas utility regulated by the Railroad Commission, serving the unincorporated area around Bluebonnet. It went live on the platform on **Jan 15, 2026 (invented)**; its meter-test history before that date was migrated. It is the case where the Texas customer-service rules (16 TAC §7.45) bind of their own force, and where a city franchise fee would apply in a city it serves. **Its tariff is not yet drafted**: it will be modelled on a real Railroad Commission tariff when the first scenario needs it.

## 4. The State of Fremont — a non-Texas set of law rows

An **invented** state, so a scenario can show that a statutory rule is a row for its place and nothing is hard-coded to Texas. Its rows are drafted when the first scenario needs them (for example, a winter disconnect ban or required deposit interest).

---

## Customers

| ID | Utility | Who | Schedule | Notes |
|---|---|---|---|---|
| PF-01 | Pecan Flat | homeowner, residential | — | deposit $100 |
| PF-02 | Pecan Flat | renter aged 67 | — | senior deposit $40 |
| BB-01 | Bluebonnet | homeowner inside the city | R-U | deposit $150 |
| BB-02 | Bluebonnet | renter outside the city | R-R | deposit $250 |
| BB-03 | Bluebonnet | the county courthouse | G | a governmental account; no pipeline safety fee if a state agency |

---

## Questions the real tariffs raise (for Kyle)

None of the five tariffs read publishes these; the scenarios need an answer, or a rule that the tariff must state one. Questions 1–4 and 6 go to Kyle with the first batch of worked bills (Ryan, 2026-11-02); question 5 is raised with Ryan when collections scenarios start (after -26 mirrors); question 7 is a schema question for Ryan.

1. **A rate change partway through a billing period.** No tariff says. Brenham's 2021 release suggests the whole bill goes at the new rates from the first billing cycle after the change. What do city systems do in practice: whole bill by cycle, by read date, or split by days? And if a tariff doesn't say, should the platform refuse to bill the straddling period until the utility states its policy? Second half: is a city's monthly gas cost adjustment a figure per billing cycle (never split), or a dated factor that splits by days like a rate?
2. **The pipeline safety fee.** Do city systems bill it, and on which bill?
3. **The 10% late penalty.** Is it on the current bill only, or on the whole amount due (previous balance and taxes too)?
4. **Local sales tax on residential gas, where a city adopts it.** Is the base every gas line (customer charge, distribution, gas cost), and is it charged outside the city limits on a rural schedule?
5. **The combined city bill.** These systems bill gas with water, sewer and trash, and an unpaid bill puts every service at risk. The platform bills gas only at first (Ryan, 2026-10-02). How should a scenario treat a customer whose gas is paid but whose water is not? (This one may be Ryan's, as a product question.)
6. **Brenham's second refund route.** "It is also refunded if no bill is past due." Read literally, almost every customer qualifies at twelve months and the late-penalty limit does nothing. Does it mean at twelve months, or at disconnection?
7. **Bill lines billed in Mcf.** The platform's rule for bill lines (Ryan 10-14, CI-016) requires every gas usage line to carry a meter factor, hundreds of cubic feet used, therms billed and a commodity rate. Both source tariffs bill per Mcf with no therm conversion, and carry the gas cost as its own line. (This one is a schema question for Ryan, not for Kyle.)
