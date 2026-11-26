# Review (Fable): gas cost, zones and factors, meter reads, the added cases (SCN-0146 – 0154), round 8

Scope: `scenarios/gas-cost-zones-and-reads.md` lines 354 – 509, `cast.md` §6 and rows BB-20, BB-21, GP-09, and questions 17 – 22 of `application/kyle-brief-2026-11-25-scenario-batch-7.md`. Read-only; no repository file was changed. "TU" is this repo, "GBM" is `~/code/gas-billing-memory`.

## What checked out

- **Arithmetic.** Every dollar figure and volume in SCN-0146 – 0154 was recomputed (four-decimal working figures, half-up per line, tax on the sum of the rounded lines). All agree: SCN-0146 $34.47 and $25.71; SCN-0147 $253.60; SCN-0148 7.8 Mcf and $73.50; SCN-0149 $36.75 and $38.20; SCN-0150 37.2320 Mcf and $421.16; SCN-0153 $352.38, $362.94 and $10.56; SCN-0154 43.6800 Mcf and $472.71. The one figure I think is incomplete is SCN-0152 (b), finding 1.
- **Weekdays and day counts.** Dec 2 (Wed), Dec 10 (Thu), Dec 11 (Fri), Dec 20 (Sun), Jan 4, 2027 (Mon), Jan 8, 2027 (Fri), Mar 1, 2027 (Mon), Sep 9 and 10, 2027 (Thu, Fri), Sep 30, 2027 (Thu), Oct 5, 2027 (Tue), Oct 8, 2027 (Fri) are all right. Nov 20 – Dec 14 is 25 days; Dec 15 to Jan 8 is 24 days and Jan 8 – 14 is 7, which add to the 31-day period.
- **Law.** Read today on Cornell LII. §7.45(6)(C), (6)(B)(v), (6)(B)(viii) and (4)(E)(vii) say what the scenarios say; the scope (residential and small commercial, unincorporated areas) is right; the last amendment is July 12, 2004. §7.5519 has no effective-date, filing-date or carry-forward rule ("The Commission shall determine in each case the necessary reporting, filing, and other procedures"), as `cast.md` §6 and the brief's opening say. Two parts of the rule the added cases do not use are in findings 5 and 6.
- **Rulings quoted correctly.** Kyle 09-02 R-21 (catch-up "uncapped"; "on its face evidence the utility breached (6)(C)"), GBM `kyle-decisions-2026-09-02-a2-backbilling-caps.md:123-133`. Kyle 11-05 answer 13 (a reader's report "is a lead, not a finding"; supervisor approval with the estimate basis), `kyle-decisions-2026-11-05-scenario-batch-2.md:36`. Kyle 07-10 D3A-2 (150% and 10% of class average as starting settings), `wu5-wu6-kyle-decisions-2026-07-10.md:120`. Kyle 10-15 K-06 (four decimals, half-up), `kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md:54`. Kyle 09-23 "a correct reading converted wrong", `kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md:323`.
- **Built claims that hold.** The cap on estimates in a row fires on the estimate that would reach the cap and is resolved only by an override or a field order (TU `application/APPLICATION-CONTRACTS.md:228-234`). A meter is base or elevated pressure, and nothing stops a factor other than 1.0000 on a base-pressure meter (parity record, CI-029 line 338: "Core must apply Fp=1.0 … and reject at pre-mail review"). The six-month check is the core's (CI-090 line 399). Texas's row for a catch-up after estimates is uncapped (`sql/tu.sql:24366`).
- **Plain language.** No table or column names in the nine scenarios.

## Findings

### Blocking (a wrong figure or a wrong claim)

**1. SCN-0152 (b), line 478: PF-04's bill is not $20.00; PF-04 is a taxed customer.**
The scenario bills the empty weekly rental "zero usage, raised to the **$20.00** minimum". PF-04 is the cast's example of gas that is *not* residential: `cast.md:159` ("taxed: not residential use") and `tax.md:226-238` (SCN-0111 (c): state 6.25% and Pecan Flat's 1.5% on its bill). Being empty does not change how the premise's use is recorded. So one of two results applies, and neither is a bare $20.00:
- as the schema is built (the minimum compared with the subtotal before tax, SCN-0135's Status, line 132): minimum bill adjustment $20.00, state tax $1.25, city tax $0.30, total **$21.55**, if the adjustment line is flagged taxable ("every gas line is flagged taxable", `tax.md:225`);
- as the invariant reads (the floor checked after taxes, GBM `canonical-invariants.md:1798`): total $20.00 with the tax inside it.
This is exactly the case SCN-0135 says "does not show here" (line 149), so it is worth keeping, but worked both ways with the expected one named and the taxability of the adjustment line added to the Open for the rates stream. If the tax question is unwanted here, use a residential customer (PF-02, as SCN-0135 does). PF-03 in (a) is taxed too; that matters once (a) has a figure (finding 8).

**2. SCN-0147 Status, line 386: "nothing records it today" is wrong; the choice not to estimate is built in three places.**
- A rate schedule carries a yes/no setting for whether system estimates are allowed (`sql/tu.sql:14855`).
- A meter can be blocked from estimation, with a required reason, who and when (`sql/tu.sql:3711-3714`, enforced at lines 214-227).
- The utility's settings hold a switch for estimation as a whole (`sql/tu.sql:4649-4650`).
- The billing run already records the outcome "skipped, no read" for a meter (`sql/tu.sql:2301`), and the read checks include a rule for a gap between reading dates (`sql/tu.sql:17095`).
What is *not* built is a dated, per-month record of "this route was skipped and why". Fix the Status to say which exists and which does not. The same scenario has three rule problems in finding 4.

### Should-fix

**3. SCN-0146, lines 358, 368 – 380, and question 17: the customer charge on a part-month bill is already a built setting with a platform default, and the default is the opposite of the expected result.**
The schema has a setting, per utility with a per-schedule override, for a fixed charge when a customer changes partway through a period. Its three values are: share by days (days covered over days in the period), both customers pay in full, or whoever holds the account at the period's end pays in full. The utility default is share by days (`sql/tu.sql:4605`, `4624`; the override and its description at `4207`, `4277`: "Most utilities use prorated"; the line records which was applied, `3302-3337`). The invariant on the customer charge says it is "prorated only by the schedule's proration rule for a partial period" (GBM `canonical-invariants.md:1782`), and the parity record expects "the prorated final bill" at a move-out (CI-122, line 431).
- The Status says only "Not built (as SCN-0130)". It should say this setting is built and that the scenario's expected result is its "both pay in full" value.
- Kyle's standing rule is that the platform default applies where the tariff is silent (GBM `kyle-decisions-2026-11-03-scenario-batch-1.md:9`). Bluebonnet's "the customer charge, every month, even while service is off for the summer" speaks to a customer with service all month, not to a part month. If that is silence, the default gives **$25.71**, not $34.47. The scenario should state Bluebonnet's setting as an invented cast fact (`cast.md` §2) rather than as a reading of the tariff, and name the third value (BB-20 alone pays December's charge) as not expected.
- Question 17 should tell Kyle the platform's default is a share by days and ask whether "every month" overrides it. It asks about the final bill only; the scenario's Open also asks about a first bill.
- This also reaches BB-18's first bill, finding 9.

**4. SCN-0147, lines 387 – 398: three things stated as the rule are the author's reading, and one invariant points the other way.**
- *"No bill is issued that month."* The customer-charge invariant says an active customer "with zero usage still produces a bill carrying the customer charge", and the parity record says the core "must not let" a no-read skip drop it (CI-102, line 411; GBM `canonical-invariants.md:1782`). Pecan Flat has no customer charge, which is why the scenario gets away with it, but the Rule is written for any utility. At Bluebonnet a skipped month would still owe $12.80. Scope the Rule to a utility with no fixed monthly charge, or say what happens to the fixed charge and the $20.00 minimum for the skipped month.
- *"The minimum bill counts once per month covered"* ($40.00). Nothing cited says so; the tariff says "$20.00 a month". As built, the minimum is one amount per bill (SCN-0135's Status), so a $40.00 floor has nowhere to live. Mark it as this stream's reading, add it to the Open and to question 18, and add a case where it bites (two months, 3.0 Mcf: $47.55 against $40.00 passes; 2.0 Mcf at $31.70 does not).
- *The high-read check.* 16.0 Mcf on one read is over 150% of PF-01's same month last year (7.6 Mcf, SCN-0139 line 238: the limit is 11.4), and the built checks include a gap between reading dates. The scenario should say the read is flagged and cleared with the two-month reason, or that the check compares per month covered. As written a test cannot tell whether the bill issues on Dec 20 or waits.
- The Sources line cites Kyle 11-03 answer 1 for "never split". That answer covers a figure inside one billing month; it does not say a two-month bill takes the later figure. The Status should call the result this stream's reading (the Open already asks).

**5. SCN-0148, lines 404 – 414: the hold is the author's reading and runs against two parts of the Texas rule the scenario does not mention.**
- §7.45(6)(A): "Bills for gas service shall be rendered monthly". Holding the September bill until an actual reading breaches that while curing nothing: the six months were passed on Sep 1 whether or not a bill goes out. Kyle's R-21 says the platform "should surface that, not quietly bound it". The Status should say that refusing a further estimate is this stream's reading (the Open and question 19 ask, but the Rule line states it as settled), and question 19 should mention the monthly-billing duty.
- §7.45(6)(C) requires a card to the customer in the second straight month without access and, by its wording, in the months after. The Given says nothing about cards for GP-09 over five months. State that cards went from May and none came back, or say the gate keeps the customer from the meter too. Otherwise the breach in (a) is partly the utility's own omission, and the scenario cannot be separated from SCN-0142's open question on a returned card.
- (b) says the catch-up "is ordinary billing, not a backbill, so no limit applies". The Texas rows hold "catch-up after estimates" as a named cause: allowed, no limit, and able to ground a cut-off only on the condition that the missed reads were beyond the utility's control (`sql/tu.sql:23905`, `24366`). A test needs to know whether the September bill records that cause and whether, with a locked gate, it can ground a cut-off. Say so in the Then.
- GP-09's five estimates (9.0, 7.2, 4.8, 3.1, 2.6) are GP-08's figures from SCN-0142 plus one. Say they are GP-09's own use in the same months of 2026 (Gulf Plains' method, `cast.md:136`).

**6. SCN-0149, lines 420 – 430: Kyle's ruling on a missed figure is not cited, and nothing says how a carried figure becomes locked.**
- Kyle 07-10, T-1: a bill issued on a "stale/missed factor load — a superseded rate was applied" is cancelled and rebilled (GBM `wu5-wu6-kyle-decisions-2026-07-10.md:22-24`; SCN-0132 cites it). SCN-0149 (b) says October's bills are not rebilled. The two fit only because the tariff term makes the carried figure the right one, so no superseded figure was applied. Cite T-1 in Sources and say why it does not reach this case; otherwise the scenario reads as contradicting SCN-0132.
- "A carried figure is the month's locked figure": who locks it and when? SCN-0131 makes a lock a supervisor's approval. Here the Given has no approval and the bills go out Oct 5. A test needs the event: locked by the system when the filing deadline passes, or by a supervisor confirming that nothing was filed. Pick one and mark it this stream's reading.
- SCN-0131's Rule ("The run never falls back to the previous month's figure", line 50) and its title are written for every utility. Add "unless the utility's tariff carries the figure forward (SCN-0149)" there, or the two rules conflict on their faces.
- Nit in the same scenario: for a regulated utility the term comes from the Commission's order in its rate case (§7.5519(c)), so "the utility's tariff term" should read "its approved tariff's term".

**7. SCN-0150, lines 436 – 447: two "the core's" items need somewhere to be stored, and the built fallback is not mentioned.**
- The Rule says the core "does not fall back to another method on its own". As built, a schedule with no method set falls back to a platform default by service (gas: the same month last year; `sql/tu.sql:4263`, `4653`). That is a different situation (no method chosen, rather than a method that cannot run), but the scenario should say so, since a builder will find the fallback.
- The built list of estimate methods is fixed: three-month average, twelve-month average, same month last year, last actual reading, zero (`sql/tu.sql:14877`). "Set by a supervisor, with its basis" is not among them, and I found no field for an estimate's basis or its approver. A record cannot be "the core's"; the Status should say the supervisor's basis and approval are not built (a note for the rates stream).
- The built list of reasons for an estimate has no "meter destroyed" (`sql/tu.sql:3578`); the nearest are "meter malfunction" and "other". Say which the scenario expects.
- The Sources line already says answer 13 is used by analogy. Good.

**8. SCN-0152, lines 469 – 478: (a) cannot be built as a test, and its rule is attributed to the wrong place.**
- (a) has no quantity and no dollar figure. "The December bill is issued on that estimate" does not say what the estimate is (Pecan Flat's three-month average? November's 1.9 Mcf?).
- The gas since Nov 15 has never been billed, so this is December's own bill, estimated because the meter failed. It is not a correction of an earlier bill, and no backbilling limit comes into play. Yet the scenario calls it a backbill "under Pecan Flat's backbilling rule: a known stoppage under three months charges only that period". That sentence is Kyle's answer 13 on Texas's three-month rule for regulated utilities (§7.45(7)(B)(v)(II), SCN-0035 line 197). Pecan Flat is a city with no backbilling rule; its limit is the six-month default (SCN-0019). Say plainly: an estimated December bill, reason "meter malfunction", a supervisor's approval with the basis; and keep the backbill for a case where a zero month was already billed.
- "Under 10% of the class average": Pecan Flat has one class (`cast.md:17`), so a café is measured against homes. As built, the low-usage setting is a fraction of the customer's own history (default 25%), and a zero reading on an active account is a separate check (`sql/tu.sql:4664-4668`, `17095`). The Status should note that the built setting differs from Kyle's 10% of class average, and the Given should give the average used.
- (b) "reads 1,312 Ccf both times" leaves out Nov 15. If November also read 1,312, November's bill was the first zero and this is the second; say which bill is under test and what happened to the first.
- Neither part has a question for Kyle, though both the three-month rule at a city and the class average at a one-class city are unruled. Add one to the brief.

**9. SCN-0153 (b), lines 487 and 493 (and SCN-0150): BB-18's first bill is priced with a full customer charge, which SCN-0136 deliberately left open.**
SCN-0136 (b) says the first bill's amount "is not under test here: whether a first partial month's customer charge is prorated is not stated" (line 167). SCN-0153 then states that bill as $352.38 and $362.94, both with the full $82.90 for a 25-day first period. With the platform's default share by days (finding 3; 25 of the 30 days in Nov 15 – Dec 14, $69.08) they would be $337.63 and $348.19. The difference, **$10.56**, is the same either way, so the figure under test survives; say that, and say the two totals assume the full charge pending SCN-0146's Open.
Also in this scenario:
- The Status omits two things SCN-0138's Status states for the same kind of error: the cause "billing constant error" exists only in the Texas rows, which bind regulated utilities and where it is a placeholder (`sql/tu.sql:31364`), and how the correction reaches the customer (void and rebill, or a line on the next bill) is unruled (SCN-0138 Open 1). SCN-0153 presents both as settled.
- (b) says the meter "was confirmed in the Standard zone at activation by mistake", but a zone belongs to the premise and the meter is confirmed against it (`cast.md:134`, SCN-0136). Was the premise put in the wrong zone, or was the meter confirmed against a zone the premise is not in? In the second case the activation check should have caught it. A test needs to know which record was wrong.

**10. SCN-0154, lines 499 – 509: the case does not test what it was added for.**
The round 7 gap asked for "the order, and four-decimal rounding of the chain". With an index to a tenth, a multiplier of 10 and a factor of 1.0400, no working figure ever has more than three decimals, and as the last bullet admits, the order changes nothing. So the only thing a test can assert is what the line displays. Two fixes:
- Use figures that go past four decimals, for example an index difference of 4.27 and a factor of 1.0437: 42.7 × 1.0437 = 44.56599, carried as 44.5660.
- Say whether the billed volume is itself rounded to four decimals before it is priced. The Rule says figures "are rounded only on each line's dollar amount"; Kyle's K-06 says "intermediate math carry four decimals". Those are different instructions once a fifth decimal exists.

**11. SCN-0151, lines 453 – 463: the When and Then leave the test's path open, and the cut-off side is not built.**
- "A supervisor resolves it by an override or a field order" is two outcomes. Non-payment of the February bill follows only from the override (with a field order the bill waits, as in SCN-0142 (d)). Pick the override.
- No figures. This is the only place a second estimate in a row under the three-month average appears, and it does not say whether December's estimated month counts in January's average. Give BB-02's history (6.6 Mcf, SCN-0141) and the January figure, or state the rule.
- "Nothing bars a cut-off" is a statement about rules that do not exist yet: the cut-off check belongs to the collections patch, which is not mirrored (SCN-0142's Status says so; SCN-0151's does not).

**12. SCN-0146 (a) and (b), lines 361 – 378: one day counted twice, and (b) has nothing to assert.**
- BB-17's final bill covers Dec 1 – 10 (10 of 31) and BB-20's first covers "Dec 10 – 31" (22 days). That is 32 days of December. Under a share by days the two charges would add to more than one month. Say who holds Dec 10.
- (b) gives no volume, so the only testable claim is "uses $0.71". It declines to work the bill because "its taxes depend on the tax family's rule". But this family's own header says a bill reads everything at the period's last day (line 7), which is Dec 31, 2026, and SCN-0138 states flatly that bills for 2026 periods "carry 2026's taxes … though they are issued in 2027" (line 223). Either work (b) at the 1% city tax, or soften SCN-0138 to match. They should not differ.

**13. Kyle brief, questions 17 – 22.**
- Q17: finding 3.
- Q18: add the minimum for the skipped month ($20.00 or $40.00), and what a city with a monthly customer charge bills in a month with no read (finding 4).
- Q19: add that holding the bill sets the six-month duty against the monthly-billing duty (finding 5).
- Q20 asks Kyle what Texas tariffs "usually" say; note that the term itself is invented for Gulf Plains so he does not read it as taken from a filed tariff. The Figures line (Q23) lists "Gulf Plains' rates and factor timing"; add the carry-forward term.
- Missing: the two unruled points in SCN-0152 (finding 8).
- The count ("23 questions") and the SCN numbers on Q17 – 22 are right.

### Nits

14. SCN-0153 (b) line 493 (and SCN-0138 line 222): "the next bill, Jan 16". Jan 16, 2027 is a Saturday. Weekend bill dates are used elsewhere with the weekday given (Sun Dec 20); give it here.
15. Family header, line 11: "New customers: BB-17, BB-18, BB-19, GP-08" leaves out BB-20, BB-21 and GP-09.
16. `cast.md:138` (Meters): BB-19's multiplier is described, BB-21's is only in its customer row. BB-19's and BB-21's indexes are shown to a tenth (3.1, 4.2) on meters reading in units of 10 Mcf (round 7's nit 30, repeated in SCN-0154).
17. `cast.md:136`: "(the platform default; …)" follows both the three-month average and the cap. The cap of 3 is the platform default; for gas the built default method is the same month last year (`sql/tu.sql:4653`). Move the parenthesis to the cap.
18. SCN-0146 line 361: "Its November bill was issued Wed Dec 2". The header names things by billing month, so this is BB-17's December bill for November's gas.
19. SCN-0147 line 389: PF-01's Dec 15 reading, 1,204.0, is the same number SCN-0139 gives as PF-01's Nov 15 reading. Each scenario stands alone, but a different number avoids a reader reconciling them. The same goes for BB-02's locked gate on Dec 15 in SCN-0141 and SCN-0151, and GP-08 in SCN-0142 and SCN-0149.
20. SCN-0150: no issue date for the January bill; say Jan 16 (Sat) or the next workday.
21. SCN-0154 Status (and SCN-0143): "are columns" is schema talk without a name; "are recorded on the meter" is plainer.

## Gaps (within the cast)

1. **A skipped month at a utility with a fixed monthly charge** (Bluebonnet): finding 4.
2. **A self-read card that comes back.** SCN-0142 and SCN-0148 both end with no card returned; the customer reading, whether it ends the run of estimates and whether it counts as Texas's actual reading are only an Open.
3. **A second and third estimate under the three-month average**, with figures (finding 11): does an estimated month feed the next estimate?
4. **An actual reading dated before estimates already entered** (round 7's gap 11): still only an Open, though the built rule is definite (a back-dated actual does not clear the run, `APPLICATION-CONTRACTS.md:234`).
5. **A new customer at Gulf Plains with no "same month last year"**: SCN-0150 covers the missing-history case for Bluebonnet's method only.
6. **The minimum bill with tax** (finding 1) and **a first bill worked in dollars** (SCN-0146 (b), finding 12).
7. **A correction of a final bill** in a later billing month: which gas cost figure, when the customer has left (SCN-0133's rule, on SCN-0146's facts).
