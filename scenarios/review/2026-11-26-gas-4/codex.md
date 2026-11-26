Reviewed SCN-0163–0168 and cast rows PF-09, PF-10, BB-27, BB-28, GP-12 and GP-13 against the cited rulings, current SQL, parity record, related scenarios and §7.45. **Changes are needed before these are dependable test specifications.** The stated amounts reproduce under the proposed policies; the principal defects are unsupported claims and incomplete prerequisites, rather than cent arithmetic.

References below are relative to TU (`/Users/ryanscomputer/code/tally-utility-scenarios`) unless prefixed GBM (`/Users/ryanscomputer/code/gas-billing-memory`). Scenario line numbers refer to `scenarios/gas-cost-zones-and-reads.md` as reviewed. Only this report was created; pre-existing working-tree changes were left alone. This was a source review with independent decimal/date calculations, not a database or C# execution test.

1. **Blocking — SCN-0166, lines 757–761: the earlier actual does not establish the asserted overbilling.**

   An index of 701.5 on November 13 does not prove that an estimate of 704.0 for November 15 was excessive. Consumption during those two days is unknown. This is materially different from SCN-0160: an earlier actual of 506.2 already exceeds a later estimate of 504.0, proving an underestimate on an increasing register. The reverse inference is invalid. Likewise, 8.0 Mcf billed through December 15 cannot be compared with 1.5 Mcf measured only through November 13 to conclude that overbilling grows with every estimate.

   **Evidence:** scenario lines 752, 757–761; SCN-0160 at lines 633–640; SCN-0141 at lines 274–280. SCN-0141(b′) actually has an actual index below an earlier estimate, which establishes the excess. GBM `application/kyle-decisions-2026-11-03-scenario-batch-1.md:22` (answer 8) addresses refunds where records establish an overcharge; it supplies neither the missing November 15 index nor a rule moving a bill's closing date.

   **Fix:** Keep Ryan's conflict question, but frame it as a suspected over-estimate unless additional evidence proves the November 15 position. If the intended case is a known overcharge, supply that evidence. The alternative $28.53 bill and $22.94 credit are arithmetically correct only if November 13 is deliberately adopted as the revised closing boundary; identify that as a separate proposed policy, with the two remaining days included in the next period. Do not present it as the uniquely established refund. The provisional catch-up totals of $51.47, $33.43 and $52.11 are otherwise consistent with SCN-0141 and SCN-0160.

2. **Blocking — SCN-0164, lines 714 and 725: a new minimum-proration default is described as already settled.**

   The built default applies to fixed charges. This scenario correctly acknowledges that a minimum is a floor, but then treats extending the fixed-charge policy to that floor as an existing platform default. Neither the cited standing rule nor SCN-0146 establishes that extension. SCN-0147 addresses two complete months, not a fractional-month minimum. The choice changes PF-09's bill from $20.00 to $6.67 and the deposit refund from $80.00 to $93.33: this is a decision about money.

   **Evidence:** scenario lines 713–714, 721–725; `sql/tu.sql:4277,4726` explicitly describe fixed-charge handling; `sql/tu.sql:4291,14860` describe the minimum separately. SCN-0146 lines 360–383 and SCN-0147 lines 389–401 have the narrower scopes above. GBM `application/kyle-decisions-2026-11-03-scenario-batch-1.md:9` says existing defaults apply when the tariff is silent; TU `application/DECISION-LOG.md:19` retains questions about a new default affecting money for Kyle.

   **Fix:** Make prorating the minimum an explicit invented Pecan Flat policy selected at onboarding, which preserves this example without asking Kyle about that utility's choice. Alternatively, mark the proposed platform default provisional and route the default question under Ryan's triage rule. Do not call the extension already settled by the fixed-charge implementation.

3. **Blocking — SCN-0163, lines 686 and 707: the minimum calculation is not a built database check, and CI-103 does not expressly prescribe an untaxed adjustment.**

   SQL represents the minimum amount and the adjustment line type. Its comment describes the intended pre-tax calculation; it is not executable enforcement. CI-103 explicitly assigns applying the floor and writing the adjustment to the core. Consequently, “Built … compared with the bill's subtotal” and “the built check” overstate what exists. Separately, CI-103's “after the full stack settles” is ambiguous about ordering; it does not explicitly say that the adjustment carries no tax. Column (b) is an interpretation of that wording, not an implemented alternative or a tax ruling.

   **Evidence:** scenario lines 686–687, 697–707; `sql/tu.sql:3313,4291,14860,14879`; `application/invariant-parity-measurement-2026-10-13.md:412` (CI-103: partial representation, core applies the floor). The related SCN-0135 claim at lines 132–133 is the inherited source of the same overstatement.

   **Fix:** Say that the amount and line type are represented, the SQL comment specifies a pre-tax floor, and computation belongs to the core. Label (b) explicitly as a hypothetical reading of the parity wording. Preserve (a)'s $21.55 expectation and the clearly disclosed tax-advisor confirmation; the taxable minimum adjustment is already identified as this stream's reading, so it should not be promoted to a cited legal ruling.

4. **Should-fix — SCN-0165, lines 732 and 745: estimating after an unusable card is an interpretation of the law, not the quoted postcard condition.**

   The specific postcard sentence concerns a card not received in time. Here the card arrives on May 3, before billing. An invalid reading can reasonably support estimation under the broader good-reason provision, but the scenario paraphrases the statute as if it expressly covers any reading the utility cannot bill on. AC-20 establishes a validation gate, not the legal conclusion.

   **Evidence:** scenario lines 732–740; SCN-0158 lines 589–597 distinguishes timely and late receipt. [16 TAC §7.45(6)(C), Cornell LII](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-45) separately addresses good reason to estimate and late postcard receipt.

   **Fix:** Cite the good-reason provision and label applying it to an unusable timely card as the proposed legal reading. Keep “same validation checks” settled, but route the legal interpretation to Kyle or the existing legal review. Do not broaden the quoted condition silently.

5. **Should-fix — SCN-0165(c), lines 736 and 742: a fresh May 4 reading is treated as the May 1 reading without specifying the changed boundary.**

   The customer reads the meter again on May 4. SCN-0158(a), whose result is imported, explicitly dates its reading May 1. The index can legitimately remain 1,066.1, but that does not make the two physical events the same reading date. A test needs the new reading's date and the next period's starting boundary to avoid dropping or counting the intervening days twice.

   **Evidence:** scenario lines 736, 742; SCN-0158 lines 591, 596; SCN-0139 lines 240–244 explicitly handles a later re-read closing the period. GBM `application/kyle-decisions-2026-08-18-coda-items.md:361` explains that a re-read is a distinct physical event with its own date and that changing that date distorts the billing boundary.

   **Fix:** Either make the phone call a verification of the May 1 reading using contemporaneous evidence, or retain a new May 4 reading, explicitly date it, and state how it closes the period and starts the next one. Retain the $68.25 total if the stated index and charges remain appropriate. Also carry SCN-0139's unbuilt replacement-reason/pointer qualification into Status; AC-20/21 alone do not build that replacement workflow.

6. **Should-fix — SCN-0166(b), line 758: the claimed low-check pass uses the high-check comparator.**

   The scenario checks 3.0 Mcf per month against last year's 6.3. Its preceding branch and SCN-0152 instead define the low check against the customer's own historical average, with a 25% threshold. Last-year usage is supplied for the high check. Additionally, once the November 13 actual is approved, “since the last actual” can mean November 13 rather than October 15; the validation window must be explicit.

   **Evidence:** scenario lines 752, 757–758; SCN-0152 lines 484–485; SCN-0159 line 605; `sql/tu.sql:4664` records the 0.25 low threshold, and `sql/tu.sql:17312–17320` updates the latest validated actual when the back-dated reading is newer than the previous actual.

   **Fix:** Specify the validation window and compare its normalized usage against BB-28's own 4.0 Mcf baseline. If October 15–December 15 remains the intended window, say why the intervening validated actual does not reset that window; 3.0 versus 4.0 passes the stated low threshold. Keep billing from 704.0 separate from the validation calculation.

7. **Should-fix — SCN-0167, lines 770 and 775: the deposit refund assumes an unstated zero prior balance.**

   The Given supplies a November 30 actual but does not say the preceding bill is paid or that no other amount is owed. Applying only $25.71 and refunding $224.29 requires that fact. Bluebonnet applies the deposit to all amounts owed at termination, not just the bill under test. SCN-0155 explicitly supplies the paid preceding bill.

   **Evidence:** scenario lines 770, 775; `scenarios/cast.md:68`; SCN-0155 line 537; `scenarios/deposits.md:131–149`.

   **Fix:** Add that the bill through November 30 is paid and there are no other unpaid charges. Then the proposed refunds of $224.29, a further $5.38 or $9.86, and cumulative refunds of $229.67 or $234.15 follow deterministically.

8. **Should-fix — SCN-0168, lines 787 and 793–794: establish the replacement boundary before GP-13's July 5 bill.**

   GP-13's first bill is issued July 5 and uses a replacement starting reading. The final-bill correction is issued July 6 “after the reviewer confirms the shares,” without a date for that confirmation or replacement. A test cannot tell whether July 5 legitimately uses an approved replacement or whether it initially uses the estimate and itself requires correction. SCN-0155 makes validation and both billing actions part of the same explicit sequence.

   **Evidence:** scenario lines 787, 793–794; SCN-0155 lines 539, 543–546. Its alternative first bill from the estimated boundary demonstrates that this timing changes money.

   **Fix:** State that review approves the shares and records the replacement before July 5, with the outgoing correction posted July 6. Alternatively, hold GP-13's bill until that approval and adjust its issue date, or supply both the original incoming bill and its correction. The present $28.75 and $40.00 first-bill amounts are correct once the replacement is available.

9. **Should-fix — coverage gap anchored at SCN-0164, lines 721–724: the two minimums always binding hides a consequential policy distinction.**

   Both customers are below their prorated floors, so their minimums sum to $20.00. This does not test whether each customer's floor is independent when the other customer's usage already exceeds a full month's minimum. The family has full-month and two-month minimum examples, but no mixed above/below-floor move-out example.

   **Evidence:** SCN-0164 lines 721–724; SCN-0135 lines 136–150; SCN-0147 lines 394–401. The current SQL only represents a per-bill floor (`sql/tu.sql:4291`), while the proposed extension shares that floor across a period.

   **Fix:** Once finding 2's policy is selected, add a variant using the same PF-09/PF-10 cast: PF-09 still uses 0.3 Mcf, but PF-10 uses 2.0 Mcf. Under independent prorated floors, PF-09 still owes $6.67 and PF-10 owes $18.00 + $13.70 = $31.70; total $38.37. Explicitly assert that the incoming customer's usage does not eliminate the outgoing customer's $2.14 adjustment. This catches an implementation that incorrectly pools the two bills before applying a single premise minimum.

The arithmetic and calendar checks produced these results, conditional on the policies and prerequisites above:

| Case | Recomputed result |
|---|---|
| SCN-0163 | Gas $8.10 + gas cost $6.17 = $14.27; adjustment $5.73; tax on $20.00 is $1.25 + $0.30; total $21.55. Hypothetical after-tax floor: $14.27 + $0.89 + $0.21 + $4.63 = $20.00. |
| SCN-0164 | 10/30 and 20/30 shares yield $6.67 and $13.33. Adjustments $2.14 and $5.40; refund $93.33. Full outgoing minimum alternative: $15.47 adjustment. |
| SCN-0165 | 547.1 Mcf flags high; 1,005.1 is below the last actual with no rollover basis. 7.2 Mcf costs $69.00; 7.1 costs $68.25. |
| SCN-0166 | November $51.47; December actual branch $33.43; December estimate $52.11. Hypothetical 1.5 Mcf rebill $28.53 and credit $22.94. These sums do not prove the proposed November closing boundary. |
| SCN-0167 | 2.3871 → 2.4 Mcf, $25.71; 1.7742 → 1.8 Mcf, $20.33; 1.3187 → 1.3 Mcf, $15.85. Rounded tax bases $25.46, $20.13, $15.69. Unassigned remainders 3.7 and 10.7 Mcf. |
| SCN-0168 | Estimate $15.50; correction $14.00 or $20.00; additional refund $1.50 or debt $4.50. Incoming bills $28.75 or $40.00. Interest: 147 days, working amount $2.0137, rounded $2.01. Initial principal refund $184.50. |

Every explicit weekday in these six scenarios matches its date. November 16–December 15 is 30 covered days; November 30–March 1 is a 91-day read interval; January 15–June 10 inclusive is 147 interest days. December 11 plus 15 days rolls from Saturday December 26 to Monday December 28 under Bluebonnet's stated rule. July 6 plus Gulf Plains' 20 days is July 26. Pecan Flat's January 1 due date is not moved merely because it is a holiday: its cast does not supply Bluebonnet's rollover rule.

The remaining source checks support the following conclusions:

- AC-20/21's approval gate and estimate streak are genuinely enforced: `sql/tu.sql:17253–17324`. An unapproved failed card does not clear the streak; an approved November 13 actual leaves the later November 15 estimate counted. Detection of the special review remains core work, correctly qualified in SCN-0166. The card communication and six-month checks remain gaps/partial work, as CI-095 and CI-090 state (`application/invariant-parity-measurement-2026-10-13.md:399,404`).
- The minimum's tax rates agree with `scenarios/tax.md:226–239`. The new cast rows agree with their Given facts (`scenarios/cast.md:187–192`); PF-09 explicitly has the Mcf exception and PF-10 takes that same meter. BB-27 explicitly overrides the usual route day. No conflicting reuse of a new cast customer was found.
- SCN-0167/0168 disclose that allocation across occupants or vacancy is provisional under SCN-0155. The final-bill workflow and billing-failure inventory motivate correcting an estimated final bill but do not themselves decide day allocation: GBM `application/configurable-rules/workflows/final-bill-generation.md`, exception 1, and `knowledge/24-billing-failures-index.md:195`. That Open concerns who pays for gas and appropriately remains with Kyle; no further question is needed merely to choose the vacancy report's shape.
- Further credits from deposit-paid final bills remain deposit refunds under Kyle's November 3 answer 17 and SCN-0029. The original deposit application and refund remain history; neither new example requires holding the original refund or recreating a held deposit. SCN-0168's interest arithmetic matches SCN-0043/0044. The current schema validates the accrual record and held principal, while the core decides the legal calculation (`sql/tu.sql:36425–36480,36566`). A partial application alone would not stop interest on a retained remainder; the example avoids that issue by returning the remainder the same day.
- Gulf Plains' estimation-catch-up cause is represented with no billing cap (`sql/tu.sql:23905,24366–24367`); applying it and the utility's 20-day due-date policy is still core behavior. Correction at the original gas-cost month and original tax period agrees with SCN-0133 and the family convention. No unpaid prior penalty is introduced in SCN-0164 or SCN-0168, unlike the late-payment situation tested in SCN-0033.
- The cited law supports estimated-bill marking, the six-month actual-read requirement, the second unsuccessful access month's postcard, prompt deposit return net of unpaid bills, and stopping interest upon return or credit. The disconnection restriction has the stated exceptions; the departed GP-12 has no ongoing service to disconnect. These match the regulated, unincorporated residential facts here. The timely-but-invalid card interpretation is the qualification in finding 4. [16 TAC §7.45, introductory scope and (4)(E)(vii), (5)(C)(iv), (5)(F)(i), (6)(B)(viii), (6)(C)](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-45).
- No table or column identifiers appear in the new scenario prose. Invariant identifiers and cross-references serve as sources rather than customer-facing schema terminology. Beyond finding 9, the main remaining coverage concern is already the existing negative-usage catch-up/pricing Open in SCN-0141; these additions should not silently settle it. No new Open was found that an existing ruling fully answers.
