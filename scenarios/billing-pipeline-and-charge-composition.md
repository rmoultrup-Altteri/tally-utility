# Billing pipeline and charge composition

How one bill is assembled from its charges. Invariants: CI-016 (each line carries its own arithmetic), CI-109 (rounding), the mid-period rate selection family. Schema at parity (the measurement, `application/invariant-parity-measurement-2026-10-13.md`).

### SCN-0001 — Rates change partway through a billing period

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03 (no errors). Split rule settled: the method is stated when the rate change is entered (Kyle 11-03, answer 1).
*Rule:* when a city's ordinance changes rates partway through a billing period, the bill applies each rate to its share of the period by the method stated when the rate change was entered (split by days, by read date, or by cycle; there is no default, so a rate change entered without one is refused at setup, not at billing), and each line shows its own arithmetic. The gas cost adjustment is one figure per billing month, set at month end and never split. Sources: Kyle 11-03 answer 1 (the method at entry; the monthly gas cost figure) and answer 4 (city sales tax inside city limits, on lines flagged taxable); each line carries its own arithmetic (Ryan 10-14, CI-016; Kyle 10-15, R-01); four-decimal working math, half-up to the cent (Kyle 10-15, K-06); every charge declares whether it is taxable (Kyle 10-14).

**Given**
- Bluebonnet City Gas (`cast.md` §2); customer BB-01, a homeowner inside the city, schedule R-U.
- An ordinance effective Oct 1 raises R-U from $11.80 to $12.80 a month and from $2.75 to $2.96 per Mcf. The new rates are the cast's; **the old ones are invented**.
- **Bluebonnet entered the Oct 1 rate change with the method "split by days" (invented; the source tariff is silent, so the city chooses at entry).**
- Commodity charge $5.35 per Mcf; the gas cost adjustment is a charge of $0.42 per Mcf (invented), set and locked at the end of September, so it applies to bills issued in October (the cast's invented mapping); it applies to the whole bill and is never split (Kyle 11-03, answer 1).
- City sales tax on residential gas inside the city at 1% (invented); BB-01's premise is inside the city limits, and Bluebonnet flags every gas line taxable (invented).
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
- Had the Oct 1 rate change been entered with no method, it is refused when entered; no bill is ever held for want of one.
- Changing September's locked gas cost figure after it is locked is refused. An October bill issued while no figure is locked for September is refused; it waits until one is.
- Had it been entered as "by read date", the rates in force on the closing read's date (Oct 14) apply to the whole bill: the same **$65.83** as by cycle here, since Oct 14 is after the change. A read taken Sep 29 on a period ending then would bill wholly at the old rates.
- Had it been entered as "by cycle" (the method Brenham's 2021 release suggests), the whole bill goes at the new rates: $12.80 + 6.0 × $2.96 ($17.76) + $32.10 + $2.52 = $65.18, tax $0.65, **$65.83** (the reference bill of `cancel-rebill.md`).

- The distribution lines are billed in Mcf, a volume unit, so they carry quantity, unit and rate only; the gas conversion figures (meter factor, Ccf, therms, commodity rate) are required only on a line billed in an energy unit (Ryan 2026-11-04, cast question 7). A line whose unit is not one of therm, dekatherm, MMBtu, Ccf or Mcf is refused at issue.

---

### SCN-0048 — A customer 60 or over may ask for a later due date, and pays no penalty until it

*Status:* draft (2026-11-04), not yet sent to Kyle. That Utilities Code chapter 182 binds city gas systems is Ryan's reading of 10-18, put to Kyle and not yet answered. Reviewer gap (Opus, 2026-11-02, A8).
*Rule:* on request from a customer aged 60 or over who is a residential customer and occupies the whole premises, a utility must delay a bill's payment date without penalty until the 25th day after the bill is issued, for the latest bill or for that bill and every later one; the utility may ask for proof of age. "Utility" includes one run by a public entity, so it reaches a city system. Sources: Tex. Util. Code §§182.001 (a "utility" is "an electric, gas, water, or telephone utility operated by a public or private entity"), 182.002, 182.003, 182.004, 182.005 (official text: https://statutes.capitol.texas.gov/Docs/UT/htm/UT.182.htm; read 2026-11-04 from a FindLaw copy stated current to Jan 1, 2026, and the reading confirmed by all three reviewers); Ryan 10-18 (for Kyle). The text is verified; that the platform applies it to city systems waits on Kyle.

**Given**
- Bluebonnet City Gas; **BB-04 (invented)**, aged 63, residential, the only occupant of the house, schedule R-U. Proof of age on file. On Nov 2, 2026 BB-04 asks for the delay on every bill from then on.
- The reference November bill (`cancel-rebill.md`), issued Mon Nov 16, 2026, **$65.83**. Bluebonnet's ordinary due date is 15 days after issue, Tue Dec 1; the late penalty is 10% of the bill (the reading of SCN-0033, open with Kyle there).

**When** BB-04 pays (a) on Tue Dec 8; (b) on Mon Dec 14; (c) as (a), but BB-04 had made no request; (d) as (a), but BB-04 asked for the delay on the November bill only.

**Then**
- BB-04's due date is the 25th day after issue: **Fri Dec 11, 2026**.
- **(a)** On time: no penalty. This stream reads it as on time for anything else that counts late payments too, such as a deposit refund's limit (SCN-0007): open with Kyle, below.
- **(b)** Late from Dec 12: a penalty of **$6.58** posts after Dec 11, not after Dec 1.
- **(c)** Late from Dec 2: the penalty of $6.58 posts after Dec 1, as for any customer. The delay applies only on request.
- **(d)** The November bill is due Dec 11 as in (a); the December bill is due 15 days after issue, as for any customer, unless BB-04 asks again.
- The request, its scope (one bill or every later one) and the proof of age are on record; each bill shows the delayed due date.
- **Open (Kyle):** (1) Does chapter 182 bind city systems, as read on 10-18? (2) Confirm: §182.005's three conditions are joined by "and", and the third (regulated under Title 2, electricity and telecoms) never fits a gas utility, so the exclusion never reaches one. (3) Pecan Flat's bills are due on the 1st and service is cut off on the 10th. If its bill goes out late in the month before, the 25th day comes after the cut-off date. Does the delay hold back the cut-off too? (4) Does the delay also make a payment on time for a deposit refund's late-payment limit, or only free it of the penalty?
