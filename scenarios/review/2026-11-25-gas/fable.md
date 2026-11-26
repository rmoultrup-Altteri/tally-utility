# Review (Fable): gas cost, zones and factors, meter reads (SCN-0130 – 0145), round 7

Reviewed 2026-11-25: `scenarios/gas-cost-zones-and-reads.md` (line numbers below are that file's unless a path is given) and `scenarios/cast.md` §6 plus BB-17, BB-18, BB-19, GP-08. Read-only; no repo file edited. I did not read the other reviewers' files in `scenarios/review/2026-11-25-gas/`.

Paths: TU = `/Users/ryanscomputer/code/tally-utility-scenarios`, GBM = `/Users/ryanscomputer/code/gas-billing-memory`.

## What checked out

- **Arithmetic.** Every dollar figure and volume in SCN-0130, 0131, 0132, 0133, 0134, 0135, 0138 (all six bills, the three differences and the $798.41 total), 0139, 0141 (a), (b), (b′), 0142 (a), 0143 and 0144 recomputes exactly (four-decimal working, half-up per line, tax on the sum of rounded lines). SCN-0137's three columns recompute as written, but see findings 1 and 2.
- **Weekdays.** Nov 16 Mon, Nov 30 Mon, Dec 1 Tue, Dec 2 Wed, Dec 4 Fri, Dec 8 Tue, Dec 20 Sun, Dec 22 Tue (2026); Jan 4 Mon, Jan 6 Wed (2027): all correct. Feb 15 – Mar 14, 2027 is 28 days, 14 on each side of Mar 1. Jul 4, 2026 is six months before Jan 4, 2027. Dec 22 to Jan 1 is ten days.
- **Law.** 16 TAC §7.45(6)(C), (6)(B)(viii) and (4)(E)(vii) exist at those cites and say broadly what SCN-0142 claims (text: TU `application/wave3-build-2026-10-18/sources/law-text/tac7-45.txt:470-484`, `:473`, `:309-312`), with the omissions in finding 6. §7.5519 (read on Cornell LII today): (a) lets a utility have a purchased gas adjustment clause, (b) applies it prospectively to rate cases, (c) leaves "reporting, filing, and other procedures" to the Commission in each case. It sets no effective date and no filing deadline, so `cast.md` §6's wording for Gulf Plains is right, and GBM's knowledge page (`knowledge/31-texas-regulatory-compliance.md:115-135`: "last business day", "bills rendered on and after the first day") describes typical tariffs, not the rule.
- **Rulings quoted correctly:** Kyle 10-14 answers 6 and 7; Kyle 11-03 answer 1; Kyle 11-05 answers 10 – 12 and 17; Kyle 07-10 T-1, D3-1, D3A-2 (150%), D3B-1, D3B-2, D11-2, D14-1, "no customer-initiated reads in v1"; Kyle 08-18 D-3, D-5 (the ten reasons match the confirmed list exactly), D-6; Kyle 08-26 R-11; Kyle 09-23 (billing constant error); Kyle 10-15 K-02, K-03, R-10.
- **Plain language.** No table or column name appears in the scenario text; the only code-formatted strings are file names.

## Findings

### Blocking (a wrong figure or a wrong claim)

**1. SCN-0137, lines 178 – 185: the "By cycle" column uses the old factor, which is the opposite of what "by cycle" means in SCN-0001.**
SCN-0001 (Kyle-checked) defines "by cycle" for a period straddling a change as *the whole bill at the new rates*: `scenarios/billing-pipeline-and-charge-composition.md:35-36` ("the whole bill goes at the new rates ... $65.83", the same result as "by read date"). SCN-0137 has the same shape (period Feb 15 – Mar 14, change Mar 1, bill issued in the March cycle) but prices "by cycle" at 1.0400, the old factor (41.6000 Mcf, $450.42). By SCN-0001's meaning it is 40.0 × 1.0600 = 42.4000 Mcf and the same $457.38 as "by read date".
Fix: either make the column 42.4000 / $97.94 / $226.84 / $20.78 / $26.78, $2.14 / $457.38 and say that cycle and read date agree here (as SCN-0001 does), or pick an example where they differ (a read dated before the change on a bill issued after it). If the author means a different "by cycle" (the cycle that opened before the change keeps the old factor), that is a new definition and must be stated and reconciled with SCN-0001.

**2. SCN-0137, line 185: the March 2027 bill leaves out Bluebonnet's pipeline safety fee.**
`cast.md` §2 bills the fee "once a year, $1.00 per service line, on the March bill, not to state agencies", and SCN-0054 (`billing-pipeline-and-charge-composition.md:98`) puts it on every March 2027 bill, outside the tax base. BB-08 is a machine-shop-class commercial customer, not a state agency, and its bill here is issued Mar 16, 2027. Each total is $1.00 short: $454.91 / $458.38 / $451.42 as the columns stand.
Fix: add the $1.00 line (untaxed) to all three totals, or move the example to a month other than March (the factor change could be Apr 1 with no other change), which is cleaner.

**3. SCN-0142, lines 276, 286 – 287: the built cap on estimates fires on the third estimate, not the fourth.**
The Status says the cap is built, and (c) lets a third estimate through with the gate raising only at (d), the fourth. The built gate opens its exception when an estimate *would bring the meter to* the cap: `sql/tu.sql:17294` and `:17363` (`v_count + 1 >= v_cap`), and `application/APPLICATION-CONTRACTS.md:236` ("an estimated ... read that would bring the meter to `max_consecutive_estimates` (default 3) opens a `consecutive_estimate_over_cap` exception; approving that read requires the exception resolved by override or field order"). With Gulf Plains' cap at 3, the Apr 1 estimate (c) is the one that is stopped, so the April bill in (e) exists only after a supervisor's override or a field order.
Fix: either write (c) as the exception (and (e)'s April bill as issued under a recorded override), or set Gulf Plains' cap to 4 if three unchallenged estimates are wanted, or record this as a mismatch for the rates stream. The same reading affects `cast.md` §6 ("at most 3 estimates in a row") for all three utilities: say whether "3" means the third is the last allowed or the third is the one that needs a decision.

**4. SCN-0140, line 245 (c): the request is dated before the read it disputes.**
PF-06 asks on Oct 12 for a re-read that "shows the Oct 15 read was keyed wrong ... on a bill already issued". Oct 15 is three days after the request, and Pecan Flat's bill is not issued until the 20th (`cast.md` §6).
Fix: make the request Oct 22 (a Friday), or dispute the Sep 15 read.

**5. SCN-0144 and SCN-0136, lines 153 and 310: "not built" is wrong for the confirmation records.**
The stamps Kyle's D3B-2 asked for exist: a person-and-time confirmation of a meter's zone and of its pressure class, and a recorded confirmation (who, when, reason) of a pressure-factor mismatch at an installation (`sql/tu.sql:12099-12134`, v5.4.0-05; the parity record's CI-029 row, `application/invariant-parity-measurement-2026-10-13.md:338`, lists the mismatch confirmation as represented). What is not built is the zone model itself and the gate that refuses to bill; the column comments say the gate is application logic (`sql/tu.sql:12119`).
Fix: SCN-0136 Status: "the confirmation stamp is built as one stamp per meter (not one per factor set); the zone model and the hold at billing are not; the hold is the core's". SCN-0144 Status: "the record of a confirmed mismatch is built; the check itself is the core's".

### Should-fix

**6. SCN-0142, line 277 and (e) line 288: two parts of the Texas rule are dropped.**
(a) §7.45(4)(E)(vii) reads "failure to pay an estimated bill *other than a bill rendered pursuant to an approved meter reading plan*, unless the utility is unable to read the meter due to circumstances beyond its control" (`tac7-45.txt:309-312`). The Rule sentence omits the approved-plan exception; Kyle's R-30 keeps it as an open field (GBM `kyle-decisions-2026-09-02-a2-backbilling-caps.md:383`). (b) §7.45(6)(C) requires the card only "if the meter is of a type that can be read by the customer without significant inconvenience or special tools" and allows estimates "where there is good reason" (`tac7-45.txt:475-484`). Add both conditions; state that GP-08's meter is customer-readable.

**7. SCN-0142, line 277: the list of what is "beyond the utility's control" is cited as Kyle's ruling; it is an engineering proposal.**
GBM `kyle-decisions-2026-09-02-a2-backbilling-caps.md:310`: "The bucket assignments above are an engineering proposal, not Kyle's ruling. Kyle ruled the mechanism and the default." R-30 was also issued 2026-09-14, not 09-02 (the file's date). Fix: cite R-30 for the mechanism (read from the reason recorded at the time; no basis means protected; the more conservative bucket wins) and mark the dog/gate/weather list as proposed, with an Open for Kyle or counsel.

**8. SCN-0142 (a), line 279 and 284: the estimate uses the wrong month, and (b) – (e) have no figures.**
Gulf Plains bills "for the month before" (`cast.md` §3), so the read that fails on Feb 1 closes January 2027. "The same month last year" is then January 2026, not February 2026, and Gulf Plains went live on Jan 15, 2026, so half of that month predates the platform. Lines 285 – 288 give no usage or dollar amount for the March, April or May bills, and (b) ends "Estimates in a row: 2" for both branches (card returned, card not returned) while (c) assumes it was not returned.
Fix: say which month each estimate copies and give its usage (and say what is used when last year's month predates go-live); give the March and April totals; pick one branch for (b) and put the other in the Open.

**9. SCN-0141 (b′) against SCN-0143: a lower reading is billed as negative usage in one and "never negative" in the other.**
SCN-0143's Rule (line 296): "when a reading is lower than the last ... The usage is never negative". SCN-0141 (b′) (line 268) bills −2.0 Mcf because the actual is below the estimated reading. A test built from SCN-0143 would hold SCN-0141 (b′)'s read for a re-read. The parity record also says whether a negative usage is ever legitimate "is not ruled" (`invariant-parity-measurement-2026-10-13.md:152`).
Fix: scope SCN-0143's rule to a lower reading after an *actual* reading, and state in SCN-0141 that a reading below an *estimated* one is an over-estimate, credited, never a rollover; add the negative-usage question to the Open.

**10. SCN-0141 (b′), line 268: a −$4.19 bill against Bluebonnet's minimum bill.**
`cast.md` §2: "Minimum bill: the customer charge, every month". The built floor adds an adjustment line whenever the bill's subtotal is below the schedule's minimum (`sql/tu.sql:4291`; parity CI-103, line 412). If Bluebonnet's minimum is configured as $14.75, the built rule would add $18.94 back and erase the credit. Fix: say that Bluebonnet's "minimum" is only the customer charge always being billed (no floor amount configured), or add the question to the Open.

**11. SCN-0135, lines 127 – 145: an invariant already answers the Open, and the Status misdescribes what is built.**
GBM `application/canonical-invariants.md:1800` (CI-103): the floor "is evaluated once, against the assembled total, after the full charge stack (including riders, WNA, PGA, taxes ...) has settled". That is reading (a), with tax counted too. What is built is one floor amount on the rate schedule, compared with the bill's subtotal excluding tax (`sql/tu.sql:4291`, parity line 412), also reading (a). Reading (b), a floor on the $9.00 rate only, has nowhere to live, and "refused at setup with no stated base" (line 144) is not built and is no one's ruling. The minimum is a setting of the schedule, not "a rate item".
Fix: cite CI-103, say (a) is the invariant's and the schema's answer, keep (b) as the question for Kyle ("does any city floor only the rate?"), and mark line 144 "not built; this stream's reading". Note the tax discrepancy (invariant counts tax, schema excludes it) for the rates stream.

**12. SCN-0138, lines 196 – 216: how the $798.41 reaches the customer is asserted, not ruled.**
(a) The Texas rows for this cause carry "delivery path: unruled" (`law/backbilling/backbilling_rules.yaml:18-27`), and SCN-0027's rule lets only a rate misapplication (and, by Kyle's answer 7, a keying error) travel by void and reissue when it charges more. Voiding and rebilling three bills upward for a billing constant error is this stream's reading; say so and add it to the Open. (b) Kyle 11-05 answer 2 (GBM `kyle-decisions-2026-11-05-scenario-batch-2.md:14`) already says the amount an error hid goes on the next regular bill with that bill's due date; the scenario should apply it, which also frames the Open about spreading it. (c) The Given does not say whether the three bills were paid (void and rebill versus credit and rebill, SCN-0089), nor whether the charge can ground a cut-off (SCN-0031). (d) Kyle 11-05 answer 13 ("a documented field check is a finding") is about a meter found not registering; using it here is an extension, fine but worth one word.

**13. SCN-0130 (a), line 22, and `cast.md` §6: the reference bill's period does not match its source.**
`cancel-rebill.md:7` and `tax.md:14` give the reference bill as "period Oct 15 – Nov 13". SCN-0130 says "Oct 15 – Nov 14 ... (the reference bill)", and §6 says Bluebonnet reads on the 15th and bills the next day. SCN-0001's period (Sep 15 – Oct 14) and `tax.md:172` (Oct 15 – Nov 14) agree with the new text; the reference bill is the odd one out. Fix one or the other so a test fixture has one period; also Nov 15, 2026 is a Sunday (used as a read date in SCN-0139, 0141, 0143, 0144).

**14. Naming a month's figure: two conventions now coexist.**
SCN-0001 calls the $0.42 figure "September's locked gas cost figure" (the month it was locked: `billing-pipeline-and-charge-composition.md:34`); `cancel-rebill.md:129` calls $0.30 "September's gas cost adjustment" (the month the bill was issued); this family uses the issue month ("December's figure"). SCN-0131's hold reason "no locked gas cost figure for December" would read "for November" in SCN-0001's words. Fix: state the convention once in the common block and, when SCN-0001 is next touched, reword its two lines.

**15. Family header, line 3: CI-034 is listed but its text says the opposite of Kyle's ruling.**
CI-034 (GBM `canonical-invariants.md:623`) says a gas cost change inside a period is prorated by days; Kyle 11-03 answer 1 says the figure is never split, and the parity record still grades CI-034 as represented on the day-split machinery (line 343). The family should say the invariant's text is superseded for a monthly figure and note it for the parity record; otherwise a test strategy keyed to invariants will ask for a proration test.

**16. SCN-0140 (c), line 250: the operator's "rebill or catch-up" choice is applied to an overcharge.**
Kyle 11-03 answer 7 is titled "Read keyed too low" (GBM `kyle-decisions-2026-11-03-scenario-batch-1.md:21`), and SCN-0027 (b) is that case. Here the read was keyed too high (1,530 for 1,503 Ccf: 2.7 Mcf overbilled). Answer 8 says a missing rule never holds back a refund. Catch-up on an overcharge leaves the customer out of pocket for a month. Fix: correct it as SCN-0002 (void and rebill, or credit and rebill if paid), or ask Kyle whether catch-up is allowed downward. No dollar amounts are given for (c) and no 2027 gas cost figure exists for Pecan Flat, so no bill test can be built; add the figure to `cast.md` §6 or say only the fee is under test.

**17. SCN-0144 (a), lines 313 – 318: the pressure test's result is missing, so the mismatch is ambiguous.**
D3B-1 compares the factor *the pressure test establishes* with the premise's last-known factor (GBM `wu5-wu6-kyle-decisions-2026-07-10.md:125`). The scenario compares the new meter's set-up record ("standard pressure") with the premise. If the test finds 1.0400, there is no D3B-1 mismatch, only a wrong set-up value to affirm (D3B-2). State the test result and which of the two records the operator makes.

**18. SCN-0134, line 104: the Status understates what exists and the parity grade.**
The parity record grades the pass-through invariant as represented because billed gas cost revenue per period sits in the monthly reconciliation table (`invariant-parity-measurement-2026-10-13.md:182`). The scenario's record (per figure, volume, month posted, corrections netted) is not that table. Say so: "the built table holds one revenue total per month beside purchases and a balance; the per-figure, per-posting record this scenario needs is not drafted, so the parity grade is generous".

**19. Refusals that do not say whose they are (brief item 3).**
- SCN-0133 line 97: issuing at December's figure "is refused". SCN-0006 says this refusal is the core's; say it here, and note that today nothing ties a correction to a billing month's figure.
- SCN-0137 line 189: "a factor change entered with no method is refused when it is entered": not built, this stream's reading.
- SCN-0139 line 234: editing a billed reading is refused: this one is built (the freeze on billed reads, parity CI-025 and CI-031, lines 153 – 154); the Status lists only what is missing. Line 233's "change history keeps 1,221.2" for an in-place fix before billing: say whether that history is built.
- SCN-0145 (d): correctly says not blocked.

**20. SCN-0132 Open, line 82: the second question has an answer in SCN-0069 and SCN-0028.**
`date-tracking-and-immutability.md:36` already treats a rate keyed too low as an upward correction that "passes ... under Bluebonnet's six-month default (SCN-0028), cause rate misapplication". Either adopt that for an undercharging gas cost figure or say why a gas cost figure differs. Also, the paid case should point to SCN-0089 (payment moves to the corrected bill; whether the leftover needs the customer's approval is its Open), not SCN-0082, which requires the customer's approval for a held credit.

**21. SCN-0139 and `cast.md` §6: PF-01's meter contradicts the cast.**
§6: "Pecan Flat's residential meters have a four-dial index in hundreds of cubic feet". SCN-0139 gives PF-01 (a homeowner) a meter reading 1,204.0 Mcf to a tenth, "invented; most ... read in Ccf". Fix the cast to "most", or put SCN-0139 on a Ccf meter. (b) has no bill amount: 8.2 Mcf is $73.80 + $56.17 = $129.97.

**22. SCN-0141: Kyle's K-03 points the other way from the scenario's rule; mention it.**
K-03 lists "estimate trued up" as a reason a replacement reading carries (GBM `kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md:23`), and D-5's list has "estimate replaced by an actual". Line 269 says the December estimate "is never ... replaced". Both can hold (replace only an unbilled estimate), but the Open should cite K-03. The second half of Open (1), "should the utility state its method", is already answered by CI-114's text ("configured per jurisdiction and applied consistently", GBM `canonical-invariants.md:1985`) and Kyle 10-15 R-11 (estimation is dated rule data).

### Nits

**23.** SCN-0136 (b), line 162: no dollar figure. With a full customer charge BB-18's bill would be $82.90 + $72.07 + $166.92 + $18.10 = $339.99, state $21.25, county $1.70, **$362.94**; but the first period is Nov 20 – Dec 14 (25 days), and whether a first partial month's customer charge is prorated is unstated. Give the amount or say it is not under test.
**24.** SCN-0136 Rule: K-02 says a zone is assigned "to the location or meter" and CI-020 says the premise; the scenario says the meter only.
**25.** SCN-0132 Sources: T-1 covers a bill issued on a *stale or missed* figure; "wrongly loaded" is the author's extension (the Status admits (b) and (c) are a reading; the Sources line should too).
**26.** Weekend dates: May 1, 2027 (Gulf Plains read, SCN-0142 d) is a Saturday; Apr 25, 2027 (the due date) is a Sunday and §7.45(4)(A) has no next-workday rule, so it stands, but say so; Jan 1, 2027 (last actual read) is a holiday; May 15, 2027 (SCN-0145) is a Saturday.
**27.** SCN-0130 (b): read Nov 30, issued Dec 2, though §6 says Bluebonnet bills the next day; Dec 1 gives the same result.
**28.** `cast.md` §6 pressure zones: Courthouse Square has no factor; SCN-0078 gives 1.0500, then 1.0800 from Mar 1, 2027. Both zones change on the same day; fine, but state it. SCN-0078's rule ("reads the factor in force on its date") will need SCN-0137's method once that is settled.
**29.** `cast.md` §6 figures for January and March 2027 ($0.71, $0.49) differ from the $0.42 that `tax.md` and SCN-0054 use in 2027; `tax.md:14` covers itself ("used in later months too for comparison"), but SCN-0054 does not carry that note.
**30.** SCN-0138: BB-19's index is shown to a tenth (3.1) on a meter reading in units of 10 Mcf; and the Oct 16 bill's period (Sep 15 – Oct 14) straddles Oct 1, when SCN-0001 changes R-U's rates. Say LC-U's rates did not change on Oct 1.
**31.** SCN-0139 (a): the reason is written "re-read for high usage"; Kyle's list has one reason, "re-read for high or low usage" (as SCN-0143 writes it). The re-read is dated Dec 16 for a period ending Dec 15; say which date closes the period.
**32.** SCN-0142 Status: the "customer reported" reading method is built; say so.

## Gaps (cases the family should cover, within the cast)

1. **A bill held across a month end.** A bill held in December (SCN-0131, 0136) and released in January: December's figure or January's? This is the sharpest consequence of "billing month = month issued" and is not tested.
2. **A final bill or an off-cycle bill** under one figure per billing month (move-out on the 3rd; a first bill longer than a month).
3. **Gulf Plains' gas cost on a bill.** No gas cost scenario uses the regulated utility. §7.45(6)(B)(v) requires "the amount of adjustments per billing unit" on the bill, which is exactly "the bill records the month and the figure".
4. **A base-pressure meter never carries a factor other than 1.** The header lists CI-029, and nothing tests it (a residential meter wrongly placed in the Industrial Park zone).
5. **A multiplier and a pressure factor on one meter:** the order, and four-decimal rounding of the chain (CI-021 is in the header; BB-19 has only a multiplier, BB-08 only a factor).
6. **A zone confirmed but wrong** (BB-18 confirmed as Standard): a billing constant error like SCN-0138, on the factor side.
7. **A zero or very low read** (the low-usage check, the "zero or missing read" reason, a stuck meter) and the customer whose usage is truly zero.
8. **An estimate with no history** (BB-18's first months; Gulf Plains before its go-live year is complete).
9. **A city system at its estimate limit** (Bluebonnet's fourth locked-gate month), since §7.45 does not bind it and only its own setting does.
10. **A new meter starting below the old one's last reading is not a rollover** (SCN-0144's M-2 at 0.0 after 5,141.5): one sentence there would cover CI-022's "roll-under".
11. **An actual reading dated before estimates already entered** (still open with Kyle; the built streak rule says a back-dated actual does not clear the run).
12. **Two months billed on one read** (a skipped month with no estimate): which month's gas cost figure applies to the whole.
