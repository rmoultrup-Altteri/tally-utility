# Round 8 review — added gas cost, zones/factors and meter-read cases

Reviewed 2026-11-25. Scope: SCN-0146–0154; cast BB-20, BB-21, GP-09 and §6 carry-forward term; Kyle batch 7 questions 17–22. Earlier cases were read for context. Only this report was written. `GBM/` below means `/Users/ryanscomputer/code/gas-billing-memory/`; other paths are relative to TU.

Disposition: **changes needed**. Two blocking findings and seven should-fix findings, including one coverage recommendation. The displayed multiplication, rounding and addition otherwise check out. Some expected outcomes depend on policy that is still proposed, so they should not yet become unconditional acceptance tests.

## Findings

1. **Blocking — SCN-0153 gives the issue date as the correction's due date.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:493`.

   The $10.56 is said to be due Jan 16. Bluebonnet issues the next regular bill that day; it is not due that day. `scenarios/cast.md:122` establishes the issue day, and `scenarios/cast.md:62` allows 15 days and moves weekend/holiday due dates to the next workday. Jan 16, 2027 + 15 days is Sunday Jan 31, so the ordinary due date is **Monday Feb 1, 2027**. Kyle's answer 2 explicitly gives the hidden amount the next regular bill's due date (`GBM/application/kyle-decisions-2026-11-05-scenario-batch-2.md:14`). The same issue occurs in the context case SCN-0138 at family line 222; copying it does not make Jan 16 correct.

   **Fix:** say the increase accompanies the bill issued Jan 16 and is due Feb 1. Preserve the distinction between issue, aging and due date. The $352.38, $362.94 and $10.56 themselves are correct under the assumed full customer charge.

2. **Blocking — SCN-0152(b) omits PF-04's taxes from its only stated bill amount.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:472` and `:478`.

   PF-04 is the weekly rental explicitly marked taxable in `scenarios/cast.md:159`. SCN-0111 includes the premise in Texas and Pecan Flat, flags every gas line taxable, and applies state 6.25% and city 1.5% (`scenarios/tax.md:225–240`). Vacancy does not establish a change to residential use. The new case ends with a bill raised to $20.00 without carrying those taxes or distinguishing the minimum from the final amount. On a single monthly $20.00 taxable minimum, the components are **$20.00 + $1.25 state + $0.30 city = $21.55**.

   **Fix:** show the minimum adjustment, both tax lines and the $21.55 total, explicitly assuming one month's bill and unchanged taxable use. Alternatively use an existing residential Pecan Flat customer. Also state what happened to the November bill: the Given only supplies Oct 15 and Dec 15 reads, while SCN-0147 at line 394 treats an unbilled two-month interval as two minimums. If this is another two-month bill, first settle that policy and recompute the whole bill accordingly.

3. **Should-fix — SCN-0152 does not establish the stoppage date or a billable estimate, and imports a Texas-specific rule into Pecan Flat without qualification.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:469–477`.

   A Nov 15 reading above the Oct 15 reading proves that some gas registered during that interval. It does not prove the meter was working at the instant of the Nov 15 read, or establish Nov 15 as the actual stoppage date. The field check in December establishes that it is stopped then. Kyle distinguishes a confirmed finding from a known actual stoppage date (`GBM/application/kyle-decisions-2026-11-05-scenario-batch-2.md:36`). SCN-0035 expressly concerns utilities bound by §7.45 (`scenarios/backbilling.md:197`); Pecan Flat instead needs its own tariff/default treatment (`scenarios/backbilling.md:153`). No estimate quantity, approved basis, prior-test history or resulting bill is supplied. A C# test cannot derive the proposed charge from these facts.

   **Fix:** add dated evidence establishing when registration stopped, the applicable city rule, the history used, the supervisor's approved quantity and the full taxed bill. Label the application of the known-stoppage rule to a silent city as an assumption/extension unless a specific ruling supports it. State the configured low-usage threshold and a positive class average as well: Kyle's 10% figure is a configurable starter default, not an immutable rule (`GBM/application/wu5-wu6-kyle-decisions-2026-07-10.md:120`).

4. **Should-fix — SCN-0149 needs a precise late-filing effective-month term.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:423–429`; `scenarios/cast.md:130`; batch-7 question 20 at `application/kyle-brief-2026-11-25-scenario-batch-7.md:47`.

   The invented term both requires filing by the prior month's last business day and says the existing factor continues until a new one is filed. The Then makes an Oct 8 filing effective for November, with no change to October. That is a reasonable intended interpretation, but the term should state it directly: continuation "until filed" can also suggest effectiveness on Oct 8. Neither §7.5519 nor Kyle's one-locked-figure rule defines the treatment of a late filing. [16 TAC §7.5519(c)](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-5519) leaves implementation procedures to the Commission in each case.

   **Fix:** make the invented tariff say that a filing in October first applies to November bills, and the carried October figure stays locked for all October bills. Add a bill issued after Oct 8 to prove this result. Expand question 20 to ask about prospective bills later in the same month as well as retrospective rebills.

5. **Should-fix — SCN-0148 presents the proposed hard hold as a settled consequence of the cited sources.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:404–414`; batch-7 question 19 at `application/kyle-brief-2026-11-25-scenario-batch-7.md:46`.

   The six-month actual-read duty and uncapped catch-up are supported. However, R-21 says to surface the breach and interlock with the estimation controls; it does not prescribe this exact no-further-bill workflow (`GBM/application/kyle-decisions-2026-09-02-a2-backbilling-caps.md:123–135`). The scenario itself asks Kyle whether another estimate may be issued. The Rule should therefore distinguish the legal duty from the proposed operational remedy. Its status also omits the unbuilt true-up-method setting that SCN-0141 acknowledges: CI-114 remains GAP (`application/invariant-parity-measurement-2026-10-13.md:423`).

   **Fix:** label the hold as this stream's proposed core behavior pending question 19, retain the breach and uncapped catch-up assertions, and identify the unbuilt Gulf Plains catch-up-method configuration. Specify that the Sep 9 actual is validated before it resets the streak. Complete the fixture with the applicable self-read-card handling, or explicitly reference SCN-0142 for it, so the long inaccessible-meter history does not silently omit that obligation. The [six-month and postcard requirements](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-45) are in (6)(C).

6. **Should-fix — SCN-0147's doubled minimum is an unlabelled policy assumption that its worked example cannot test.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:387–398`; batch-7 question 18 at `application/kyle-brief-2026-11-25-scenario-batch-7.md:45`.

   The tariff says $20 monthly; Kyle's cited answer settles the gas-cost factor's lack of daily splitting, not the accumulation of minimum charges on a skipped bill. The proposed $40 treatment is plausible but is stated as settled. At $253.60, both a $20 and a $40 floor produce the same result. Question 18 asks whether to skip/estimate, but never asks Kyle to confirm the accumulated minimum.

   **Fix:** label this as the stream's reading, add it to question 18, and supply a low-volume variant. At 0.8 Mcf and $6.85 gas cost the pre-minimum charge is $7.20 + $5.48 = $12.68; the proposed two-month floor would add $27.32 and produce $40.00 for residential PF-01. That distinguishes the intended policy from a once-per-issued-bill floor.

7. **Should-fix — SCN-0153 silently fixes the unresolved first-partial-month customer charge.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:487–493`; related question 17 at `application/kyle-brief-2026-11-25-scenario-batch-7.md:44`.

   BB-18 began service Nov 20 and its first bill covers only Nov 20–Dec 14. SCN-0136 deliberately avoids a dollar bill because first-month proration is unstated (`scenarios/gas-cost-zones-and-reads.md:167`). SCN-0153 now uses the full $82.90 in both original and corrected bills without acknowledging that dependency. SCN-0146's Open covers both first and final bills, but question 17 asks only about a final bill. The factor correction difference is correct under the full-charge assumption; the two absolute bill totals are not independent of that assumption.

   **Fix:** state explicitly that this fixture assumes the full first-month customer charge pending question 17, and ask Kyle about both first and final bills. Preserve the provisional status of the totals, or move the correction example to a full service month.

8. **Should-fix — SCN-0151's year and initial estimate count are underspecified.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:456–461`.

   "Dec 15, Jan 15 and Feb 15, 2027" can put all three dates in 2027, despite the intended chronological sequence being December 2026 through February 2027. The first estimate is asserted to be December, but there is no last validated actual or starting streak. The actual gate uses the existing per-meter streak and blocks when the next approved estimate reaches the cap (`sql/tu.sql:17290–17304`), so an omitted prior estimate changes which month stops.

   **Fix:** write Dec 15, 2026; Jan 15, 2027; Feb 15, 2027, and give a validated actual on Nov 15, 2026 with a zero streak. The cap-3 behavior itself is correctly described.

9. **Should-fix — add a direct missing-factor refusal variant to SCN-0153.**

   **Location:** `scenarios/gas-cost-zones-and-reads.md:482–493`.

   The title promises a factor left off where needed, and Status correctly identifies the built refusal for an elevated meter with no factor. Neither When actually exercises it: (a) supplies 1.0400 to a base meter; (b) supplies 1.0000 under a wrongly confirmed Standard zone. The second is a wrong-but-present value, which does not test the missing-value guard. This is an important gap because the existing database check distinguishes missing pressure class, missing elevated factor and a present factor (`sql/tu.sql:17028–17039`; CI-023 at `application/invariant-parity-measurement-2026-10-13.md:332`).

   **Fix:** add an independent BB-18 variant with confirmed elevated class and no factor. Assert the existing billing gate refuses it, then accepts it after the confirmed 1.0400 is supplied. Keep the current wrong-zone correction as a separate branch.

## Checks completed and limits

- Recomputed all displayed monetary amounts and volumes in SCN-0146–0154 with decimal arithmetic and half-up rounding per line, including the hypothetical $38.20, the $352.38 original bill, and every state/county tax. Apart from finding 2's incomplete bill, no numerical discrepancy was found. SCN-0150's 25-day history, 24 estimated days, 28.8 Mcf estimate, 37.2320 billed Mcf and $421.16 are consistent. SCN-0154's $442.82 tax base and $472.71 total are correct. SCN-0147's approximate $6 illustration is consistent with assigning about half the 16 Mcf to the missed month; that allocation is illustrative, not measured.
- All explicitly named weekdays in the added cases match the dates. The due-date error is finding 1; the ambiguous cross-year sequence is finding 8.
- BB-20, BB-21 and GP-09 match their new cast rows. BB-20 inherits BB-17's premise; BB-21 is outside the city; GP-09 is within the regulated residential/unincorporated scope. No conflicting reuse was found for these three. PF-04's taxable use is the relevant reused-customer problem.
- Read the cited Kyle answers and relevant decision-log entries, and compared the requested earlier scenarios. The November gas-cost lock rule, pressure-factor error classification, four-decimal rounding and raw-quantity/multiplier requirement are supported. The proposed use of a supervisor's stopped-meter estimate rule by analogy in SCN-0150 is explicitly labelled and is not a false citation. None of questions 17–22 is wholly answered by the cited rulings; findings 4–7 identify necessary sharpening.
- The estimate cap and its override/field-order gate are built; the six-month query is core work. Base-pressure factor rejection is correctly described as core-owned. Meter multiplier/factor storage and estimated/removal read representation exist. The chain arithmetic is core-owned: the later replacement of `populate_reading_calculations` at `sql/tu.sql:36755–36762` removes the old automatic consumption calculation. The parity document's earlier CI-022 description is stale on that point; it is not evidence against SCN-0154.
- The [§7.45 text](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-45) supports the stated protected-service scope, estimate marking, six-month actual-read duty and conditional disconnection bar. Municipal exclusion is correctly distinguished. §7.5519 provides no universal factor effective date. Finding 5 concerns the proposed response to a breach, not the existence of the six-month duty.
- No literal database table or column identifiers occur in the added scenario text. Calling stored attributes “columns” at line 499 is unnecessary implementation language, but does not violate the narrower prohibition on names; “the meter's multiplier and factor are stored” would read more naturally.
- This was a document and schema-source review, not a live database or C# execution. No implementation edits or test fixtures were created.
