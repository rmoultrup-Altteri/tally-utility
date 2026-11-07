# Cancel and rebill

How a wrong bill is undone and replaced. Invariants: CI-007 (the rate basis of a correction is stated), CI-017 (every reversal names what it undoes), CI-110 (a closed period never reopens), CI-016 (line arithmetic). Schema at parity for these; what happens to a payment already applied to the voided bill belongs to the cash family and is written after -23 mirrors.

**Common to every scenario here.** Bluebonnet City Gas (`cast.md` §2), customer BB-01 (homeowner inside the city, schedule R-U). Rates before Oct 1 are $11.80 a month and $2.75 per Mcf (**invented**, as in SCN-0001); from Oct 1, $12.80 and $2.96 (the cast's). Commodity charge $5.35 per Mcf. Gas cost adjustment, a charge per Mcf, as locked at each month's end for the bills of the next month (the cast's invented mapping): $0.30 on bills issued in September, $0.42 on bills issued in October and November (**invented**). City sales tax on residential gas 1%, inside the city limits, on every gas line, all of which Bluebonnet flags taxable (**invented**; Kyle 11-03, answer 4). Four-decimal working figures, half-up to the cent on each line (Kyle 10-15, K-06).

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

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
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
- A keying error is flagged to the operator, who chooses how it is corrected: by rebilling (void and rebill here, since the bill is unpaid; credit and rebill if it were paid) or by keeping the keyed read as the next bill's starting read and letting the next read catch up (Kyle 11-03, answer 7). This scenario is the rebill path; the choice, who made it and why are recorded. SCN-0027 (b) tests both paths.

---

### SCN-0003 — A bill held before issue is voided: nothing posts

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
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

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* reversals against a charge total at most the charge; a void reverses what is left after earlier reversals, and a charge already fully reversed voids with no ledger entry. A courtesy credit the void absorbed carries onto the correction bill by default; if it was given because of the very error being corrected, it is queued for an operator to review instead. Sources: Kyle 10-15 (R-02); v5.4.2-21 drafting 10-15 (the void reverses the remainder); Kyle 11-03, answer 9 (the courtesy carries).

**Given**
- The reference bill posted on Nov 16 for $65.83.
- On Nov 18 a supervisor approves a $10.00 courtesy reversal against that bill's charge, for a late service call (reason recorded; **invented** example), not for the misread.
- On Nov 20 the read is found wrong, as in SCN-0002.

**When** the operator voids the bill and issues the correction for 4.5 Mcf.

**Then**

| Entry | Amount | Names |
|---|---|---|
| November bill charge | +$65.83 | — |
| Courtesy reversal | −$10.00 | the charge entry |
| Void reversal | −$55.83 | the charge entry: what was left |
| Correction bill charge | +$52.61 | — |
| Courtesy carried | −$10.00 | the correction bill's charge entry, and the Nov 18 courtesy it carries |
| **Balance** | **$42.61** | |

- A further reversal of any amount against the November charge is refused: nothing is left.
- Had the courtesy been given for the misread itself (a customer complaint about the high bill, say), it is not carried: it is queued for an operator, who decides, and the balance stays $52.61 until then.

---

### SCN-0005 — A correction to a bill in a closed period posts into the open period

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
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

*Status:* draft (2026-11-02); checked by Kyle 2026-11-03 (answer 5); case (d) reworked to his answer 17 of 2026-11-05 (no per-target override for gas). The per-target override is built as part of CI-007's run basis; refusing it for gas is the core's.
*Rule:* every correction run records whether it rebills at the original period's rates (historical), today's (current) or a stated date (custom); a run with no stated basis is refused; and a gas correction must use the original period's rates, at a city system as well as where Texas law binds, with no per-target override (the platform default). Sources: Kyle 11-05, answer 17; Kyle 11-03, answer 5; CI-007 (structurally enforced; the parity measurement); CI-005 (a cancel-rebill uses the original period's world); Kyle 06-12 (DE-3, GBM `configurable-rules/de-review-answers.md`): gas corrections rate at the historical period, "current" is for non-gas services only.

**Given** SCN-0005's facts.

**When** the correction run is submitted three ways.

**Then**
- **No basis stated:** refused.
- **Historical:** $45.85, as in SCN-0005.
- **Current:** refused, because this is a gas correction. (Had it been allowed, the November world would have charged $48.20: $12.80, 4.0 × $2.96 = $11.84, $21.40, 4.0 × $0.42 = $1.68, tax 1% × $47.72 = $0.48, which is $2.35 more than the original period's rates. That difference is what the rule protects against.)
- The schema records the basis; the refusal of "current" for gas is the core's (Kyle's DE-3 proposed a guard; it is not yet an invariant in GBM's canonical list).
- Bluebonnet is a city system, which the Commission's customer-service rule does not bind; the guard applies anyway as the platform default (Kyle 11-03, answer 5).
- **(d) Per-target override:** the run is historical, and this one target is overridden to "current", with a reason: **refused**. A gas correction always uses the original period's rates; there is no per-target rate override for gas (Kyle 11-05, answer 17, superseding answer 5's "the per-target override stays"; basis Tex. Util. Code §104.004, no unreasonable preference within a class). A concession to one customer is a visible, approved courtesy credit instead, never a different rate. A tariff that requires corrections at current rates is a utility-wide tariff setting that applies to every customer. The override stays for non-gas services.

---

### SCN-0027 — A correction that charges more passes as a price fix, or as a keying fix the operator chose

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03. Case (b) reworked to his answer 7, and (b2)'s limits to his answer 15 of 2026-11-05; the Texas law row (v5.4.2-18) still lets only a rate misapplication travel by reissue, and revisiting it for keying errors is the rates stream's (board note).
*Rule:* a bill that charges more for days already billed is refused unless it is a correction naming the voided bill, its cause is recorded, and the cause may travel by void and reissue. Under Texas law a rate misapplication may, for the same period and exactly the same usage ("correct units, wrong price"). A human keying error may too, even when it adds usage: the system flags it to the operator, who chooses either to keep the keyed read as the next bill's starting read and let the next read catch up, or to rebill (credit and rebill if paid, void and rebill if unpaid). The choice, who made it and why are recorded, there is no size threshold, and whichever path is chosen the missed usage is billed exactly once. A correction that charges less needs no cause. Sources: Kyle 11-03, answer 7 and flag 3; R-33 (a bill computed wrong is not a meter that measured wrong); R-39 (rate misapplication is not a catch-all for billing errors); R-19 (the cause is recorded on the correction); a2-rules §12; the Texas rows of v5.4.2-18 (rate misapplication: delivered by reissue, usage unchanged, enforceable for six months).

**Given**
- Gulf Plains Gas Company (`cast.md` §3), GP-01, residential, in the unincorporated area, where Texas law binds.
- Gulf Plains' residential rate, **invented for this scenario** (its tariff is not drafted): $15.00 a month and $4.10 per Mcf from Jan 1, 2026; $14.00 and $3.80 before. No tax line (**invented**).
- The February bill (Feb 1–28, read 5.0 Mcf) was issued and posted Mar 5, priced by mistake at the 2025 rates: $14.00 + 5.0 × $3.80 = $19.00, **$33.00**. Unpaid.
- On Apr 10 the mistake is found and the February bill is voided.
- For (b) only: the register read Feb 1 was 1,000.0 Mcf; the Feb 28 read was keyed 1,005.0 for a true 1,005.5; the Mar 31 read was 1,009.5 (**invented**). The March bill (Mar 1–31), issued Apr 5 from the keyed Feb 28 read, billed 4.5 Mcf: $15.00 + 4.5 × $4.10 ($18.45) = **$33.45**, unpaid. True usage: February 5.5 Mcf, March 4.0 Mcf.

**When** the replacement is issued in each of these ways:
- (a) a correction naming the voided bill, cause "rate misapplication", Feb 1–28, 5.0 Mcf, at the original period's rates;
- (b) as (a), and the Feb 28 read is also found keyed low, the operator choosing (b1) to catch up or (b2) to rebill;
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
- **(b)** the keying error is flagged to the operator before the correction is issued.
  - **(b1) catch up:** the correction bills 5.0 Mcf, **$35.50**, as (a). The keyed 1,005.0 stays the March bill's starting read, so the March bill's 4.5 Mcf ($33.45) already carries the missed 0.5 Mcf. Nothing else changes.
  - **(b2) rebill:** the correction bills 5.5 Mcf, causes rate misapplication and keying error: $15.00 + 5.5 × $4.10 ($22.55) = **$37.55**. The March bill's starting read becomes 1,005.5, so March is voided and rebilled at 4.0 Mcf: $15.00 + 4.0 × $4.10 ($16.40) = **$31.40** (a decrease, so no cause gate).
  - Either way February and March together bill 9.5 Mcf, **$68.95**. A 5.5 Mcf February correction that leaves March starting from the keyed read is refused: it would bill the 0.5 Mcf twice.
  - The operator's choice, its maker and its reason are on the record of each path.
- **(c)** refused: an increase needs its cause.
- **(d)** refused: it charges more than the voided bill for the same days, and an ordinary bill carries no cause. (The same bill at $33.00 or less would be accepted.)
- **Under Kyle's answer 15 (11-05), where §7.45 binds:** (b1)'s catch-up on the next read is ordinary billing, with no backbilling limits. (b2)'s rebill borrows the strictest nearby §7.45 limits: it may reach back six months, and its increase may ground a disconnection for six months only; its cause is recorded as **keying/billing error**, a cause of its own. February is within six months of Apr 10, so (b2) is issued at **$37.55**, its $4.55 over the voided bill limited as (a)'s is. **Not built:** the cause is not yet in the backbilling cause list (R-39), and the Texas law row lets only a rate misapplication travel by reissue (the rates stream's; board note). Kyle's flag 3: check §7.45's cause list against the rule's current text before relying on "keying errors are not listed".
- Not yet written: answer 7's credit-and-rebill path for a bill already paid. It waits for the cash family (v5.4.2-23); it must be tested against the next bill's starting read too (Kyle's flag 3).

---

### SCN-0028 — At a city system with no stated rule, an upward correction takes the six-month default

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03 (one display fix applied). Reworked to his answer 8. Written against the ruling; the backbilling tariff table and the platform's default row are not built (the rates stream's; board note).
*Rule:* as SCN-0027; no Texas row binds a city-owned system. Where the city's ordinance says nothing, an undercharge may be corrected back six months by platform default, and the city may replace that by recording its own rule, citing its ordinance; a decrease is not limited at all. Sources: Kyle 11-03, answer 8; as SCN-0027; Utilities Code 101.003(7); SCN-0019.

**Given**
- Bluebonnet City Gas (`cast.md` §2), BB-01, with the facts in this file's common section.
- The November bill (Oct 15 – Nov 13, 6.0 Mcf) was issued Nov 16, priced by mistake at the pre-Oct 1 R-U rates: $11.80 + 6.0 × $2.75 ($16.50) + $32.10 + $2.52 = $62.92; tax 1% × $62.92 = $0.63; **$63.55**.
- On Nov 20 the mistake is found and the bill voided.

**When** the correction is issued, naming the voided bill, cause "rate misapplication", 6.0 Mcf: (a) with Bluebonnet's ordinance silent; (b) after Bluebonnet records a tariff rule copying Texas's rate-misapplication row, citing its ordinance (**invented**, as SCN-0019 b), with the delegated law row for city systems.

**Then**
- **(a)** issued: the reference bill, **$65.83**, $2.28 more than the voided bill. The November period is well inside six months, so the platform default admits it; the record cites the default, not a Bluebonnet rule.
- **(b)** issued: the same **$65.83**. The record cites Bluebonnet's tariff record and the delegated row instead of the default.
- SCN-0002 and SCN-0005 (corrections that charge less) pass at Bluebonnet either way: a decrease is never limited by the default.

---

### SCN-0030 — Correcting a bill that straddled a rate change, after its month has closed

*Status:* draft (2026-11-02); checked by Kyle 2026-11-03 and confirmed as written: $55.90 (answer 6).
*Rule:* as SCN-0005 and SCN-0006: the correction posts into the open period and rates at the original period's world. For a period that straddled a rate change, that world is both rates, split as the original bill split them: a correction repeats the original bill's rate method and changes only what was wrong. Sources: Kyle 11-03, answer 6 (DE-3's "period end" was shorthand); CI-005 (a cancel-rebill uses the original period's world); CI-110; Kyle 06-12 (DE-3); SCN-0001.

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
- Not $57.01: rating the whole period at the Oct 14 rates ($12.80 + 5.0 × $2.96 ($14.80) + $26.75 + $2.10 = $56.45, tax $0.56) is not the historical basis: it would change the rate method as well as the usage. A test expecting $57.01 is wrong.

---

### SCN-0033 — A bill voided after its late penalty posted: the penalty is re-assessed on the lower amount, and what the error hid goes on the next bill

*Status:* draft (2026-11-04); reworked 2026-11-05 to Kyle's answers 1, 2, 3a and 3b of batch 2 (GBM `application/kyle-decisions-2026-11-05-scenario-batch-2.md`); the figures are not yet checked by Kyle (his flag 6). Written against the rulings: the late-penalty rules are dated rule data not yet built (Kyle 10-15, R-11), penalties belong with collections (v5.4.2-26, not yet built). How the corrected November bill shows the split in (b) is this stream's reading (below). The penalty's tax treatment on a gross/net tariff waits on a tax advisor before a gross/net city goes live (Kyle 3b).
*Rule:* a late penalty is its own charge, naming the bill it was assessed on. When the utility's error makes a bill void and corrected, the penalty is reversed in full, naming the penalty entry, with the void as its reason, and re-assessed only on the **lower** of the original and the corrected amount: the customer was late on money they knew about, not on money the error hid. That amount keeps the original due date and age; any extra the error hid goes on the **next regular bill** as a prior-period correction line, with that bill's due date and age. The penalty's base is every line the tariff prices (customer charge, distribution, commodity charge, gas cost adjustment), never a tax or a state fee. On a gross/net tariff such as Bluebonnet's, the extra is a forfeited prompt-payment discount, taxed like the gas (city sales tax on residential gas inside the city). A penalty is charged once and never compounds. No penalty is charged on a bill while the customer's dispute of it is open. Sources: Kyle 11-05, answers 1, 2, 3a, 3b; Kyle 11-03, answer 3 (current bill only, charged once); every reversal names what it undoes, capped at it (Kyle 10-15, R-02; CI-017); Bluebonnet's tariff (`cast.md` §2: due 15 days after issue, rolling to the next workday; the late "gross" rate 10% higher).

**Given**
- The reference November bill: issued and posted Mon Nov 16, **$65.83**, due Tue Dec 1. Unpaid. Its tariff-priced lines total $65.18.
- On Wed Dec 2 a penalty posts, naming the November bill: 10% × $65.18 = 6.5180 → **$6.52**, and city sales tax on it, 1% × $6.52 = 0.0652 → **$0.07**: **$6.59** in all.
- On Fri Dec 4 the read is found keyed wrong, and the operator chooses to void and rebill (Kyle 11-03, answer 7). The true read is (a) 4.5 Mcf, as SCN-0002; (b) 7.5 Mcf.

**When** the operator voids the November bill and issues the correction on Dec 4, rate basis historical.

**Then**
- **(a)** The correction is SCN-0002's, **$52.61** (tariff-priced lines $52.09), lower than the original, so it is the amount re-assessed. It keeps the Dec 1 due date, and all of it was late.

  | Entry | Amount | Names |
  |---|---|---|
  | November bill charge (Nov 16) | +$65.83 | — |
  | Late penalty (Dec 2) | +$6.52 | the November bill |
  | City sales tax on the penalty (Dec 2) | +$0.07 | the penalty |
  | Void reversal (Dec 4) | −$65.83 | the November bill's charge |
  | Penalty reversal (Dec 4) | −$6.52 | the Dec 2 penalty; reason: the bill it was assessed on is void |
  | Tax reversal (Dec 4) | −$0.07 | the Dec 2 tax on the penalty |
  | Correction charge (Dec 4) | +$52.61 | — (names the voided bill) |
  | Late penalty on the correction (Dec 4) | +$5.21 | the correction: 10% × $52.09 = 5.2090, late since Dec 1 |
  | City sales tax on it (Dec 4) | +$0.05 | 1% × $5.21 = 0.0521 |
  | **Balance** | **$57.87** | |

- **(b)** The true November bill at 7.5 Mcf:

  | Line | Arithmetic | Amount |
  |---|---|---|
  | Customer charge | $12.80 | $12.80 |
  | Distribution | 7.5 Mcf × $2.96 = 22.2000 | $22.20 |
  | Commodity charge | 7.5 Mcf × $5.35 = 40.1250 | $40.13 (half-up) |
  | Gas cost adjustment | 7.5 Mcf × $0.42 = 3.1500 | $3.15 |
  | City sales tax | 1% × $78.28 = 0.7828 | $0.78 |
  | **Total** | | **$79.06** |

  The original, $65.83, is the lower, so it is what BB-01 is held to at the Dec 1 due date, and what the penalty is re-assessed on: the Dec 2 penalty and its tax are reversed (−$6.52, −$0.07) and assessed again on the correction, **$6.52 + $0.07**, naming it. Balance on Dec 4: $65.83 + $6.59 = **$72.42**.
  - The **$13.23** the error hid ($79.06 − $65.83) goes on BB-01's December bill (issued Wed Dec 16, due Thu Dec 31) as a prior-period correction line naming the November correction, cause keying error, under Bluebonnet's six-month default for an upward correction (SCN-0028). It is due with the December bill and ages from it. No penalty is charged on it unless the December bill is paid late.
  - This stream's reading of how the correction shows the split: the November correction is issued at the lower figure, $65.83, and the $13.23 is billed only on the December line, so it is never owed twice. **Open (Ryan):** whether instead the correction shows the full $79.06 with $13.23 marked as moved to the next bill. Either way the customer owes $65.83 from Dec 1 and $13.23 from Dec 31.
- Had BB-01 disputed the November bill before Dec 1, with the dispute still open on Dec 2, no penalty would have posted (Kyle 11-05, answer 1). Bluebonnet has its own dispute rule (`cast.md`, from Brenham's): the disputed bill should still be paid, and no disconnection or credit harm follows during the investigation; it says nothing of the penalty. **Open (Ryan):** where a city's own rule requires the disputed bill to be paid, does Kyle's answer 1 (no penalty while the dispute is open) still hold, or does the city's rule govern, so the Dec 2 penalty posts if BB-01 did not pay? (The platform default of 2026-11-07, protection until resolved or 60 days after issue, applies only to a city with no rule of its own.)
- In both, the voided bill and the original penalty stay readable as posted; nothing is edited.
- **Open (Kyle):** answer 2 is about a rebill for the utility's error. Does the hidden extra also go to the next regular bill for the other upward corrections already written (a rate misapplication, SCN-0027 a; a city's six-month default, SCN-0028), or do those keep the increase on the correction itself, as written there?
