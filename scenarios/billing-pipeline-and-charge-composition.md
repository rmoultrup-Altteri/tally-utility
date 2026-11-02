# Billing pipeline and charge composition

How one bill is assembled from its charges. Invariants: CI-016 (each line carries its own arithmetic), CI-109 (rounding), the mid-period rate selection family. Schema at parity (the measurement, `application/invariant-parity-measurement-2026-10-13.md`).

### SCN-0001 — Rates change partway through a billing period

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* when a city's ordinance changes rates partway through a billing period, the bill splits each charge at the effective date as its tariff says, and each line shows its own arithmetic. Sources: each line carries its own arithmetic (Ryan 10-14, CI-016; Kyle 10-15, R-01); four-decimal working math, half-up to the cent (Kyle 10-15, K-06).

**Given**
- Cedar Bend Municipal Gas, a city-owned system. Its tariff (invented for this example) splits a period by days at a rate change.
- A residential customer; billing period Oct 15 – Nov 13, 30 days.
- An ordinance effective Nov 1: customer charge $12.00 → $14.00 a month; delivery $6.50 → $7.00 per Mcf.
- Gas-cost factor for the period: $4.1250 per Mcf.
- Reads 1,234 → 1,286 hundred cubic feet: 52 hundred cubic feet, 5.2 Mcf.

**When** the November bill is issued.

**Then**

| Line | Arithmetic | Amount |
|---|---|---|
| Customer charge, Oct 15–31 | $12.00 × 17/30 days | $6.80 |
| Customer charge, Nov 1–13 | $14.00 × 13/30 = 6.0667 | $6.07 |
| Delivery, Oct 15–31 | 5.2 Mcf × 17/30 = 2.9467 Mcf × $6.50 = 19.1536 | $19.15 |
| Delivery, Nov 1–13 | 5.2 Mcf × 13/30 = 2.2533 Mcf × $7.00 = 15.7731 | $15.77 |
| Gas cost | 5.2 Mcf × $4.1250 | $21.45 |
| **Total** | | **$69.24** |

- Each customer-charge line records its coverage dates, the days it covers, the days in the period and the split policy applied.
- Each delivery line records its quantity, unit and rate.

**Open (Kyle):** does the gas-cost factor split at its own change date, or follow the bill date? Does any tax, or the pipeline safety fee, apply to a residential bill from a city-owned system?
