# Cancel and rebill

How a wrong bill is undone and replaced. Invariants: CI-007 (the rate basis of a correction is stated), CI-017 (every reversal names what it undoes), CI-110 (a closed period never reopens), CI-016 (line arithmetic). Schema at parity for these; what happens to a payment already applied to the voided bill belongs to the cash family and is written after -23 mirrors.

**Common to every scenario here.** Bluebonnet City Gas (`cast.md` §2), customer BB-01 (homeowner inside the city, schedule R-U). Rates before Oct 1 are $11.80 a month and $2.75 per Mcf (**invented**, as in SCN-0001); from Oct 1, $12.80 and $2.96 (the cast's). Commodity charge $5.35 per Mcf. Gas cost adjustment, a charge per Mcf: $0.30 on the September cycle, $0.42 on the October and November cycles (**invented**). City sales tax on residential gas 1% on every gas line (**invented**; cast question 4). Four-decimal working figures, half-up to the cent on each line (Kyle 10-15, K-06).

The reference bill, used below: **the November bill**, period Oct 15 – Nov 13, read 6.0 Mcf:

| Line | Arithmetic | Amount |
|---|---|---|
| Customer charge | $12.80 | $12.80 |
| Distribution | 6.0 Mcf × $2.96 | $17.76 |
| Commodity charge | 6.0 Mcf × $5.35 | $32.10 |
| Gas cost adjustment | 6.0 Mcf × $0.42 | $2.52 |
| City sales tax | 1% × $65.18 | $0.65 |
| **Total** | | **$65.83** |

---

### SCN-0002 — A misread found after the bill posted is voided and rebilled

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a posted bill is corrected by voiding it, which reverses its charge, and issuing a correction bill that names the voided one. Sources: every reversal names what it undoes; a correction names the bill it replaces, which must be void (Ryan 10-14, CI-017); a void of a posted bill reverses its charge (Ryan 10-14).

**Given**
- The November bill above was issued and posted on Nov 16 for $65.83. No payment has been made.
- On Nov 20 the meter reader reports a transposed read: the true usage was 4.5 Mcf, not 6.0.

**When** the operator voids the November bill and issues the correction, stating the rate basis as the original period's (historical).

**Then**

The correction bill, which names the voided bill:

| Line | Arithmetic | Amount |
|---|---|---|
| Customer charge | $12.80 | $12.80 |
| Distribution | 4.5 Mcf × $2.96 = 13.3200 | $13.32 |
| Commodity charge | 4.5 Mcf × $5.35 = 24.0750 | $24.08 (half-up) |
| Gas cost adjustment | 4.5 Mcf × $0.42 = 1.8900 | $1.89 |
| City sales tax | 1% × $52.09 = 0.5209 | $0.52 |
| **Total** | | **$52.61** |

The customer's ledger:

| Entry | Amount | Names |
|---|---|---|
| November bill charge | +$65.83 | — |
| Void reversal | −$65.83 | the November bill's charge entry, with a reason |
| Correction bill charge | +$52.61 | — (the correction bill names the voided bill) |
| **Balance** | **$52.61** | |

- The voided bill stays readable as issued; nothing on it is edited.
- A correction bill naming a bill that is not void is refused.

---

### SCN-0003 — A bill held before issue is voided: nothing posts

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* voiding a bill that was held and never issued posts nothing; only the replacement posts. Sources: Ryan 10-14 (CI-017, the void): the line is posting, not mailing; a held bill's void posts nothing (this reversed the earlier behaviour, which credited it).

**Given**
- The November bill run computes BB-01's bill from a read keyed as 60.0 Mcf: $541.97 ($536.60 of gas lines and $5.37 tax). It is held for high usage and never issued.
- On review the read is 6.0 Mcf.

**When** the operator voids the held bill and issues the replacement, which names it.

**Then**
- The replacement is the reference bill: **$65.83**.
- The ledger has one entry, the replacement's charge of +$65.83. The held bill's void writes no reversal, because there was no charge to reverse.
- Had the held bill been issued and posted first, its void would reverse $541.97 instead (SCN-0002's pattern).

---

### SCN-0004 — A void after a partial reversal reverses only what is left

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* reversals against a charge total at most the charge; a void reverses what is left after earlier reversals, and a charge already fully reversed voids with no ledger entry. Sources: Kyle 10-15 (R-02); v5.4.2-21 drafting 10-15 (the void reverses the remainder).

**Given**
- The reference bill posted on Nov 16 for $65.83.
- On Nov 18 a supervisor approves a $10.00 courtesy reversal against that bill's charge (reason recorded; **invented** example).
- On Nov 20 the read is found wrong, as in SCN-0002.

**When** the operator voids the bill and issues the correction for 4.5 Mcf.

**Then**

| Entry | Amount | Names |
|---|---|---|
| November bill charge | +$65.83 | — |
| Courtesy reversal | −$10.00 | the charge entry |
| Void reversal | −$55.83 | the charge entry: what was left |
| Correction bill charge | +$52.61 | — |
| **Balance** | **$52.61** | |

- A further reversal of any amount against the November charge is refused: nothing is left.
- **Open (Kyle):** should the $10.00 courtesy be carried onto the correction bill? As written it is lost, because the void absorbs it. Under the rule as it stands, the operator would re-grant it against the correction.

---

### SCN-0005 — A correction to a bill in a closed period posts into the open period

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a closed accounting period never reopens; the void and the correction post into an open period, and the closed period's figures stay as closed. Sources: v5.4.2-22 as drafted and reviewed 10-15/16 (a closed period never reopens; money dated inside one is refused).

**Given**
- The September bill: period Aug 15 – Sep 14, read 5.0 Mcf, issued and posted Sep 18:

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | $11.80 | $11.80 |
  | Distribution | 5.0 Mcf × $2.75 | $13.75 |
  | Commodity charge | 5.0 Mcf × $5.35 | $26.75 |
  | Gas cost adjustment | 5.0 Mcf × $0.30 | $1.50 |
  | City sales tax | 1% × $53.80 = 0.5380 | $0.54 |
  | **Total** | | **$54.34** |

- September was closed on Oct 10. November is open.
- On Nov 20 a meter test shows the September read should have been 4.0 Mcf.

**When** the operator voids the September bill and issues the correction on Nov 20, rate basis historical.

**Then**
- The correction uses September's world: the pre-Oct 1 rates and September's gas cost adjustment:

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | $11.80 | $11.80 |
  | Distribution | 4.0 Mcf × $2.75 | $11.00 |
  | Commodity charge | 4.0 Mcf × $5.35 | $21.40 |
  | Gas cost adjustment | 4.0 Mcf × $0.30 | $1.20 |
  | City sales tax | 1% × $45.40 = 0.4540 | $0.45 |
  | **Total** | | **$45.85** |

- The void reversal (−$54.34) and the correction charge (+$45.85) are both dated Nov 20, in November. Net effect on November: −$8.49.
- September's closed figures still show the $54.34 charge. A void or correction dated inside September is refused.

---

### SCN-0006 — A correction must state its rate basis; the two bases give different bills

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* every correction run records whether it rebills at the original period's rates (historical), today's (current) or a stated date (custom); a run with no stated basis is refused. Sources: CI-007 (structurally enforced; the parity measurement); "a cancel-rebill uses the original period's world" (the related invariant).

**Given** SCN-0005's facts.

**When** the correction run is submitted three ways.

**Then**
- **No basis stated:** refused.
- **Historical:** $45.85, as in SCN-0005.
- **Current:** the November world: $12.80, 4.0 × $2.96 = $11.84, $21.40, 4.0 × $0.42 = $1.68, tax 1% × $47.72 = $0.48: **$48.20**. Recorded as current, so a later reader can see why the correction charged $2.35 more than the historical one.
- **Open (Kyle):** for a misread, is "current" ever lawful, or should a correction of a past period's usage be held to historical, with current reserved for runs the tariff allows (for example a refund ordered at new rates)?
