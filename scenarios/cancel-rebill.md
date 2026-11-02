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
*Rule:* voiding a bill that was held and never issued posts nothing, and its replacement is an ordinary bill, not a correction: a correction may only replace a bill that was issued and then voided. Sources: Ryan 10-14 (CI-017, the void): the line is posting, not mailing; a held bill's void posts nothing (this reversed the earlier behaviour, which credited it); v5.4.2-10 (a correction names a bill that is void and was once issued).

**Given**
- The November bill run computes BB-01's bill from a read keyed as 60.0 Mcf: $541.97 ($536.60 of gas lines and $5.37 tax). It is held for high usage and never issued.
- On review the read is 6.0 Mcf.

**When** the operator voids the held bill and issues the November bill again from the corrected read.

**Then**
- The new bill is an ordinary November bill, the reference bill: **$65.83**.
- The ledger has one entry, its charge of +$65.83. The held bill's void writes no reversal, because there was no charge to reverse.
- Issuing it as a correction naming the held bill is refused: that bill was never issued.
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
- On Nov 20 BB-01 calls about the September bill. The meter's register photo from the Sep 14 read shows 4.0 Mcf; the reader keyed 5.0. The meter measured correctly: the bill was computed from a wrong figure. (A meter that measured wrong is corrected under the backbilling rules, as an adjustment on a later bill, not by void and reissue: `backbilling.md`.)

**When** the operator voids the September bill and issues the correction on Nov 20, rate basis historical (the original period's).

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
*Rule:* every correction run records whether it rebills at the original period's rates (historical), today's (current) or a stated date (custom); a run with no stated basis is refused; and a gas correction must use the original period's rates. Sources: CI-007 (structurally enforced; the parity measurement); CI-005 (a cancel-rebill uses the original period's world); Kyle 06-12 (DE-3, GBM `configurable-rules/de-review-answers.md`): gas corrections rate at the historical period, "current" is for non-gas services only.

**Given** SCN-0005's facts.

**When** the correction run is submitted three ways.

**Then**
- **No basis stated:** refused.
- **Historical:** $45.85, as in SCN-0005.
- **Current:** refused, because this is a gas correction. (Had it been allowed, the November world would have charged $48.20: $12.80, 4.0 × $2.96 = $11.84, $21.40, 4.0 × $0.42 = $1.68, tax 1% × $47.72 = $0.48, which is $2.35 more than the original period's rates. That difference is what the rule protects against.)
- The schema records the basis; the refusal of "current" for gas is the core's (Kyle's DE-3 proposed a guard; it is not yet an invariant in GBM's canonical list).
- **Open (Kyle):** DE-3 was framed as protecting a correction the Railroad Commission mandates. Since the October rulings, that Commission's customer-service rule does not bind a city-owned system like Bluebonnet. Does the "historical only" guard still apply to city systems as a platform rule, or should each city's tariff choose?

---

### SCN-0027 — A correction that charges more passes only as a price fix with the same usage

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a bill that charges more for days already billed is refused unless it is a correction naming the voided bill, its cause is recorded, and under the law row for that cause it may travel by void and reissue. Under Texas law only a rate misapplication may, and only for the same period and exactly the same usage ("correct units, wrong price"). A correction that charges less needs no cause. Sources: R-33 (a bill computed wrong is not a meter that measured wrong); R-39 (rate misapplication is not a catch-all for billing errors); R-19 (the cause is recorded on the correction); a2-rules §12; the Texas rows of v5.4.2-18 (rate misapplication: delivered by reissue, usage unchanged, enforceable for six months).

**Given**
- Gulf Plains Gas Company (`cast.md` §3), GP-01, residential, in the unincorporated area, where Texas law binds.
- Gulf Plains' residential rate, **invented for this scenario** (its tariff is not drafted): $15.00 a month and $4.10 per Mcf from Jan 1, 2026; $14.00 and $3.80 before. No tax line (**invented**).
- The February bill (Feb 1–28, read 5.0 Mcf) was issued and posted Mar 5, priced by mistake at the 2025 rates: $14.00 + 5.0 × $3.80 = $19.00, **$33.00**. Unpaid.
- On Apr 10 the mistake is found and the February bill is voided.

**When** the replacement is issued in each of these ways:
- (a) a correction naming the voided bill, cause "rate misapplication", Feb 1–28, 5.0 Mcf, at the original period's rates;
- (b) as (a), but billing 5.5 Mcf, because the read is also found keyed low;
- (c) as (a), with no cause recorded;
- (d) an ordinary February bill, not a correction, for the same amount as (a).

**Then**
- **(a)** issued:

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | $15.00 | $15.00 |
  | Gas | 5.0 Mcf × $4.10 | $20.50 |
  | **Total** | | **$35.50** |

  | Entry | Amount | Names |
  |---|---|---|
  | February bill charge | +$33.00 | — |
  | Void reversal | −$33.00 | the February charge |
  | Correction charge | +$35.50 | — (the correction names the voided bill) |
  | **Balance** | **$35.50** | |

  The extra $2.50 carries the law's limit on collection for this cause: it may ground a disconnection for six months only (R-20, §7.45(4)(E)(v)).
- **(b)** refused: a rate-misapplication correction must bill exactly the usage of the bill it replaces. More usage cannot travel by reissue under any cause.
- **(c)** refused: an increase needs its cause.
- **(d)** refused: it charges more than the voided bill for the same days, and an ordinary bill carries no cause. (The same bill at $33.00 or less would be accepted.)
- **Open (Kyle):** under (b), how is gas that was billed short because the read was keyed low corrected upward? It is not a meter that measured wrong, so not a backbilling adjustment, and the reissue path refuses more usage. None of the backbilling causes in the rulings fits "the reader keyed too low". Is it billed as a later read catching up, as an adjustment on the next bill, or something else?

---

### SCN-0028 — At a city system, an upward correction has no rule to travel by

*Status:* draft (2026-11-02), not yet sent to Kyle. Written against the ruling; the backbilling tariff table is not built.
*Rule:* as SCN-0027; the cause must resolve to a law row, and no Texas row binds a city-owned system. Until the city records its own rule, an increase is refused, while a decrease is not gated. Sources: as SCN-0027; Utilities Code 101.003(7); "unknown law is not permission"; SCN-0019.

**Given**
- Bluebonnet City Gas (`cast.md` §2), BB-01, with the facts in this file's common section.
- The November bill (Oct 15 – Nov 13, 6.0 Mcf) was issued Nov 16, priced by mistake at the pre-Oct 1 R-U rates: $11.80 + 6.0 × $2.75 = $16.50 + $32.10 + $2.52 = $62.92; tax 1% × $62.92 = $0.63; **$63.55**.
- On Nov 20 the mistake is found and the bill voided.

**When** the correction is issued, naming the voided bill, cause "rate misapplication", 6.0 Mcf: (a) today; (b) after Bluebonnet records a tariff rule copying Texas's rate-misapplication row (**invented**, as SCN-0019 b), with the delegated law row for city systems.

**Then**
- **(a)** refused: no rule says how a rate misapplication may be corrected at a city-owned system. The refusal names what is missing. The November bill stays voided until a correction is issued, so BB-01 owes nothing for November in the meantime.
- **(b)** issued: the reference bill, **$65.83**, $2.28 more than the voided bill. The record cites Bluebonnet's tariff record and the delegated row.
- By contrast, SCN-0002 and SCN-0005 (corrections that charge less) pass at Bluebonnet today: a decrease is not gated, because it can't be told apart from an honest misread correction (a2-rules §12.3).
- **Open (Kyle):** together with SCN-0019's question: when a city's ordinance is silent, can it correct an undercharge at all, and how far back? Onboarding would ask each city to state it.

---

### SCN-0030 — Correcting a bill that straddled a rate change, after its month has closed

*Status:* draft (2026-11-02), not yet sent to Kyle. Depends on SCN-0001's split rule (cast question 1).
*Rule:* as SCN-0005 and SCN-0006: the correction posts into the open period and rates at the original period's world. For a period that straddled a rate change, that world is both rates, split as the original bill split them. Sources: CI-005 (a cancel-rebill uses the original period's world); CI-110; Kyle 06-12 (DE-3); SCN-0001.

**Given**
- SCN-0001's October bill: Sep 15 – Oct 14, 6.0 Mcf, split by days across the Oct 1 rate change, issued and posted Oct 15, **$64.61**.
- October is closed on Nov 10.
- On Dec 3 the meter's register photo shows the Oct 14 read was keyed 6.0 for a true 5.0 Mcf (a keying error, as in SCN-0005).

**When** the operator voids the October bill and issues the correction on Dec 3, rate basis historical.

**Then**
- The correction repeats the original split, with the new usage:

| Line | Arithmetic | Amount |
|---|---|---|
| Customer charge, Sep 15–30 | $11.80 × 16/30 = 6.2933 | $6.29 |
| Customer charge, Oct 1–14 | $12.80 × 14/30 = 5.9733 | $5.97 |
| Distribution, Sep 15–30 | 5.0 Mcf × 16/30 = 2.6667 Mcf × $2.75 = 7.3334 | $7.33 |
| Distribution, Oct 1–14 | 5.0 Mcf × 14/30 = 2.3333 Mcf × $2.96 = 6.9066 | $6.91 |
| Commodity charge | 5.0 Mcf × $5.35 | $26.75 |
| Gas cost adjustment | 5.0 Mcf × $0.42 (the October cycle's) | $2.10 |
| City sales tax | 1% × $55.35 = 0.5535 | $0.55 |
| **Total** | | **$55.90** |

- The void (−$64.61, naming the Oct 15 charge) and the correction (+$55.90) are dated Dec 3, in December. October's closed figures are unchanged.
- **Open (Kyle):** your 06-12 proposal (DE-3) says a gas correction rates at "the voided invoice's period end". For this bill that is a single date, Oct 14, which puts the whole period at the new rates: $12.80 + 5.0 × $2.96 = $14.80 + $26.75 + $2.10 = $56.45, tax $0.56, **$57.01**. That is $1.11 more than repeating the original split. Did you mean the period-end date, or the original bill's rates however they were split?
