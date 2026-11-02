# Billing pipeline and charge composition

How one bill is assembled from its charges. Invariants: CI-016 (each line carries its own arithmetic), CI-109 (rounding), the mid-period rate selection family. Schema at parity (the measurement, `application/invariant-parity-measurement-2026-10-13.md`).

### SCN-0001 — Rates change partway through a billing period

*Status:* draft (2026-11-02), not yet sent to Kyle. Its split rule waits on Kyle (cast question 1).
*Rule:* when a city's ordinance changes rates partway through a billing period, the bill applies each rate to its share of the period as the tariff says, and each line shows its own arithmetic. Sources: each line carries its own arithmetic (Ryan 10-14, CI-016; Kyle 10-15, R-01); four-decimal working math, half-up to the cent (Kyle 10-15, K-06); every charge declares whether it is taxable (Kyle 10-14).

**Given**
- Bluebonnet City Gas (`cast.md` §2); customer BB-01, a homeowner inside the city, schedule R-U.
- An ordinance effective Oct 1 raises R-U from $11.80 to $12.80 a month and from $2.75 to $2.96 per Mcf. The new rates are the cast's; **the old ones are invented**.
- **For this scenario, the tariff states that a period straddling a rate change is split by days (invented; the source tariff is silent, cast question 1).**
- Commodity charge $5.35 per Mcf; the gas cost adjustment for the cycle is a charge of $0.42 per Mcf (invented). **Assumed: the city sets its gas cost adjustment per billing cycle**, so a cycle never straddles a change of it; if it is a dated factor instead, it splits like a rate (CI-034). That is part of cast question 1.
- City sales tax on residential gas inside the city at 1% (invented), on every gas line (cast question 4).
- Billing period Sep 15 – Oct 14, 30 days. Reads 6.0 Mcf.

**When** the October bill is issued.

**Then**

| Line | Arithmetic | Amount |
|---|---|---|
| Customer charge, Sep 15–30 | $11.80 × 16/30 = 6.2933 | $6.29 |
| Customer charge, Oct 1–14 | $12.80 × 14/30 = 5.9733 | $5.97 |
| Distribution, Sep 15–30 | 6.0 Mcf × 16/30 = 3.2000 Mcf × $2.75 = 8.8000 | $8.80 |
| Distribution, Oct 1–14 | 6.0 Mcf × 14/30 = 2.8000 Mcf × $2.96 = 8.2880 | $8.29 |
| Commodity charge | 6.0 Mcf × $5.35 | $32.10 |
| Gas cost adjustment | 6.0 Mcf × $0.42 | $2.52 |
| City sales tax | 1% × $63.97 (the six lines above) = 0.6397 | $0.64 |
| **Total** | | **$64.61** |

- Each customer-charge line records its coverage dates, the days it covers, the days in the period and the split policy applied.
- Each distribution line records its quantity, unit and rate; the tax line records the lines in its base.

**Open (Ryan):** cast question 7: the bill-line rule requires therms and a meter factor on every gas usage line, which an Mcf tariff does not use; as written, this bill's distribution lines would be refused at issue.

**Open (Kyle):** cast question 1 (how a mid-period change is billed; if the whole bill goes at the new rates, the total is $65.18 before tax: $12.80 + 6.0 × $2.96 + $32.10 + $2.52). Cast question 4 (the tax base).
