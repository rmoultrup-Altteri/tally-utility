# Round 9 review: gas cost, zones and reads, SCN-0155 – 0162 (Opus)

Scope: `scenarios/gas-cost-zones-and-reads.md` lines 530–674, and the cast rows BB-22 – BB-26, GP-10, GP-11, PF-08 (`scenarios/cast.md` lines 179–186). Read-only. GBM `main` was fetched; nothing new there since Nov 24.

## Arithmetic: recomputed, all correct

Every dollar figure and volume in SCN-0155 – 0162 recomputes: four-decimal working figures, half-up per line, and tax on the sum of the rounded lines. Specific checks:

- SCN-0155: the estimate 9.3 × 10/31 = 3.0000. The final bill is $31.11 (tax base $30.80) and the deposit remainder $118.89. The shares are 8.0 × 10/31 = 2.5806, so 2.6 and 5.4. The corrected final is $27.52 (base $27.25, overbilled $3.59). BB-23 is $57.94 (base $57.37), and the alternative at 5.0 Mcf is $54.31.
- SCN-0156: $149.24, and the alternative $163.99.
- SCN-0157: $36.75, $33.00 and $34.20.
- SCN-0158: 7.1 Mcf, $68.25, and 9.0 + 7.1 = 16.1.
- SCN-0159: all eight bills ($35.59, $35.87, $35.87, $81.07; $35.59, $37.71, $38.62, $76.40). The averages are 2.4667 (rounds to 2.5) and 2.6. Both columns total 14.0 Mcf.
- SCN-0160: $51.47 and $89.47.
- SCN-0161: 15 × 19/28 = 10.1786 ($10.18), then $38.68, 6.2 Mcf ($61.50) and $78.00.
- SCN-0162: $120.80, $39.26 and $41.21. The refund is $60.74 + $20.80 = $81.54. In (b) the customer owes $81.54, and the penalty is $8.15.

Weekdays and due dates all check out: Dec 10 2026 Thu, Dec 11 Fri, Dec 26 Sat → Mon Dec 28, Nov 16 + 15 = Tue Dec 1, Oct 5 2027 Tue + 20 = Mon Oct 25, Oct 8 2027 Fri, Oct 21 Thu, Mar 1 2027 Mon, May 1 Sat, May 3 Mon, May 5 Wed, Nov 13 2026 Fri, Nov 20 Fri, Feb 10 2027 Wed, Mar 5 Fri, Apr 5 Mon, Nov 30 2026 Mon, Dec 4 Fri, Dec 2 Wed, Dec 9 Wed, Jan 1 2027 Fri.

## Findings

### 1. SCN-0155, Status and Sources (lines 534–535): the wrong invariant is cited, and "not built" overstates the gap. **Blocking**

- **Wrong invariant.** The scenario says "the move-out events require a final reading, CI-123". CI-123 is the rule that a meter change-out reaches billing before the bill is generated (GBM `application/canonical-invariants.md:2136`; measurement `invariant-parity-measurement-2026-10-13.md:432`). The rule that a move-out produces a final-read capture, a prorated final bill and a deposit disposition is CI-122 (`canonical-invariants.md`, the CI-122 section just above line 2136; measurement line 431: partial, the core orchestrates it). The mistake comes from GBM's own `final-bill-generation.md:41` ("CI-123 makes the final read a required move-out event"), which mis-cites it too.
- **More is built than the scenario says.** The schema can already record an estimated final reading. A reading's purpose may be "final read" (`sql/tu.sql:3582`), it can be marked estimated with the reason "access issue" (`tu.sql:3578`), and it can be flagged as the boundary between two customers, naming the outgoing and incoming customer (`tu.sql:3545–3547`, comment at 3593). Nothing refuses an estimated final reading.
- **Fix.** Cite CI-122. Restate the not-built part: the move-out workflow is the core's (CI-122 partial), and so are the sharing of gas between two actual readings and the figure by billing month. Note in GBM's ingestion log that `final-bill-generation.md` mis-cites CI-123.
- **Consistency with SCN-0146.** The same transition flag also contradicts SCN-0146's Status (line 360: "one reading that is both one customer's final and the next one's first has no single purpose in the list"). There is a dedicated flag for exactly that reading. Worth a line in SCN-0146.

### 2. SCN-0156, Status (line 554): "Built: the customer charge is billed whatever the usage (CI-102)" is wrong. **Blocking**

The measurement grades CI-102 "requires-app-discipline" (`invariant-parity-measurement-2026-10-13.md:411`). Its note says the core must emit the customer-charge line for every active account, must not let a meter skipped for no read drop it, and that "No schema mechanism fits."

Fix: move this to "the core's". The built part is that a billing run can record a meter skipped for no read, and that a fixed monthly charge exists as a charge kind.

### 3. SCN-0160, Status (line 629): "Built: … an actual dated earlier than estimates already entered raises its own review" is wrong. **Blocking**

- **What is built.** Only the run count is built: a back-dated actual doesn't clear the estimates dated after it (`tu.sql:16895–16900`, 17304–17309; AC-21).
- **What is not.** No trigger raises a review for a back-dated actual, and no rule code names one. The list is high or low against history, reverse read, rollover, over the cap, zero read, date gap, negative consumption, incomplete meter record, tamper, and other (`tu.sql:17093–17096`). SCN-0142's "Settled by rule" calls this "the built rule", but only the part about not clearing the run is built.
- **Fix.** Say "Built: a back-dated actual doesn't end the run (AC-21); a review can be recorded on it (as 'other'). Raising the review is the core's." The existing "Not built: a reason for the review" is then accurate.

### 4. SCN-0160 (a), (b′), line 637 ff.: this can't be built into a test as written. **Should-fix**

- **(a) Order of steps.** As built, a reading with an open review can't be approved (AC-20). So "validated as an actual and raises a review" has to happen in this order: the review is raised, the reviewer resolves it ("the billed estimate stands"), and then the reading is validated. Name the resolution kind (an override with that reason, presumably). If it were resolved as excluded instead, the Nov 13 reading would not become the latest actual.
- **(a) A backwards step in the readings.** Once the Nov 13 reading (506.2) is in, the meter's history runs 506.2 on Nov 13 and then 504.0 on Nov 15, which is backwards. The built reverse-read rule (`tu.sql:17094`) exists for exactly this. Say whether the core raises it, and on which reading. Per AC-20 it can't be raised on the billed (locked) Nov 15 estimate. Also say it is not a rollover (SCN-0143).
- **(b′) No figure.** No estimate is given. State the December estimated reading and its base. Is it the Nov 15 estimate plus 4.0 (508.0), or the Nov 13 actual plus a pro-rata share? Under SCN-0159's rule (actual months only), does the Nov 13 part-month actual feed the average?

### 5. SCN-0159 (b), SCN-0160 (b): catch-up readings would trip the high-usage check, and neither scenario says so. **Should-fix**

- **SCN-0159.** December's catch-up is 7.1 Mcf against BB-25's 2.3 average, about 309%.
- **SCN-0160.** December is 8.0 against 4.0, which is 200%. Per month since the last actual (12.0 over two months) it is exactly 150%, the threshold, which the platform flags only when exceeded (SCN-0139).
- **Fix.** SCN-0156 says the check compares usage per month covered. Say the same for a catch-up after estimates, either "per month since the last actual reading" or "against the estimated months' totals", and state which history Bluebonnet compares with. Otherwise a C# test can't tell whether the December bill is held.

### 6. SCN-0155 (b), line 543: "refunded with the deposit's remainder" doesn't work. **Should-fix**

The deposit's remainder ($118.89) was already refunded at (a) on Dec 11. Say: "the deposit is applied again to the corrected $27.52, and a further $3.59 is refunded, recorded as deposit," as SCN-0162 (a) does.

### 7. SCN-0155 Given (line 537): the status of BB-22's Dec 2 bill (for November's gas) is unstated. **Should-fix**

Bluebonnet's route (b) applies the deposit "to what is owed". If the Dec 2 bill (due Thu Dec 17) is unpaid on Dec 11, the deposit pays it too, and $118.89 is wrong. State it as paid, as SCN-0162 does for PF-08.

### 8. SCN-0155 (b): how the corrected boundary is recorded is not said. **Should-fix**

After the share by days, BB-22's final rests on 4,102.6 (4,100.0 + 2.6), not the estimated 4,103.0. Say whether the core records a replacement final reading of 4,102.6, and with which reason from Kyle's list ("estimate replaced by an actual" is for an estimate not yet billed, per SCN-0141). The alternative is that the share is a billing computation with no new reading. A test needs one or the other.

### 9. SCN-0155 (a): spreading the monthly average by days is the stream's reading. **Should-fix**

Bluebonnet's method is the "average over its last three billed months". Taking 10/31 of it for a part-month final reading is an extension of the method, not the method itself. Label it as the stream's reading, and say the same rounding to the meter's tenth applies.

### 10. Cast §6, "Estimates" (cast.md, §6), against SCN-0159's rule: the method's wording now conflicts. **Should-fix**

- **The conflict.** The cast says the estimate is "the customer's average usage over its last three billed months". Read literally, an estimated month is a billed month, which is the alternative SCN-0159 rejects.
- **Fix.** Reword the cast as "its last three months billed on actual readings (SCN-0159)". SCN-0155 (line 537) and SCN-0141 use the same "last three billed months" wording; align them.
- **Something the core shouldn't reuse.** The only built three-month average is a per-meter dashboard summary (`tu.sql:4810–4826`, comment at 21577). It averages estimated readings with actual ones and leaves out boundary readings. It isn't the estimator, but the scenario's "Not built: which months the average reads" could say so.

### 11. SCN-0158 against SCN-0142's Open (2) and batch 7, question 6: the run half is now settled by built behaviour, but the other two still ask it. **Should-fix**

- **The overlap.** SCN-0158 states as built that a validated customer reading ends the run. SCN-0142's Open (line 302) and Kyle's batch 7 question 6 (`application/kyle-brief-2026-11-25-scenario-batch-7.md:26`) still ask "does it end the run of estimates?". By Ryan's standing rule (built behaviour), that half is settled. Only "does it count as Texas's six-month actual reading" is Kyle's.
- **Fix.** Mark SCN-0142's Open (2) accordingly. If Kyle answers the run half differently, the built rule changes; note that.
- **A precision point.** "As built" holds because the run counts any validated reading not marked estimated, whatever its method (`tu.sql:16903–16910`). The schema doesn't stop a customer reading from being entered as an estimate, so it is the core that enters the card as not estimated.

### 12. SCN-0162 (b), line 671–672: Kyle's answer 1 bears on the penalty, and the Then states the penalty as fact. **Should-fix**

- **Answer 1.** Kyle 11-05, answer 1 (`gas-billing-memory/application/kyle-decisions-2026-11-05-scenario-batch-2.md`, table row 1): after a misread is voided and rebilled, a penalty is reassessed "only on the lower of the original (wrong) bill and the corrected bill … not on money our error hid." The $81.54 is exactly that hidden money. Answer 2 then gives it the next regular bill's due date.
- **Fix.** Cite answer 1 beside answer 2 in the Open. Mark the $8.15 as provisional, pending the Open.
- **Backbilling.** Add that the $81.54 undercharge passes under Pecan Flat's six-month default for a silent city (answer 10, counted from discovery on Dec 9) with the cause "keying error", as SCN-0132 does for Bluebonnet.
- **Collections.** "The debt goes to collections" is the stream's reading: collections isn't built or ruled. Say so.

### 13. SCN-0162 (a), line 670: refunding the payment that is no longer needed answers, for a closed account, the question `cash.md` SCN-0089 leaves open. **Should-fix**

Cite SCN-0089. A refund is never held back, and there is no account to hold a credit, so this case is settled by rule. Say so, so the two scenarios don't read as conflicting.

### 14. SCN-0161 Rule (line 647): "the meter's history at that address" is ambiguous when the meter has been swapped. **Should-fix**

- **The ambiguity.** SCN-0145 keeps a meter's history with the meter and each house's readings with the house. Gulf Plains' "same month last year" should read the house's readings, whichever meter took them (Kyle 08-18, D-3, requirement (4): a read history for the premise across meter swaps).
- **Fix.** Say "the readings taken at the address, across meters".
- **Status.** Add to Not built: a read history for the premise across meter swaps is a net-new item in GBM (`kyle-decisions-2026-08-18-coda-items.md:245`, item A11).

### 15. SCN-0157 Rule (line 573): "A downward correction keeps the original due date" has no source. **Nit**

Kyle 11-05, answer 2 says it: the amount the customer already knew about keeps the original due date. Add it to Sources.

### 16. Cast gaps. **Nit**

- §6 "Part-month customer charges" names only Bluebonnet. SCN-0161 prorates Gulf Plains' charge by days, so add "Gulf Plains: the platform default, until its tariff is drafted".
- §6 "Billing days" names BB-17 as read on the month's last day. Add BB-22 and BB-23; BB-23's row doesn't say when it is read.

### 17. SCN-0161 (b): GP-11's Mar 1 reading and March bill are not given. **Nit**

That leaves the April estimated reading's value unknown. Give the Mar 1 actual.

### 18. SCN-0155 (b): the tax year of the corrected final bill. **Nit**

"Its taxes are 2026's" is said only of BB-23. The correction issued Jan 4, 2027 is also on a 2026 period, so it carries no crime-control district tax. Say it for the corrected final as well.

### 19. SCN-0159: rounding an average to the meter's tenth is used but not stated. **Nit**

2.4667 rounds to 2.5. Say "an estimate is rounded half-up to the meter's tenth".

### 20. SCN-0162 (b): Jan 1, 2027 is New Year's Day. **Nit**

Pecan Flat's tariff doesn't move a holiday due date, and SCN-0131 keeps Jan 1. A one-clause note ("the tariff doesn't move it") would stop a tester asking.

## Built / not built: checked

- SCN-0157, 0159 (method list `tu.sql:4211`, 14877; cap AC-21), 0161 (method list; part-month setting `tu.sql:514`) and 0162: accurate.
- SCN-0158 is accurate, with the precision in finding 11.
- SCN-0155, 0156 and 0160 are wrong (findings 1–3).

## Rulings cited: checked

- Accurate: the final-bill workflow's exception 1 and the named failure "estimated final bill never reissued when actual differs" (GBM `final-bill-generation.md:41`; `24-billing-failures-index.md:195`).
- Kyle 10-14, answer 6, "rebills use the factor in effect at the time": verbatim (`kyle-decisions-2026-10-14-…:37`).
- Kyle 10-15, R-10 and R-11: accurate. Kyle 08-18, D-3: accurate.
- Kyle 11-05, answers 2 and 13: accurate. Answer 1 is missing in SCN-0162 (finding 12).
- Batch 7, question 6: accurate.
- Law: SCN-0158's §7.45(6)(C) (the card in the second straight month without access) is correct. No other new scenario states §7.45 or §7.5519.

## Opens and "Settled by rule"

- **SCN-0155's Open is properly Kyle's.** It decides which of two customers pays for the estimate's error, which is where money ends up.
- **SCN-0162's Open is properly Kyle's.** It sets a penalty and due date against Kyle's answers 1 and 2, which is a rule conflict.
- **The "Settled by rule" items are properly settled.** These are SCN-0156, 0159, 0160 and 0161. None is a where-money-ends-up question: in SCN-0159 the two defaults differ by only the figure months ($188.40 against $188.32 in all).
- **SCN-0158's run half is settled by built behaviour** (finding 11).

## Gaps (within the cast)

1. **The minimum bill with tax** (round 8, Fable's gap 6) is still not covered. Pecan Flat's café PF-03 below $20.00 would show whether the minimum is compared before or after tax (SCN-0135's note on CI-103).
2. **An estimated final reading that undercharged the departing customer.** This is SCN-0155 reversed, where the share by days exceeds the estimate. It joins SCN-0155 to SCN-0162 (b)'s Open (due date and penalty for a departed customer).
3. **A returned self-read card that fails validation, or reads below the estimated reading.** It joins SCN-0158 to SCN-0141 (b′) (a credit) and SCN-0139 (a re-read).
4. **A Gulf Plains estimated final bill.** There §7.45 binds the estimated-bill marking, and a departed customer can't be cut off, so (4)(E)(vii) has nothing to bar.

## Plain language

No table or column names appear in SCN-0155 – 0162. The invariant and contract codes appear only as pointers.
