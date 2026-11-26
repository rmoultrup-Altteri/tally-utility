Reviewed SCN-0155–0162 and the eight new cast entries against the local rulings, schema, parity record, related scenarios, and cited Texas rules. **Changes are needed before these become test specifications.** The arithmetic is correct for the stated Mcf quantities, but several setup and rule claims are inconsistent or unsupported. No repository files were changed.

In the findings below, **TU** means this repository and **GBM** means `/Users/ryanscomputer/code/gas-billing-memory`.

1. **Blocking — SCN-0162, line 666: PF-08’s readings do not establish the billed volumes under the cast.**

   Pecan Flat’s residential meters normally read in Ccf; PF-01 is the explicit Mcf exception. PF-08’s new cast row specifies no exception. Consequently, subtracting 2,038.0 from 2,046.0 does not establish **8.0 Mcf**. With Ccf readings it would be **0.8 Mcf**, and the minimum bill would matter.

   **Evidence:** [scenario:666](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:666); [cast meter conventions:142](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/cast.md:142); [PF-08:186](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/cast.md:186).

   **Fix:** Explicitly give PF-08 a meter reading in Mcf to a tenth, both in its cast row and the Given. That preserves the intended $120.80 and $39.26 bills.

2. **Blocking — SCN-0162, lines 663–673: “working the deposit’s disposition again” conflicts with the already-ruled final-bill correction.**

   SCN-0029 explicitly preserves the original deposit application and refund: the deposit does not reappear as held. SCN-0162 instead describes reopening the disposition and applying the deposit again. In part (b), “the deposit was applied in full” also contradicts the Given: **$39.26 was applied and $60.74 refunded**, not $100 applied.

   The resulting **$81.54** refund or debt is arithmetically correct, but the described money history is not.

   **Evidence:** [scenario:663](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:663); [SCN-0029 rule:131](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/deposits.md:131), [unchanged deposit history:149](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/deposits.md:149); GBM `application/kyle-decisions-2026-11-03-scenario-batch-1.md`, answer 17.

   **Fix:** Follow SCN-0029. Preserve the original deposit disposition and record the bill reversal, corrected charge, and resulting refund or receivable. Remove “reopening” from Status unless it names a genuinely additional requirement. Cite answer 17 for the deposit-derived refund.

3. **Blocking — SCN-0155, line 544: the correction says to refund money with a deposit remainder already refunded.**

   Part (a) pays out **$118.89**. Part (b) then says the additional **$3.59** is refunded “with the deposit’s remainder.” There is no remaining held deposit at that point. This wording can produce either a second refund of the remainder or an unauthorized delay of the first refund.

   **Evidence:** [initial refund:542](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:542); [correction:544](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:544); [SCN-0029:149](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/deposits.md:149).

   **Fix:** State that January produces a **separate $3.59 refund**. Total refunds are **$122.48**; the original $118.89 payout remains unchanged.

4. **Blocking — SCN-0159, lines 605/623, and SCN-0161, lines 647/657: the cited rulings do not settle the proposed estimation defaults.**

   R-11 establishes estimation as dated rule data. D-3 preserves history with the meter and address, including for diagnosing meter problems. R-10 establishes dated occupancy and installation history. None chooses:

   - the last three **actual-billed** months as the platform’s averaging default; or
   - a former occupant’s usage as the platform’s default estimate for a new occupant.

   These choices affect money. SCN-0159’s own alternatives total **$188.40 versus $188.32**, despite both billing 14.0 Mcf. They therefore exceed a record-format decision.

   **Evidence:** [SCN-0159 settlement:623](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:623); [SCN-0161 settlement:657](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:657); GBM `application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md:41,49`; GBM `application/kyle-decisions-2026-08-18-coda-items.md:155–163`; [Ryan’s triage rule:19](/Users/ryanscomputer/code/tally-utility-scenarios/application/DECISION-LOG.md:19).

   **Fix:** Either make these explicit, invented policies selected by Bluebonnet and Gulf Plains, or mark the proposed **platform defaults** provisional and ask Kyle in batch 8. Do not attribute the selected defaults to the cited rulings.

5. **Blocking — SCN-0156, line 554: emitting the customer charge without a reading is not built schema behavior.**

   CI-102 is graded **requires-app-discipline**. Its parity entry expressly assigns emitting the charge—and preventing a skipped reading from dropping it—to the core, with no schema mechanism.

   **Evidence:** [Status:554](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:554); [CI-102:411](/Users/ryanscomputer/code/tally-utility-scenarios/application/invariant-parity-measurement-2026-10-13.md:411).

   **Fix:** Say the fixed charge and estimation settings are represented, while producing the no-read bill is required core behavior. The **$14.75** November bill and **$149.24** December bill are correct.

6. **Blocking — SCN-0155, line 534: an estimated final reading is representable today; the cited invariant number is also wrong for the current TU register.**

   The schema separately represents an estimated reading, the purpose “final read,” and a service-transition reading identifying outgoing and incoming customers. The scenario conflates this representation with the unbuilt move-out orchestration and cross-customer allocation.

   In the current parity record, **CI-122** covers move-in/move-out billing events; **CI-123** covers meter change-outs. The cited GBM workflow uses the older numbering.

   **Evidence:** [Status:534](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:534); `sql/tu.sql:3545–3547,3578–3582,3594`; [CI-122/123:431](/Users/ryanscomputer/code/tally-utility-scenarios/application/invariant-parity-measurement-2026-10-13.md:431).

   **Fix:** Separate “can record an estimated final/service-transition reading” from “core must orchestrate the move-out and allocate consumption.” Cite current CI-122 and identify the GBM document’s numbering as historical.

7. **Blocking — SCN-0160, lines 629/637: the automatic back-dated-reading review is not established as built.**

   AC-21 and the database implement the estimate-streak calculation. They do not automatically raise the described review when an earlier actual reading arrives. The exception queue can hold an operator/core-raised exception, including an “other” reason with detail.

   Moreover, part (a) says the reading is validated and raises a review, without making clear whether review resolution precedes approval. AC-20 blocks approval while an exception remains open.

   **Evidence:** [Status:629](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:629); [Then:637](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:637); [AC-20/21:228](/Users/ryanscomputer/code/tally-utility-scenarios/application/APPLICATION-CONTRACTS.md:228); `sql/tu.sql:16902–16916,17094–17105,17205–17324`.

   **Fix:** Mark detection and raising the review as core behavior. Specify the sequence: enter reading, raise exception, reviewer resolves it with a recorded disposition, then approve. Keep the correctly stated streak result.

8. **Should-fix — SCN-0162(a), line 666: the December 4 payment introduces an omitted late penalty.**

   The November 30 final bill falls due December 1 under Pecan Flat’s tariff. After applying the $100 deposit, **$20.80** remains unpaid, so the stated tariff produces **$2.08** on December 2. The December 4 payment and December 9 correction therefore need to account for that penalty.

   **Evidence:** [Given:666](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:666); [Pecan Flat due date and penalty:22](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/cast.md:22); [SCN-0033:261](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/cancel-rebill.md:261); GBM `application/kyle-decisions-2026-11-05-scenario-batch-2.md`, answers 1–2.

   **Fix:** Move the $20.80 payment to December 1 if penalties are outside this test. Otherwise show the original penalty, payment allocation, and its reversal/reassessment after the corrected bill is fully covered by the deposit-derived money.

9. **Should-fix — SCN-0159, lines 607–623: the cast and scenario disagree about the averaging window, and volume rounding is implicit.**

   The cast says “last three billed months”; this scenario says the last three months billed on actual readings. The alternatives also round **2.4667 to 2.5 Mcf** before pricing, but neither the Rule nor the cast explicitly defines that rounding step. Meter display precision alone does not specify how a calculated estimate must be rounded.

   **Evidence:** [cast estimation method:138](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/cast.md:138); [scenario table:613](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:613); GBM `application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md:51–54`.

   **Fix:** Align the cast with the selected policy, subject to finding 4. Explicitly state four-decimal averaging followed by half-up rounding to the meter’s tenth before constructing the estimated reading and pricing usage. All table totals then reproduce correctly.

10. **Should-fix — SCN-0161, lines 649–655: GP-11’s March bill and alternative estimate cannot be constructed.**

    The When issues March and April bills for both customers, but GP-11 has no opening reading, March 1 reading, first-period consumption, or March bill expectation. “Estimated as in (a)” cannot supply GP-11’s own daily-average basis: the **3.8 Mcf over 19 days** belongs to GP-10.

    **Evidence:** [Given/When:649](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:649); [GP-11 expectation:655](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:655); [cast GP-11:185](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/cast.md:185).

    **Fix:** Supply GP-11’s readings and March bill, or narrow its When to April. For the alternative policy, give a supervisor-selected quantity and basis specific to GP-11, or explicitly stop the test at referral to the supervisor.

11. **Should-fix — SCN-0162, lines 664/673: the unresolved due-date and penalty outcome is written as unconditional behavior.**

    The Open correctly recognizes that Kyle’s “next regular bill” ruling does not directly resolve a departed customer’s case. Nevertheless, the Rule and Then prescribe January 1, an $8.15 penalty, and collections without marking that branch provisional. Status also omits the unbuilt handling of the newly disclosed amount’s due date.

    **Evidence:** [Rule:664](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:664); [Then/Open:673](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:673); [SCN-0089 Status:185](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/cash.md:185); GBM `application/kyle-decisions-2026-11-05-scenario-batch-2.md`, answer 2.

    **Fix:** Label this branch “proposed, pending batch 8.” Keep the question: it concerns when money becomes due and whether a penalty is allowed. The **$8.15** calculation is correct if that proposed rule is accepted.

12. **Should-fix — SCN-0155 and SCN-0160: two important test branches remain incomplete.**

    **SCN-0155, lines 543–548:** Only an overestimated departing customer is worked. The opposite direction would test an additional charge to the departed customer, a reduction for the incoming customer, and the unresolved post-closure due-date rule. A delayed actual arriving after the incoming customer has already received an estimated bill would also test whether both customers’ bills are corrected consistently.

    **SCN-0160, lines 634/639:** The failed-December-read branch asserts only the streak count. It does not specify the estimated reading, quantity, or bill after the late November actual has entered history—precisely where averaging-history selection and the billing starting point could diverge.

    **Evidence:** [SCN-0155:543](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:543); [SCN-0160:634](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/gas-cost-zones-and-reads.md:634); [CI-114:423](/Users/ryanscomputer/code/tally-utility-scenarios/application/invariant-parity-measurement-2026-10-13.md:423).

    **Fix:** Add the opposite-direction allocation case and complete the December-estimate branch with explicit history, quantity, starting reading, and amount. Keep any outcomes dependent on Kyle’s allocation decision provisional.

The remaining verification results were satisfactory:

- Recalculated dollar figures, including alternative bills, match four-decimal working math and half-up rounding per line **when the stated Mcf quantities and proposed policies are accepted**. Bluebonnet’s city-tax bases correctly sum rounded components.
- Stated weekdays and the 10/21-day December and 19-day February allocations are correct.
- SCN-0157 correctly preserves the tariff-authorized carried figure. Its refusal traces through SCN-0133 to a core responsibility, not an existing gas-cost database guard.
- SCN-0158 correctly separates the built non-estimated-reading streak behavior from the unresolved legal six-month question. The postcard timing, estimated-bill marking, and disconnection exception match §7.45. Section 7.5519 supplies no universal factor effective-date rule. [Railroad Commission rules, §§7.45 and 7.5519](https://www.rrc.texas.gov/media/tkfkdxtk/chapter7-all-effective-march-16-2026.pdf)
- The new customer identities do not conflict with existing customers. No table or column names appear in the eight scenarios’ narrative text.
- SCN-0155’s allocation Open and SCN-0162’s post-closure due-date Open properly remain questions for Kyle. Neither is answered merely by making the behavior configurable.