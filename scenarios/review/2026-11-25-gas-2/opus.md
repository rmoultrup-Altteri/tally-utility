# Review round 8 (Opus): gas cost, zones and reads, added cases SCN-0146 – 0154

Scope: `scenarios/gas-cost-zones-and-reads.md` lines 354–509, `scenarios/cast.md` (BB-20, BB-21, GP-09, Gulf Plains carry-forward in §6), `application/kyle-brief-2026-11-25-scenario-batch-7.md` questions 17–22. Line numbers below are file lines in `gas-cost-zones-and-reads.md` unless another file is named.

## Arithmetic: what I recomputed

Every dollar figure and volume in SCN-0146, 0147, 0148, 0149, 0150, 0153 and 0154 matches when recomputed (four-decimal working, half-up per line, tax on the sum of the rounded lines):

- SCN-0146 (a): $34.13 → tax $0.34 → **$34.47**; customer charge by days 12.80 × 10/31 = 4.1290 → $4.13, $25.46 → $0.25 → **$25.71**. Correct.
- SCN-0147: 16.0 × 9.00 = 144.00, 16.0 × 6.85 = 109.60, **$253.60**. "About $6": 8 Mcf × (6.85 − 6.10) = $6.00. Correct.
- SCN-0148: estimates add up to 26.7; 34.5 − 26.7 = 7.8; 15.00 + 31.98 + 26.52 = **$73.50**. Correct.
- SCN-0149: 15.00 + 11.89 + 9.86 = **$36.75**; at $3.90, 11.31 → **$38.20**. Correct.
- SCN-0150: 1.2 × 24 = 28.8; 35.8 × 1.04 = 37.2320; 86.0059 → 86.01; 199.1912 → 199.19; 26.4347 → 26.43; subtotal 394.53; state 24.6581 → 24.66; county 1.9727 → 1.97; **$421.16**. Correct.
- SCN-0153 (b): at 1.0000, 330.10 + 20.63 + 1.65 = $352.38; at 1.0400, 72.07 / 166.92 / 18.10, subtotal 339.99, 21.25, 1.70 = **$362.94**; difference **$10.56**. Correct.
- SCN-0154: 43.68; 100.90 / 233.69 / 25.33; subtotal 442.82; 27.68; 2.21; **$472.71**. Correct.

Day counts: Nov 20 – Dec 14 is 25 days and Dec 15 – Jan 7 is 24 days. Correct. Weekdays: Wed Dec 2, Thu Dec 10, Fri Dec 11, Mon Jan 4 2027, Sun Dec 20, Mon Mar 1 2027, Thu Sep 9 / Fri Sep 10 2027, Thu Sep 30 2027, Tue Oct 5, Fri Oct 8, Fri Jan 8 2027, Mon Jan 4 2027. All correct.

The law quotes in the brief's item 5 match 16 TAC §7.45 as published on Cornell LII (fetched 2026-11-25): (6)(B)(v), (6)(B)(viii), (6)(C), (4)(E)(vii), and the scope paragraph. I found no misstatement of §7.45 in the added cases.

## Findings

### 1. SCN-0152 (a), line 476: the backbill limit applied to Pecan Flat is the Texas state rule, which does not bind Pecan Flat. **Blocking (wrong claim; the result happens to be unchanged)**
- The scenario says the missed usage "is billed as a non-registering meter under Pecan Flat's backbilling rule: a known stoppage under three months charges only that period". Pecan Flat has no backbilling rule (`cast.md` §1 has none). The three-month window and the known-stoppage cut come from 16 TAC §7.45(7)(B)(v)(II), through Kyle 11-05 answer 13. That answer was asked about SCN-0035, which is a Gulf Plains case, and SCN-0035's own Rule says "where §7.45 binds" (`backbilling.md:197`). For a city system, a charge reaches back six months by default, counted from the finding, until the city records its own rule (Kyle 11-03 answer 8; Kyle 11-05 answers 10–12; SCN-0019, `backbilling.md:153`).
- Fix: cite SCN-0019's six-month default for a city undercharge. Since Nov 15 is inside that window, the charge is still "since Nov 15". Keep answer 13 only for what it settles generally: a finding needs a field check or a shop test, and with no history the supervisor approves the estimate with its basis.

### 2. SCN-0152 (b), line 479: PF-04's bill leaves out its sales tax. **Blocking (figure incomplete)**
- PF-04 is the weekly visitor rental. In the cast it is taxed as non-residential use: state 6.25% and city 1.5%, every gas line flagged taxable (`cast.md` customers row; `tax.md` SCN-0111 (c), $81.35 on $75.50). The scenario gives the bill as "zero usage, raised to the $20.00 minimum" and shows no tax. SCN-0135 notes that the schema checks the minimum before tax while CI-103 checks it after tax, so here the two readings give different figures: **$21.55** under the schema's reading ($20.00 + $1.25 + $0.30, if the minimum adjustment is taxable) and **$20.00** under CI-103's.
- Fix: state the tax lines and the total under the expected reading, and point to SCN-0135's note. A simpler alternative is to use a residential Pecan Flat customer for (b), such as PF-06, so no tax applies. SCN-0135 also says "Pecan Flat bills no tax", which holds only for residential customers.

### 3. SCN-0146 (a)/(b), lines 360 and 376: the move-out day is counted in both bills. **Should-fix**
- BB-17's final bill prorates "10 of 31" days, which means Dec 1 – 10. That fits SCN-0130 (b)'s convention, where a reading on Nov 30 ends the period Nov 1 – 30. But BB-20's first bill is "Dec 10 – 31", which is 22 days. Together the two bills cover 32 days of a 31-day month. By the same convention BB-20's period is Dec 11 – 31, 21 days.
- Fix: change BB-20's period to Dec 11 – 31. Also state what happens to BB-20's customer charge (finding 4).

### 4. SCN-0146, lines 372–379: under the expected reading, December gets two full customer charges. **Should-fix**
- The expected result gives BB-17 the full $12.80 because it "had service in December". By the same reading BB-20's first bill also carries the full $12.80 for December, which puts $25.60 of customer charge on one premise in one month. The scenario doesn't say this, and Kyle's question 17 asks only about the final bill.
- The quoted "the customer charge, every month" is the cast's paraphrase. Brenham's actual words are "The minimum monthly base bill shall be the customer charge for each month of the year, regardless of whether service is disconnected during the summer months" (`cast-sources/texas-city-gas-tariffs-2026-11-02.md:58`). That sentence is about a continuing customer who shuts off for the summer, not about move-in and move-out. So the expected result rests on the stream's reading more than the wording suggests.
- Fix: in (b), say whether BB-20's first bill carries the full charge or a share by days. Quote the tariff's real sentence. Widen question 17 to cover both the final and the first bill. Note that SCN-0153 (b) silently gives BB-18's first partial month, Nov 20 – Dec 14, the full $82.90 (finding 12).

### 5. SCN-0146, line 378: one reading named by both bills does not fit the reading purposes the schema has. **Should-fix (Status)**
- In the schema a reading has one purpose, from a fixed list that includes `final_read`, `initial_read` and `turn_on` as separate values (`sql/tu.sql:3582`). A single reading that is both BB-17's final and BB-20's first has no single purpose that fits.
- Fix: Status should say that a shared move-out / move-in reading is not built (or is the core's), or the Then should say which purpose the reading carries.

### 6. SCN-0148, Rule (line 405) and (a) (line 413): holding the bill at six months is stated as settled, but it is the stream's reading. **Should-fix**
- Kyle's R-21 (GBM `kyle-decisions-2026-09-02-a2-backbilling-caps.md:133`) says a catch-up spanning more than six months of estimates is evidence of a breach of the six-month rule, and that the platform should "**surface** that, not quietly bound it". §7.45(6)(C) requires an actual reading at least every six months. It does not say what happens to the next bill. The scenario's Rule ("the next bill is not issued on another estimate. A supervisor must get an actual reading") is therefore the stream's reading, and the Open asks exactly that question. The Rule should say so.
- What is built makes this the core's alone: the estimate-cap exception that already exists can be resolved by an override every time (CI-113; AC-21). Nothing in the schema stops a supervisor's override after six months.
- Fix: mark the hold as "this stream's reading". In Status, say the built cap exception would let an override through, so the six-month refusal is entirely the core's (CI-090).
- Related nit: (6)(C) requires the self-read card in the second straight month without access. GP-09's run of failed reads started Apr 1, so the card was due in May. The scenario doesn't say whether it was sent or why not, for example a meter the customer can't read.
- Related gap: the scenario doesn't say whether the Sep 10 catch-up can ground a cut-off. Under R-30 the answer turns on the recorded reason; a locked gate falls on the "beyond the utility's control" side under the engineering proposal. Add one bullet, as SCN-0142 (e) does.

### 7. SCN-0149, Rule (line 421) and (a): when a carried-forward figure counts as locked is not stated. **Should-fix (a test could not be built)**
- The Rule says "a carried figure is the month's locked figure, recorded as carried". The scenario doesn't say when October's carried $3.40 becomes locked, or by whom: automatically when Sep 30 passes, when a supervisor confirms the carry, or when the Oct 5 run starts. A C# test needs that event. Compare SCN-0131, where the lock is the supervisor's approval.
- Fix: name the event. For example: "on Oct 1 the platform records October's figure as $3.40, carried under the tariff term, and a supervisor approves it", with the record's fields.

### 8. SCN-0150, Rule (line 438): the no-fallback rule and the supervisor's estimate are the stream's reading, and the analogy is weak. **Should-fix**
- Kyle 11-05 answer 13 ("No test history: supervisor approval with the estimate basis attached") concerns a meter with no *shop test* history under §7.45(7)(B)(v)(II). It does not concern a customer with too little *usage* history for the estimating method. The scenario does say "by analogy", but the Rule's first sentence ("the core does not fall back to another method on its own") cites nothing. Kyle 07-10 D3B-2 ("measurement-critical attributes must be affirmed, never defaulted") is the closer source.
- Fix: label the Rule's first two sentences "this stream's reading", and cite D3B-2 as the nearer support. Question 21 already asks Kyle.

### 9. SCN-0151, line 459: BB-02 is reused on facts that conflict with SCN-0141 and SCN-0134. **Should-fix**
- SCN-0141 has BB-02's gate locked on Dec 15 and an actual reading on Jan 15, 2027 (2,325.9 or 2,314.6). SCN-0134 relies on BB-02's December estimate. SCN-0151 has the gate locked again on Jan 15. The scenarios stand alone, but the brief asks for this check, and a reader of the three together gets two different January 15ths.
- Fix: use a new rural residential customer, or BB-09 (a renter outside the city, `cast.md`). Alternatively write "continues SCN-0141 (a), but the Jan 15 read also fails" and accept that SCN-0141 (b) then doesn't happen.
- Nit: "Dec 15, Jan 15 and Feb 15, 2027" reads as if Dec 15 were also 2027. Write "Dec 15, 2026, Jan 15 and Feb 15, 2027".
- Nit: Status should say that the cut-off check is the collections rules' (-26, not mirrored), as SCN-0142 does.

### 10. SCN-0152 (a), line 471: PF-03's usage conflicts with the tax family, and the estimate a test needs is not given. **Should-fix**
- `tax.md` SCN-0111 (b) bills PF-03, the café, at 30.0 Mcf in a month. Here "19 Ccf (1.9 Mcf), a normal month" is about a sixteenth of that, which is also unusually low for a café open every day.
- The December bill "is issued on that estimate, marked as one", but the scenario gives no estimated volume, no basis and no dollar figure. A C# test can't assert anything on it.
- Fix: use a usage in line with SCN-0111 (for example 300 Ccf, 30.0 Mcf), and give the supervisor's estimate and the bill. With Pecan Flat's tax, the figures are state 6.25% and city 1.5% (PF-03 is commercial).

### 11. SCN-0152, Status (line 469): "built as a setting" does not describe the 10% class-average check. **Should-fix**
- What is built is `anomaly_detection.low_usage.multiplier_threshold`, default 0.25, plus a separate zero-usage switch (`sql/tu.sql:4664–4668`). It is a ratio with no class-average basis. Kyle's D3A-2 starter default, "10% class-average low-usage", has no representation: grepping tu.sql for a class average finds only an unrelated final-bill item. The reason "re-read for a zero or missing read" is not built either (SCN-0139's Status says the replacement reason is not built).
- Fix: "a low-usage threshold exists as a setting (a ratio, default 0.25); a check against the class average and the re-read reason are not built".

### 12. SCN-0153 (b), lines 487 and 493: which record was wrong is ambiguous, and the partial first month is assumed. **Should-fix**
- "BB-18's meter was confirmed in the Standard zone at activation by mistake", then "the zone is corrected to Industrial Park from Nov 20". In the cast, a zone is assigned to the premise and the meter is confirmed against it (`cast.md` §6; SCN-0136). If the premise was assigned Industrial Park, SCN-0136's activation check would have refused a Standard confirmation. So the error must be the premise's zone assignment, or the check was bypassed. A test needs to know which record is corrected and which stays as history.
- The Dec 16 bill for Nov 20 – Dec 14 carries the full $82.90 customer charge. SCN-0136 says whether a first partial month is prorated "is not stated", and SCN-0146 makes the question Open. The $10.56 difference is unaffected, but $352.38 and $362.94 are not. Fix: say "with the full customer charge (SCN-0146's expected reading)".
- Consistency with SCN-0138: SCN-0138's Status notes that the cause "billing constant error" exists only in the Texas law rows, and that for Bluebonnet only the city's six-month default applies. SCN-0153's Rule ("A wrong factor is a billing constant error") and (b) ("The cause is 'billing constant error'") drop that caveat. Add it.

### 13. SCN-0147, Rule (line 388): "the minimum bill counts once per month covered" is the stream's reading, stated as a rule. **Nit**
- The tariff says "$20.00 a month". Counting the minimum twice for a two-month bill is a reasonable reading but unruled. The bill clears $40.00 easily, so no figure depends on it. Label it, or add it to question 18.
- Consistency: SCN-0139 has PF-01's **Nov 15** reading at 1,204.0, and here 1,204.0 is the **Dec 15** reading with November unread. The scenarios stand alone, but changing the numbers costs nothing.
- `cast.md` §6 gives Pecan Flat an estimate method and a cap of 3. A note that Pecan Flat may skip a month instead of estimating (the choice this scenario tests) belongs in the cast's Estimates paragraph.

### 14. SCN-0154 and `cast.md` §6: BB-21's multiplier is missing from the cast's Meters paragraph. **Nit**
- `cast.md` §6 "Meters" names only BB-19's ×10 meter. Add BB-21's. The rest of SCN-0154 is correct. The claim that both orders give the same volume holds because the multiplier is a whole number; with four-decimal rounding at each step, a fractional multiplier could make the order matter. That doesn't change the scenario, which fixes the order anyway.

### 15. SCN-0146 (a): the final bill's due date is not stated. **Nit**
- 15 days after Fri Dec 11 is Sat Dec 26, which moves to the next workday: Mon Dec 28, assuming Dec 25 is the holiday and the city is open on the 28th. The due date doesn't affect any figure, but a final-bill scenario is the natural place to show it.

### 16. Kyle batch 7, questions 17–22. **Nit**
- All six match their scenarios' Opens. Question 17 should quote the tariff's real sentence rather than the paraphrase in quotation marks, and should ask about the first bill too (finding 4). Question 19 could say that R-21 already asks the platform to surface a breach rather than block it, so Kyle can tell whether holding the bill goes further than he meant.

## Built / not built: checked

- CI-023 (REP+PROT): the billing gate refuses an elevated meter with no factor, `sql/tu.sql:17030`. SCN-0153's Built line is correct.
- CI-029 (REP, core): no constraint ties the meter factor to the pressure class. Correct as "the core's".
- CI-021 (REP): the multiplier column exists and is NOT NULL. Correct.
- CI-090 (partial): the six-month cadence is a core query. Correct.
- AC-20 / AC-21, CI-113: the cap, its exception, and resolution by override or field order are built. Correct for SCN-0151.
- CI-024 (REP): removal and installation readings exist. Whether a removal reading can be estimated is not ruled. SCN-0150's Status assigns it to the core; acceptable.
- Estimate methods `historical_average_3mo` and `same_period_prior_year` exist (`sql/tu.sql:4211`). Neither has a rule for too little history, so SCN-0150's "can't run" is the core's. Correct.

## Rulings cited: checked

- Kyle 09-02 R-21 quotes (on its face, uncapped): verbatim. See finding 6 on how they are used.
- Kyle 09-23 "billing constant error": "a correct reading converted wrong: multiplier, pressure factor, BTU/therm factor, dial count". Matches. Texas enforceability is `never`, pending counsel; not relevant to Bluebonnet.
- Kyle 11-03 answers 1 and 8: match.
- Kyle 11-05 answer 13: the quote is verbatim, but its scope is Texas and meter tests (findings 1 and 8).
- Kyle 07-10 D3A-2: 150% prior-year and 10% class-average starter defaults, per tenant. Matches.
- D14-1: per meter, reset only by a validated actual reading. Matches SCN-0150's "starts at zero".
- Kyle 10-15 K-06: four-decimal working figures, half-up to the cent. Matches.

## Gaps (within the cast)

1. **A final reading that can't be taken.** The customer moves out and the gate is locked, so the final bill is estimated and the new occupant starts from an estimated reading. Who gets the catch-up? This is common, and it joins SCN-0146 and SCN-0141.
2. **A missed month at Bluebonnet**, the companion to SCN-0147: how many customer charges a two-month bill carries, and which month's figure it uses.
3. **A rebill of a bill that used a carried-forward figure** (SCN-0149 plus SCN-0133): the rebill keeps $3.40 even after the $3.90 is filed.
4. **Gulf Plains' catch-up and the cut-off bar**, as in finding 6.
