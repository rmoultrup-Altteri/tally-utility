# Review, round 10: gas cost, zones and reads, SCN-0163 – 0168 (Opus, 2026-11-26)

Scope: `scenarios/gas-cost-zones-and-reads.md` lines 682–795 (the section "Added cases (2026-11-26, round 9's gaps)") and the cast rows PF-09, PF-10, BB-27, BB-28, GP-12, GP-13 (`scenarios/cast.md` lines 187–192). This was a read-only review. I wrote no repo file other than this report.

Counts: 1 blocking, 11 should-fix, 7 nits, 4 gaps.

## What checks out

- **Arithmetic.** I recomputed every figure with decimal half-up rounding. All of them are right: SCN-0163 $21.55 and $20.00 (the tax in (b) is $0.89 and $0.21 on $14.27); SCN-0164 $6.67, $93.33, $15.47 and $13.33; SCN-0165 $69.00 and $68.25; SCN-0166 $51.47, $33.43, $52.11, $28.53 and $22.94; SCN-0167 $25.71, $224.29, $20.33, $5.38, $229.67, $15.85, $9.86 and $234.15, plus the shares 2.3871, 1.7742 and 1.3187; SCN-0168 $15.50, $2.01, $14.00, $1.50, $28.75, $20.00, $4.50 and $40.00.
- **Day counts.** 30, 10 and 20 days (SCN-0164), 29 days (SCN-0166), 91 days (SCN-0167) and 147 days (SCN-0168) are right.
- **Weekdays.** Every weekday named is right: Sun Dec 20, Wed Nov 25, Thu Nov 26, Fri Jan 1 2027, Mon May 3, Tue May 4, Fri Nov 13, Fri Nov 20, Wed Dec 16, Mon Dec 28, Mon Jan 4, Mon Mar 1, Tue Mar 2, Fri Jan 15, Thu Jun 10, Fri Jun 11, Thu Jul 1, Mon Jul 5, Tue Jul 6 and Mon Jul 26, 2027.
- **Law.** Each quotation matches the rule text in `application/wave3-build-2026-10-18/sources/law-text/tac7-45.txt`:
  - (5)(F)(i): "promptly and automatically refund the customer's deposit plus accrued interest on the balance, if any, in excess of the unpaid bills".
  - (5)(C)(iv)(II): "cease to draw interest on the date it is returned or credited".
  - (6)(B)(viii): "a distinct marking to identify an estimated bill".
  - (6)(C): the six months, the postcard, and "the utility may estimate the meter reading and render the bill accordingly".
  - (4)(E)(vii): the bar on cutting off for an estimated bill.
  - The scope (residential and small commercial, unincorporated areas) is right.
  - "§7.45 says nothing of final readings or final bills of their own" is right: the only uses of "final" in the rule are about complaints.
  - SCN-0168's 147 days is past the rule's 30 days, so interest is owed.
- **Rulings cited.**
  - Kyle 11-03: the standing rule (the platform default only where the tariff is silent) and answer 17 (a credit left after a deposit-paid final bill is a deposit refund) say what the scenarios claim.
  - CI-103's text (GBM `application/canonical-invariants.md:1800`) does put the floor "after the full charge stack (including … taxes)", as SCN-0163 (b) says.
  - The board's note to rates of 2026-11-25, item 3, exists (`HANDOFF.md:110`).
- **Built claims I confirmed** in `sql/tu.sql`:
  - The part-month setting has three values: a share by days, both pay in full, and whoever holds the account at the period's end. It is per utility with a per-schedule override, and each line records the value applied (lines 3302–3337 and 4277). It covers fixed charges only (4249).
  - "Customer reported" is a reading method, and "final read" is a reading purpose (3581–3582).
  - The streak resets only at a reading that reaches approval (16863).
  - The Texas law rows have the cause "catch-up after estimates", with no limit (23905, 24366).
  - A deposit's interest period never spans a principal application and never runs past the return date (18180).
- **Provisional result of SCN-0166.** It agrees with SCN-0160 (a back-dated actual is kept, reviewed, and doesn't reopen the bill or end the run) and with SCN-0141 (catch-up from the billed estimated reading; no credit line is needed because 706.0 > 704.0).
- **Cast.** The new rows don't conflict with any earlier customer. BB-27's $250 matches the renter deposit and GP-12's 2.5% matches `deposits.md` SCN-0043.

## Findings

### 1. SCN-0163, Status (line 686) and "Settled by rule" (line 707): "compared with the bill's subtotal before tax" is not in the schema. **Blocking (wrong claim)**

The only written statement that the minimum is compared before tax was the comment on the minimum-bill column of the rate schedule header: "if the meter's service-type subtotal (excluding tax) is below this amount" (`sql/tu.sql:4291`). Patch v5.4.2-03 moved the column to the dated schedule versions and dropped it from the header (`sql/tu.sql:14985`). That took the comment with it. The column on the versions carries no comment, and nothing in the schema compares a minimum with anything.

What is built is narrower:
- an amount of zero or more on each dated version of the schedule (14860, 14879);
- a line kind for the adjustment (3313);
- issued lines that can't be changed.

Before or after tax is wholly the core's job. "The built check" in the Settled line rests on the same comment.

Fix:
- Status: "Built: the minimum is one amount on each dated rate schedule version, and the adjustment is a line of its own. Not built: whether the floor is checked before or after tax is the core's. The only written statement, before tax, was a column comment dropped in -03."
- Settled line: drop "the built check" and rest it on following the tariff.
- SCN-0135's Status (line 132) makes the same claim and needs the same fix.

### 2. SCN-0163, Given (line 690): a café shut from Nov 20 can't show 0.9 Mcf for the period. **Should-fix**

The period runs Nov 16 – Dec 15. At "about 30 Mcf" a month, the café uses about 1 Mcf a day, so Nov 16 – 19 alone would be about 4 Mcf. The clerk's clearance ("citing the café's closure notice") is then clearing a reading the notice doesn't explain. A test written from this Given would encode an implausible clearance.

Fix: close it from Mon Nov 16 (or Nov 15) to Dec 15, so 0.9 Mcf is pilot and cleaning use. Also give the meter readings in Ccf (PF-03 reads in Ccf, SCN-0152 line 542: for example 2,430 to 2,439), so a test has both readings and not only a volume.

### 3. SCN-0163, "Settled by rule" (line 707): taxing the minimum adjustment is a tax-law question, and it sits inside a Settled line. **Should-fix**

The first half is settled by rule: the floor is before tax, because the tariff's $20.00 is a rate. The second half, that the adjustment is taxed like the gas, is a reading of Texas sales-tax law, and the line itself says it is "to confirm with a tax advisor". Under the standing rule, law is a question to ask, not something to settle. (The reading is probably right, since a minimum charge is part of the price of the gas sold, but it is still a reading.)

Fix: split it out as **Open (tax advisor, before go-live):** "is the minimum-bill adjustment part of the taxable sales price of the gas?" Note the effect: $1.55 on this bill.

### 4. SCN-0164, Rule (line 714) and the cast: the minimum's part-month setting has no home, and it isn't said whether it is the customer-charge setting. **Should-fix**

The rule says the minimum is "shared by days … as the platform default shares a monthly customer charge", and that a utility states otherwise "with the same three choices". It isn't clear whether that is one setting reaching both the customer charge and the minimum, or a second setting for the minimum. `cast.md` §6 records a part-month setting for Bluebonnet and Gulf Plains but none for Pecan Flat, which has no customer charge. The cast's own rule is: "If a scenario needs a fact the cast doesn't have, add it here first."

The third choice also does something worth stating. Under "whoever holds the account at the period's end pays in full", PF-09's final bill carries no minimum at all ($4.53), and PF-10 pays the full $20.00 minimum.

Fix:
- Add to `cast.md` §6: "Part-month minimum: Pecan Flat keeps the platform default, a share by days (**invented**: its setting; SCN-0164)."
- Say in the rule whether it is the same setting.
- Add one line for the third choice ($4.53 and $20.00).

### 5. SCN-0165, Rule (line 732): the law is paraphrased past its words. **Should-fix**

The scenario says "§7.45 lets the utility estimate when no reading it can bill on arrives in time". The rule's words are "If such a postcard is **not received** by the utility in time for billing, the utility may estimate" (`tac7-45.txt`, (6)(C)). Here the card was received in time. The authority to estimate is the earlier sentence of (6)(C): "Where there is good reason for doing so, estimated bills may be submitted, provided that an actual meter reading is taken at least every six months." A card that fails the checks is plausibly a good reason, but that is this stream's reading.

Fix: cite the "good reason" sentence, and mark the step "this stream's reading: a card that fails the checks is treated as no card". The alternative a regulator might expect is contacting the customer before billing, which (c) shows is possible (a phone call on May 4). Since this is a reading of law, consider whether it belongs beside batch 7's question 6 for Kyle, which already asks whether a customer reading counts as Texas's six-month reading.

### 6. SCN-0165 (c) (line 741): the phone reading's date is undefined, and its reason doesn't fit. **Should-fix**

**The date.** The phone reading is taken on Tue May 4 but is said to replace the card's reading of May 1 and to bill "as in SCN-0158 (a)", meaning the period ends May 1. A test needs one of two things:
- The reading is dated May 1, which is a value the customer could not read on May 4, since the meter had moved about 0.5 Mcf in three days.
- The reading is dated May 4. Then May's period ends May 4, June's starts there, and the result is not SCN-0158 (a)'s $68.25. A reading of 1,066.1 on May 4 would also be lower than the true May 1 index, unless use was zero.

**The reason.** The reason is given as "typo correction", but nothing was keyed wrong: the customer misread the dials. From Kyle's list, "re-read for high or low usage" is the trigger that fits.

Fix: say the customer reads the meter again on May 4 and gives 1,066.6, dated May 4, and work May's bill on 7.6 Mcf. Or keep 1,066.1 but date it May 1 as the customer's correction of the card's figure (not a new reading of the meter), with the reason "other: customer's correction of a card". Either way, state the date the test should store.

### 7. SCN-0165, the bullet on resolving the held card (line 742): accepting a held card by override would, as built, end the run of estimates. **Should-fix**

The bullet says the held card "is resolved at review, by an override with a reason or by rejection". But a reading accepted by an operator reaches approval, and approval is what resets the run. The streak's reset reading is one that "passed VEE or operator-accepted, i.e. reached approved" (`sql/tu.sql:16863`). The card is dated May 1, the same day as May's estimate, and SCN-0158 (b) says a same-day estimate beside an actual is not counted. So accepting the card would end the run, which contradicts the rule's "It ends nothing". It would also bill 547.1 Mcf, or a negative usage in (b).

Fix: say the card's reading is rejected, which keeps it in history and keeps it out of billing ("excluded" is a built reading status, `sql/tu.sql:3585`). Then say that accepting it would, as built, end the run (SCN-0158 (b)), which is why the only resolution here is rejection.

### 8. SCN-0166 (a) (line 755): the low check's basis is unstated, and on last year's month the reading fails. **Should-fix**

(a) says 1.5 Mcf passes the low check at "about 40% of BB-28's own monthly average", which is the three-month average of 4.0. But (b) checks against "last year's 6.3", and SCN-0160, its twin, checks against last year's same month (line 629).

On last year's November (6.1), 1.5 Mcf is 24.6%, under the 25% setting, so the read would be flagged low. Scaled to 30 days it is 25.4%, so it passes by a hair. The test's expected result turns on an unstated choice of history and of scaling.

Fix: name one basis for both (a) and (b), consistent with SCN-0160 and SCN-0152's built setting ("a fraction of the customer's own history"). Either change the Nov 13 reading to about 702.0 (2.0 Mcf, 33% of 6.1), or state that the comparison is with the three-month average in both checks.

### 9. SCN-0166, Open (line 762): mostly fair, but it leaves out facts Ryan needs to weigh it. **Should-fix**

The question is real: two standing rules pull opposite ways (catch-up as the platform default where the utility states no method, and "a refund is never held back"), so it isn't settled by either alone. Five things would make the framing fair:

1. **What the cited rule covers.** Kyle 11-03, answer 8 is about how far back a refund reaches when an ordinance is silent: "A missing rule never holds back a refund" (GBM `application/kyle-decisions-2026-11-03-scenario-batch-1.md:22`). It says nothing about timing. Applying it to timing is SCN-0140's own extension (line 262: "this stream's reading"). The Open should say so.
2. **A third option the rulings already contain.** Kyle 11-03, answer 7: for a known keying error, "flag this to the operator and let them choose … catch up on next bill or void/credit and rebill", with the choice recorded and the gas billed exactly once. That fits a known over-estimate too: an operator choice, with a stated default. It is the option most like built practice.
3. **The total cost of each path.** Under the rebill path, December runs from 701.5: 4.5 Mcf at $0.58 is $14.75 + $15.35 + $24.08 + $2.61 = **$56.79**, so the two months come to **$85.32**. Under catch-up they come to **$84.90**: the customer pays $0.42 less, because 2.5 Mcf is billed at November's $0.42 instead of December's $0.58. So in (b) catch-up is only a timing cost: $22.94 held about a month. In (b′) the cost grows. Show both totals.
4. **Whether November is paid.** It is due Tue Dec 1 and unpaid on Nov 20. If it is unpaid, the choice is between asking the customer to pay $51.47 they don't owe and lowering the bill to $28.53. That is a stronger case than a refund, and it sets the base of Bluebonnet's 10% gross-rate penalty if the customer is late.
5. **Which other scenarios the answer reaches.** SCN-0158 (b) (a card 0.1 lower than a billed same-day estimate) is the same case in miniature. SCN-0160 is the mirror image, an under-estimate left to catch up. The "refund never held back" answer makes the rule asymmetric (correct a credit now, catch up a charge later), and that should be said as intended.

The rule as written also doesn't bind Bluebonnet, but §7.45(2)(D)(iv)'s deferred-payment clause counts "an inaccurately estimated bill" as "the utility's error". That is a useful hint at how a regulator sees an over-estimate shown by a reading on file.

Fix: add points 1–5 in two or three sentences, and offer answer 7's operator choice as the third option, with a recommended default.

### 10. SCN-0167, Rule (line 768): gas used while no one holds the account is decided here as billed to no one. That is a where-money-ends-up question, and there is no Open. **Should-fix**

The rule bills "the rest of the window, when no one held the account" to no one, so the utility absorbs it. That decides who pays for 3.7 Mcf in (b) and 10.7 Mcf in (b′).

Batch 8's question (`application/kyle-brief-2026-11-26-scenario-batch-8.md`, question 1) asks only how to share between two customers; it doesn't cover an empty house. Round 9 raised exactly this ("is all the gas the departed customer's?", `review/2026-11-26-gas-3/fable.md`, gap 5).

There are real alternatives, each with its own cost:
- **The departing customer pays until the meter is shut off.** Many tariffs hold the customer responsible until service is actually turned off. In (b) BB-27 would keep all 5.5 Mcf, about $46 instead of $20.33.
- **The owner or landlord pays.** The Given says a landlord exists and opened the yard, and Bluebonnet's tariff has a landlord deposit (`cast.md` §2).
- **The utility absorbs it, as written.** In (b′) sharing by days also moves most of BB-27's own ten days of use onto the empty days, which the last bullet concedes.

Fix: add "**Open (Kyle):** when no one takes service and the meter can't be turned off, who pays for the gas after the move-out: the departing customer until it is off, the owner, or no one, with a report? We'd make it a utility setting, with ___ as the default." Mark the present rule as provisional.

### 11. SCN-0167, Status (line 767): a flag for gas used with no customer is partly built. **Should-fix**

The Status says it is not built. But the anomalies table already has the kind "unbilled usage" (`sql/tu.sql:2151`), tied to a premise and a meter, with the customer optional and an estimated money impact (the table at 2140ff). What is missing is a record of the volume itself, with its window and readings, that the billing-side record and the utility's report could read.

Fix: "Built: a flag of the kind 'unbilled usage' on the premise and meter, with no customer. Not built: a record of the volume and window, and the report."

### 12. SCN-0168, Given and (b) (lines 785, 792): the new customer's bill uses a reading that is made a day later. **Should-fix**

The Given says GP-13's first bill is issued Mon Jul 5 and "the final bill's correction on Tue Jul 6, after the reviewer confirms the shares". But (b) has the Jul 5 bill start "from the replacement reading 3,401.2", and that reading exists only once the shares are confirmed. Either the confirmation (and the replacement reading) comes by Jul 5, or GP-13's bill waits.

Fix: "the reviewer confirms the shares on Mon Jul 5, and the replacement reading is recorded then; GP-13's first bill is issued that day, and the final bill's correction on Tue Jul 6." Or issue both on Jul 5.

### 13. SCN-0163, the low-read bullet (line 696): the read is cleared without the re-read SCN-0152's rule calls for. **Nit**

SCN-0152's rule (line 540) is that "a reading flagged as too low or zero is held and re-read". Clearing the flag on the closure notice is a review resolved by override with a reason (AC-20), which is a fair exception. Say so: "resolved by an override with the notice as its reason, in place of the re-read SCN-0152 would send".

### 14. SCN-0165 (b) (line 740): "a dial misread" changes two digits. **Nit**

1,066.1 → 1,005.1 changes the tens and the units. Write "two dials misread", or use 1,060.1 → 1,000.1.

### 15. SCN-0166, Given (line 751): the pilot relight call carries a fee. **Nit**

Bluebonnet charges $15 for a pilot relight, or $30 after hours (`cast.md` §2). Add "the relight fee is billed separately and is outside this case", so a test doesn't expect it on the November rebill.

### 16. SCN-0168, the cut-off bullet (line 795): "(-26)" is a patch number. **Nit (plain language)**

Write "the collections rules, not built" instead.

### 17. SCN-0168, Given (line 785): Mon Jul 5, 2027 is the observed Independence Day holiday. **Nit**

July 4, 2027 is a Sunday. Gulf Plains bills on the 5th (`cast.md` §3), but the cast doesn't say whether it bills on a holiday. Either say it does, or move the bill to Jul 6.

### 18. SCN-0164 (a) (line 720): the refund's date isn't given. **Nit**

"$93.33 is refunded" has no date, while SCN-0167 and SCN-0168 give one. Give the date, for example "on Thu Nov 26", or say it is refunded with the final bill.

### 19. Outside this section: older Status lines still say "in batch 7 for Kyle (K-20), not yet sent". **Nit**

SCN-0135 (line 132), SCN-0139 – 0143, SCN-0146 – 0148, SCN-0152 and others still say this, but the brief says batches 7 and 8 have been sent. Update them to "sent (date)" at wrap-up.

## Gaps (within the cast)

1. **A card that passes the checks but reads below the billed estimate.** For example, GP-08's card shows 1,057.0 against April's estimated 1,059.0. That is a credit under SCN-0141 (b′), reached from a customer reading. Round 9 asked for it ("or reads below the estimated reading", `review/2026-11-26-gas-3/opus.md`, gap 3), and it is not yet covered.
2. **A customer's corrected reading that arrives after the estimated bill.** This is SCN-0165 (c) with the phone call on May 6. It connects SCN-0165 to SCN-0158 (b) and to the Open in SCN-0166.
3. **An empty-house window where sharing by days undercharges the utility the other way.** For example, a cold month with the house empty and the heating left on, so the shared window bills BB-27 more than its estimate. SCN-0167 shows only credits.
4. **A taxed café's part-month minimum.** This joins SCN-0163 and SCN-0164: a share of the $20.00, then tax on it. It needs the Open in finding 3 settled first.

## Plain language

The scenario text names no table or column. The only patch shorthand is "(-26)" (finding 16). Invariant and contract numbers appear only as pointers.
