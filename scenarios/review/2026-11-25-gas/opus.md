# Review: gas cost, zones and factors, meter reads (SCN-0130 – 0145), round 7 — Opus

Reviewed `scenarios/gas-cost-zones-and-reads.md` (working tree, untracked), `scenarios/cast.md` §6 and rows BB-17, BB-18, BB-19, GP-08 (working-tree diff), against GBM rulings, TU `sql/tu.sql`, the parity measurement, the other families, and the rule texts of 16 TAC §7.45 and §7.5519 (Cornell LII, read 2026-11-25). No repo file edited.

Line numbers are lines of `scenarios/gas-cost-zones-and-reads.md` unless a file is named.

## Arithmetic: what was recomputed and holds

Every figure was recomputed with four-decimal working math, half-up to the cent per line, and each tax on the sum of its rounded lines (Python `Decimal`):

- SCN-0130: $65.18 / $0.65 / $65.83; $75.03 / $0.75 / $75.78; the counterfactual at $0.42, $74.65. All right.
- SCN-0131: $126.80, and $120.80 at $6.10. Right.
- SCN-0132: $111.57 / $1.12 / $112.69; difference $36.91. Right.
- SCN-0133: $52.61; at $0.58, $53.34. Right.
- SCN-0134: −1.5 Mcf / −$0.63; 55.2 Mcf / $32.02 (4.06 + 24.13 + 3.83); −2.0 / −$1.16. Right.
- SCN-0135: $7.32 / $20.00; $12.80 / $25.48. Right.
- SCN-0136: 31.2000 Mcf. Right.
- SCN-0137: 28 days, 14 + 14. The three volumes, all the lines and the taxes are right as computed: $453.91 / $457.38 / $450.42. **But see finding 1: the March pipeline safety fee is missing.**
- SCN-0138: all six bills, the differences ($233.89, $256.52, $308.00) and the $798.41 total; the worked October line ($313.28; $19.58, $1.57, $3.13). Right.
- SCN-0139: 18.0 Mcf over 11.4 (150% of 7.6); $126.80; $285.30. Right.
- SCN-0141: $76.40; 9.3 Mcf, $102.82; −$4.19; the 26¢. Right.
- SCN-0142: $82.50. Right.
- SCN-0143: 79 Ccf, so 7.9 Mcf; $54.115 rounds to $54.12; $125.22; 9,988 Ccf. Right.
- SCN-0144: 21.5 + 18.5 = 40.0 Mcf, 41.6 billed; $425.69 + $26.61 + $2.13 = $454.43. Right.

Weekdays checked and right: Wed Dec 2, Sun Dec 20, Tue Dec 22, Mon Nov 30, Tue Dec 1, Fri Dec 4, Tue Dec 8, Mon Jan 4 2027. The six-month reach back from Jan 4, 2027 to Jul 4, 2026 is right. Jul 1 is six months after Jan 1, right.

---

## Findings

### 1. SCN-0137: the March bill leaves out the pipeline safety fee — **blocking**
- Line 172: BB-08's bill is issued Mar 16, 2027. Bluebonnet bills the pipeline safety fee, $1.00 per service line, on its March bill, to every customer except a state agency (`cast.md:75`; SCN-0054; `tax.md:143`: "on its March bills, outside every tax base").
- All three totals are $1.00 short. They should be **$454.91 / $458.38 / $451.42**. The taxes do not change, because the fee is outside every tax base.
- Fix: add the $1.00 line (not taxed). Or move the factor change and the bill to a month other than March.

### 2. SCN-0137: the "by cycle" column contradicts SCN-0001's meaning of "by cycle" — **blocking**
- In SCN-0001 (`billing-pipeline-and-charge-composition.md:25`), "by cycle" means the whole straddling bill goes at the **new** rates: "the whole bill goes at the new rates" for the Sep 15 – Oct 14 period, after an Oct 1 change.
- SCN-0137 (line 180) applies the **old** factor 1.0400 "by cycle" to a Feb 15 – Mar 14 period after a Mar 1 change. On SCN-0001's meaning, by cycle gives 42.4000 Mcf and $457.38 (with finding 1, $458.38), the same as by read date.
- A C# test built from both scenarios would contradict itself.
- Fix: either recompute "by cycle" as the new factor, and note it equals by read date here, as SCN-0001 does; or define "by cycle" explicitly in both scenarios. One definition, used everywhere.

### 3. SCN-0140 (c): the re-read request comes before the read it corrects — **blocking**
- Line 245: "on Oct 12; the re-read shows the Oct 15 read was keyed wrong … on a bill already issued". A request on Oct 12 cannot find fault with an Oct 15 read that has already been billed.
- Fix: make the request Oct 22 (after Pecan Flat's Oct 20 bill), or make the faulty read Sep 15.

### 4. SCN-0142: what counts as beyond the utility's control is cited as Kyle's ruling, but it is an engineering proposal — **blocking** (a wrong claim)
- Line 277 cites "Kyle 09-02, R-30 (what is beyond the utility's control: a locked gate, an aggressive dog, …)". (e) at line 288 rests on that list.
- GBM `application/kyle-decisions-2026-09-02-a2-backbilling-caps.md:311`: "**The bucket assignments above are an engineering proposal, not Kyle's ruling.** Kyle ruled the mechanism and the default." Kyle ruled two things: protection is judged from the reason recorded on the read, and where no reason is recorded the protection stands.
- Fix: cite R-30 for the mechanism and the default only. Mark the dog-as-beyond-control placement as the proposal, referred with the tariff-counsel questions. Or add it to the Open.

### 5. SCN-0136 and SCN-0144: the Status lines say the confirmation records are not built, but they are — **blocking** (a wrong status)
- SCN-0136 line 153 says only that the confirmation at activation "is Kyle's D3B-2", within a "Not built" status. SCN-0144 line 310 says the swap pressure check, Kyle's D3B-1, is "not built".
- The schema holds both:
  - `tu.sql:12099-12122`: v5.4.0-05 added the zone confirmation (who and when) and the pressure-class confirmation (who and when) on each meter, each pair enforced together.
  - `tu.sql:12124-12140`: the mismatch confirmation on a meter's installation, with who, when and the reason, all three or none.
  - Parity CI-029 is graded REP on these (`invariant-parity-measurement-2026-10-13.md:338`).
- There is also a built billing guard. `tu.sql:17012-17039`: a gas meter with no pressure class, or an elevated one with no factor, is refused billing in a run (CI-023, v5.4.2-05).
- What is not built:
  - zones as such, and a zone per factor set (CI-020, CI-026);
  - any history of a confirmation;
  - the comparison itself, which the column comments leave to application logic.
- Fix: rewrite both Status lines to say which parts exist and which are the core's. For SCN-0136 (a), say which guard holds BB-18 today: the built one, if its pressure class is blank; none, if the class is set but unconfirmed.

### 6. SCN-0136: the facts contradict the activation gate Kyle ruled — should-fix
- D3B-2 (GBM `wu5-wu6-kyle-decisions-2026-07-10.md:126`) is an *activation* gate: "measurement-critical attributes must be affirmed, never defaulted … at activation". The schema comment (`tu.sql:12119`) says the gate "must refuse to make the meter billable while this is NULL".
- SCN-0136 (line 156) has the meter "activated with no pressure zone confirmed" and held only at billing.
- Fix: make (a) the refusal of activation, and keep the billing hold as a second line of defence (named as such). Or say why the meter could be activated unconfirmed.

### 7. SCN-0136 vs SCN-0144: is the zone the meter's or the premise's? — should-fix
- SCN-0136 (line 154) and cast §6: "Every meter is assigned a zone", "Every meter's zone is confirmed when the meter is activated".
- SCN-0144 (lines 317-318): "the premise's Industrial Park factor"; "the operator confirms the Industrial Park zone".
- Kyle K-02 allows either ("assigned to the location or meter"). D3B-1 confirms a *pressure-factor mismatch* against the service point's last-known factor, not a zone.
- Fix: choose one holder for the cast; if the meter, SCN-0144's new meter gets its own zone confirmation. In SCN-0144 (a), make the operator confirm the pressure-test result against the premise's last-known factor (D3B-1), with the test as the reason.

### 8. SCN-0141 (b′) bills negative usage, though SCN-0143's rule says usage is never negative — should-fix
- Line 268: −2.0 Mcf is billed as a credit. Line 296 (SCN-0143's rule): "The usage is never negative and never guessed."
- Parity CI-022 (`invariant-parity-measurement-2026-10-13.md:152`): "-19 R8: no sign CHECK; whether a negative usage is ever legitimate is not ruled."
- Fix: narrow SCN-0143's sentence to "a read pair's own usage is never negative". Add to SCN-0141's Open that an estimate catch-up below the estimate (negative catch-up usage) is unruled, and name who rules it.

### 9. SCN-0141 (b′): does the January bill issue or wait? — should-fix (a test can't be built as written)
- "The read pair is flagged for review" (line 268). Under SCN-0139's rule (line 225), "a reading that fails validation is held from billing", and the schema's read-exception gate blocks billing while an exception is open (CI-112 REP+PROT; AC-20).
- Fix: say whether the flag is a blocking exception (the bill waits until it is resolved, then issues at −$4.19) or a notice only.

### 10. SCN-0142: the estimate's base month is wrong, and falls across Gulf Plains' go-live — should-fix
- Line 279: "February 2026's usage was 9.0 Mcf". Gulf Plains reads on the 1st for the month before (`cast.md:82`), so the Feb 1, 2027 read covers January 2027. The same month last year is **January 2026**, which straddles Gulf Plains' go-live of Jan 15, 2026 (`cast.md:82`). Only meter-test history was migrated.
- Fix: say "the period read Feb 1, 2026 (January's use), 9.0 Mcf". State that its first half is from before go-live and how that figure exists (migrated read history), or move GP-08 to dates where the base month is fully on the platform. Give the base figures for the Mar and Apr estimates too, or say that only the count matters there.

### 11. SCN-0142 (b): the returned card's reading is used as settled, against Kyle's "no customer reads" — should-fix
- Line 285 uses the card's reading ("method 'customer reported'") as a rule. Kyle 07-10 D3A-1 (GBM `wu5-wu6-kyle-decisions-2026-07-10.md:119`): "**No customer-initiated reads in v1, period.**" The Open (line 289) acknowledges the conflict, but the Then states the outcome.
- Fix: mark (b)'s use of the card as this stream's reading, pending Open (1).
- Nit: §7.45(6)(C) requires the card only "if the customer can read the meter without significant inconvenience or special tools". Add that condition to the rule (line 277).

### 12. SCN-0142 Open (2): half of it is already answered — should-fix
- "Should a utility be able to set a cap above Texas's six months at all?" Kyle DE-1 answers this: the Texas six months is the ceiling on the cap, and "the regulatory bounds attach as constraints on the knob" (GBM `configurable-rules/decision-tables/consecutive-estimate-enforcement.md:14`; `estimation-policy.md:13`). What is open is only that nothing in the schema enforces the ceiling (`consecutive-estimate-enforcement.md:49`; TU DECISION-LOG, the 2026-08-28 "Flagged, deliberately not changed" list).
- The back-dated-actual question is still open (no later ruling found).
- Fix: restate as "ruled (DE-1), not enforced", and keep only the back-dated question for Kyle.

### 13. SCN-0132 (c): the wrong rule is cited for a paid bill and for the refund reach — should-fix
- Line 81: "If BB-17 had already paid $112.69, the $36.91 is an overpayment credit (`cash.md` SCN-0082)."
  - A paid bill found wrong is credited and rebilled, and the payment moves to the corrected bill: SCN-0089 (`cash.md:182-208`; Kyle 11-03 answer 7).
  - SCN-0089's Open asks whether an excess caused by the utility's error may be held without the customer's approval. So "is an overpayment credit" states as settled what is open there.
- "An overcharge is refunded in full, with no backbilling limit (SCN-0015)": SCN-0015 is the Texas fast-meter refund at Gulf Plains. For Bluebonnet, a city system, the source is Kyle 11-03 answer 8 ("refunds go back as far as the records show") and SCN-0019.
- Fix: cite SCN-0089 and its Open; cite answer 8 / SCN-0019. Also say "credit and rebill" when paid, "void and rebill" when not.

### 14. SCN-0134: the Status understates what exists, and misses that the existing table can't be written for a city — should-fix
- Line 104 says today's monthly reconciliation table holds the utility's purchases and running balance. It also holds the billed gas cost revenue per month, which is the very thing parity CI-033 is graded REP on (`invariant-parity-measurement-2026-10-13.md:182`).
- It also *requires* the utility's actual gas cost and a deferred balance on every row (`tu.sql:12199-12202`, NOT NULL, with a variance check). The platform no longer holds either (Kyle 10-14, answer 6). So no row can be written for a city that doesn't hand over its purchases.
- It holds no volume, no row per figure, and no month-posted split.
- Fix: say this in the Status, and flag CI-033's REP grade for re-measurement at the next mirror.

### 15. The family never says that a city's Mcf bill is refused at issue today — should-fix
- Ryan's 2026-11-04 decision (roadmap R-19) needs a money-stream patch loosening -21's bill-line check. Until it lands, every Mcf bill line without therm figures is refused at issue (`HANDOFF.md:87`; `tu.sql` has no "dekatherm"). The common section cites the decision (line 8) but not this.
- The Status lines that call parts "built" (SCN-0135, 0138, 0141, 0143, 0144) would mislead someone building a test today.
- Fix: one sentence in "Common to every scenario here".

### 16. SCN-0135: the minimum bill is not a rate item, and the schema already describes the (a) reading — should-fix
- Line 127: "The minimum bill is a rate item (built)". It is an amount on the rate schedule version (`tu.sql:14860`). Its documented base is "the meter's service-type subtotal (excluding tax)" (`tu.sql:4291`). That includes the gas cost line, which is reading (a).
- Reading (b), and "a minimum bill with no stated base is refused at setup" (line 144), have no home, and the scenario doesn't say whose the refusal is.
- Fix: correct the Status, and name the refusal as unbuilt (the rates stream's setup check, or the core's).

### 17. SCN-0138: the delivery path and the law row are overclaimed — should-fix
- Status line 196: "billing constant error is a law row (built)". The rows bind regulated utilities only: their owner types are cooperative and investor-owned (`law/backbilling/backbilling_rules.yaml`; `tu.sql:24370`). Their protected-class rows are flagged as placeholders, "referred to counsel", with the delivery path "unruled" (`tu.sql:31364-31372`).
- For Bluebonnet, only the city's six-month default applies (SCN-0019, not built).
- Rule line 197 states "voided and rebilled" as settled. How a billing-constant correction reaches the customer is unruled; Kyle 11-05 answer 2 puts an amount an error hid on the next regular bill.
- How the $798.41 ages isn't said. Kyle 11-03 answer 10: an increase ages from the correction date, with a new due date.
- The rebills are issued in 2027. Say they carry 2026's taxes, so no 0.25% crime-control district, which a test author might otherwise apply.
- Fix: correct the Status. Mark void and rebill as this stream's reading, or add it to the Open. Add the due date and age of the increase, and the tax note.

### 18. SCN-0130: "every other rate is read at its period's last day" contradicts SCN-0001 — should-fix
- Line 7 and line 37. Under SCN-0001 and Kyle 11-03 answer 1, a mid-period rate change follows the method stated when it was entered (split by days, by read date, or by cycle), not the period's last day. The period's last day is only the snapshot's as-of date (AC-31, CI-107).
- Fix: "every other rate follows the period, by its stated method; the gas cost figure follows the billing month". Name the conflict with the snapshot rule (AC-31) as what the rates stream must solve.

### 19. Small Status gaps: say whose each refusal is — nit
- SCN-0133 (line 97): the refusal of a "current" basis for gas is the core's (SCN-0006 Status: "refusing it for gas is the core's").
- SCN-0137 (line 189): the refusal of a factor change with no method is unbuilt (zones and factor tables), and the scenario doesn't say whose it is.
- SCN-0139 (line 234): refusing an edit to a billed reading *is* built (CI-025 and CI-031, REP+PROT since -19 and -20). Say so.

### 20. SCN-0140 Status: the re-read fee is not a rate item — nit
- Line 240: "The fee is a rate item (built)". Rate items are priced only as recurring or usage charges (`tu.sql:4106`), with no per-event fee. SCN-0084 (`cash.md:76`) calls the same kind of fee "a one-off charge the tariff allows (Kyle 10-15, R-01)".
- Fix: match that wording.

### 21. SCN-0139: PF-01's meter in Mcf contradicts the cast — nit
- Line 227 invents PF-01's meter reading in Mcf. `cast.md` §6 says "Pecan Flat's residential meters have a four-dial index in hundreds of cubic feet (Ccf)", with no exception. The cast rule: "If a scenario needs a fact the cast doesn't have, add it here first" (`cast.md:5`).
- Fix: add "PF-01's meter reads in Mcf" to §6 or to PF-01's row. Or use Ccf.

### 22. Cast §6 billing days: BB-19 is on the standard cycle — nit
- "BB-17 and BB-19 are on cycles described in their scenarios". BB-19 bills on Oct 16, Nov 16 and Dec 16, which is Bluebonnet's standard cycle.
- Fix: drop BB-19 from that sentence.

### 23. Due dates on a holiday or weekend — nit
- SCN-0131 (c): due Jan 1, 2027, which is New Year's Day (a Friday). SCN-0142 (e): the April bill is due Apr 25, 2027, a Sunday.
- Neither Pecan Flat's nor Gulf Plains' cast row says whether a due date rolls; Bluebonnet's does.
- Fix: state the roll (or that there is none) for both utilities, or move the dates.

### 24. Common section: §7.45's scope — nit
- Line 10 is right that city systems are not bound. Add that §7.45 applies of its own force only in unincorporated areas, and inside a city only where it doesn't conflict with the city's standards (rule text; `application/places-sources/texas.md:86`). Gulf Plains is bound because GP-08 is unincorporated.
- The §7.45 quotes otherwise check out against the rule text: (6)(C), an actual read at least every six months and the card at the second straight month; (6)(B)(viii), "a distinct marking to identify an estimated bill"; (4)(E)(vii), no cut-off on an estimated bill unless the utility could not read the meter for circumstances beyond its control.
- §7.5519: the cast's wording at `cast.md` §6 is right. The rule sets no effective date and no filing deadline, and leaves the procedures to the Commission in each case, under subsection (c).

### 25. The two families name the same figure by different months — nit
- SCN-0001 (`billing-pipeline-and-charge-composition.md:10, 32`) names a figure by the month it was locked: "September's locked gas cost figure" for October's bills. This family names it by its billing month: "December's figure" for bills issued in December.
- SCN-0001 also says changing a locked figure "is refused" outright, while SCN-0132 (b) allows a supervisor's recorded correction.
- Fix: align SCN-0001's wording, and point it to SCN-0132.

### 26. CI-034's grade rests on a premise Kyle reversed — nit, for the parity record
- The intro (line 3) lists CI-033 – CI-035. CI-034, "PGA Mid-Period Proration", is graded REP+PROT on day-split support (`invariant-parity-measurement-2026-10-13.md:343`). Kyle 11-03 answer 1 says the gas cost figure is never split.
- Fix: one line in SCN-0130's Status, noting that CI-034's wording must be re-read before its next grade.

---

## Gaps (cases within the cast the family should cover)

### 27. A held bill that slips into the next month changes its gas cost figure — should-fix (gap)
- Under the issue-month rule, a bill read Nov 14 but held past Nov 30 (a read exception, a missing zone, SCN-0131's wait) takes December's figure only because it was late.
- This is the sharpest consequence of choosing the issue month, and it is what Kyle needs to see to answer SCN-0130's Open.
- Add a case, or an item in SCN-0130 or SCN-0131, with BB-01 held from Nov 16 to Dec 1 ($0.42 against $0.58).

### 28. Other missing cases — should-fix (gaps)
- A final bill, or a move-in partway through a month, under one figure per billing month. Two bills for one meter in one billing month; the inventory lists this as uncovered.
- No actual read by Gulf Plains' six-month deadline (Jul 1, 2027 for GP-08). What happens to the Jul 5 bill, and the surfacing Kyle asked for in R-21 (GBM `kyle-decisions-2026-09-02-a2-backbilling-caps.md:133`).
- A meter change where the old meter's removal read can't be taken (an estimated removal read).
- Gulf Plains' gas cost factor not filed by the last business day: the regulated counterpart of SCN-0131. It can wait for the tariff, but say so.

## Plain language
No table or column names found in scenario text. The reason and purpose values appear as plain words ("re-read for high usage", "dispute recheck", "customer reported"). Fine.

## Rulings checked and found as cited
- Kyle 11-03, answers 1, 7, 8 and 10.
- Kyle 10-14, answers 6 and 7 (the quotes are right).
- Kyle 10-15, K-02, K-03 and R-10.
- Kyle 08-18, D-3, D-5 (the reason list matches exactly; in-place edits only for typo fixes on reads not yet billed) and D-6.
- Kyle 08-26, R-11 (the lock at approval).
- Kyle 07-10, T-1, D3-1, D3A-2 (the 150% check), D3B-1, D3B-2, D11-2 and D14-1.
- Kyle 09-23: the billing constant error definition.
- Kyle 11-05, answers 10 – 13 and 17.
