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
- **Open (Kyle, sent 2026-11-05):** (1) Does chapter 182 bind city systems, as read on 10-18? (2) Confirm: §182.005's three conditions are joined by "and", and the third (regulated under Title 2, electricity and telecoms) never fits a gas utility, so the exclusion never reaches one. (3) Pecan Flat's bills are due on the 1st and service is cut off on the 10th. If its bill goes out late in the month before, the 25th day comes after the cut-off date. Does the delay hold back the cut-off too? (4) Does the delay also make a payment on time for a deposit refund's late-payment limit, or only free it of the penalty?

---

### SCN-0053 — Pecan Flat's late penalty is 10% of the whole amount due, because its tariff says so

*Status:* draft (2026-11-04), not yet sent to Kyle. Review round 2 gap (Opus 7, Fable 6). The late-penalty rules are dated rule data not yet built (R-11).
*Rule:* where a city's tariff states the penalty's base, the tariff governs over the platform default (the current bill only). Pecan Flat charges 10% of the amount due if it is not paid in full by the 1st. Sources: Kyle 11-03, answer 3 and flag 2; Pecan Flat's tariff (`cast.md` §1, from Stinnett).

**Given**
- Pecan Flat; PF-01. Gas cost for the month $6.10 per Mcf (**invented**), so $15.10 per Mcf with the $9.00 rate.
- The January bill, $95.00 (**invented**), was due Feb 1 and is unpaid; a penalty of 10% × $95.00 = **$9.50** posted Feb 2.
- The February bill, issued Feb 20, due Mar 1 (**invented** issue date): 8.0 Mcf × $9.00 = $72.00, plus 8.0 Mcf × $6.10 = $48.80: **$120.80**. Amount due on Mar 1: $95.00 + $9.50 + $120.80 = **$225.30**.

**When** nothing is paid by Mar 1.

**Then**
- The penalty is on the whole amount due, not the current bill only. Two readings, open with Kyle: **$22.53** (10% × $225.30, the earlier penalty included) or **$21.58** (10% × $215.80, the earlier penalty left out). The platform default would have given $12.08 (10% × $120.80).
- The penalty names the bills it was assessed on.
- **Open (Kyle, sent 2026-11-05):** Pecan Flat's "10% of the amount due": does the amount due include an earlier penalty? Answer 3's default never charges a penalty on a penalty, but this is the tariff's own wording.

---

### SCN-0054 — The pipeline safety fee: once, in the month the city passes it on, never to a state agency

*Status:* draft (2026-11-04), not yet sent to Kyle. Review round 2 gap (Opus 8, Codex 14). The state-agency check is the rates stream's v5.4.2-28 (in review). Treating a county as not a state agency is this stream's reading of §8.201: open.
*Rule:* a city that passes the pipeline safety fee on bills it once, in the month it chooses, as a flat charge of at most $1.00 per service line, never before it has paid the fee to the Commission, and never to a state agency. A city that absorbs it never shows it. Sources: Kyle 11-03, answer 2; 16 TAC §8.201; `cast.md` §1–2.

**Given**
- Bluebonnet bills the fee on its March bills (`cast.md` §2, invented timing); it paid the Commission on Mar 1, 2027 (**invented**).
- Its March 2027 bills: BB-01 (homeowner); BB-03 (the county courthouse, schedule G); **BB-07 (invented)**, a state office building, schedule G. Bluebonnet doesn't flag the fee taxable (**invented**).
- Pecan Flat absorbs the fee.

**When** (a) the March bills are issued on Mar 15, 2027; (b) a bill issued Feb 15, 2027 carries the fee; (c) a second fee is added to BB-01's April 2027 bill; (d) Pecan Flat's March bills are issued.

**Then**
- **(a)** BB-01's bill carries one line, pipeline safety fee **$1.00**, outside the sales tax base: with the reference bill's lines that is $65.83 + $1.00 = **$66.83**. BB-03's bill carries it too: a county is not a state agency. BB-07's carries none.
- **(b)** Refused: the fee may not be billed before Bluebonnet paid it (Mar 1).
- **(c)** Refused: the fee is billed once for the year.
- **(d)** No fee line on any bill.
- **Open (Kyle, sent 2026-11-05):** is a county (or a school district, or the college) outside §8.201's state-agency exemption, as written here?

---

### SCN-0055 — Outside the city: no city sales tax; a gas cost credit; a pressure factor shown with its raw reading

*Status:* draft (2026-11-04), not yet sent to Kyle. Review round 2 gap (Opus 9, Codex 14). The unit list and the multiplier rule are Ryan's 2026-11-04 decision; the money stream's patch is not drafted.
*Rule:* city sales tax applies only inside the city limits; a gas cost adjustment may be a credit; a multiplier is recorded with the raw quantity it multiplied, and a volume-billed line carries quantity, unit and rate. Sources: Kyle 11-03, answer 4; Bluebonnet's tariff (`cast.md` §2: the adjustment can be a charge or a credit); Ryan 2026-11-04 (DECISION-LOG: gas bill lines).

**Given** Bluebonnet; the October billing month's figures, except as stated.

**When** the bill is issued for (a) BB-02, outside the city, schedule R-R, 6.0 Mcf, adjustment $0.42; (b) the same with a gas cost credit of −$0.15 per Mcf (**invented**); (c) **BB-08 (invented)**, a large commercial customer outside the city, schedule LC-R, served at elevated pressure with a pressure factor of 1.0400 (**invented**), meter reading 40.0 Mcf, adjustment $0.42.

**Then**

| Line | (a) | (b) |
|---|---|---|
| Customer charge | $14.75 | $14.75 |
| Distribution, 6.0 Mcf × $3.41 | $20.46 | $20.46 |
| Commodity charge, 6.0 Mcf × $5.35 | $32.10 | $32.10 |
| Gas cost adjustment | 6.0 × $0.42 = $2.52 | 6.0 × −$0.15 = −$0.90 |
| City sales tax | none: outside the city | none |
| **Total** | **$69.83** | **$66.41** |

- **(c)** Billed volume 40.0 Mcf × 1.0400 = 41.6000 Mcf:

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | $82.90 | $82.90 |
  | Distribution | 41.6000 Mcf × $2.31 = 96.0960 | $96.10 |
  | Commodity charge | 41.6000 Mcf × $5.35 = 222.5600 | $222.56 |
  | Gas cost adjustment | 41.6000 Mcf × $0.42 = 17.4720 | $17.47 |
  | **Total** | | **$419.03** |

  The usage lines record the reading (40.0 Mcf), the factor (1.0400) and the billed quantity (41.6000 Mcf). A line carrying the factor without the reading is refused at issue. No therm figures are needed: the line is billed in Mcf.
- A line whose unit is not Ccf, Mcf, therm, dekatherm or MMBtu is refused at issue.
