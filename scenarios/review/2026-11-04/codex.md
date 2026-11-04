The scenarios are not yet ready to become acceptance tests. The review found **7 must-fix issues, 7 coverage gaps and 2 notes**. Worked monetary arithmetic, elapsed-day counts and aging totals recompute correctly.

1. **SCN-0036 — must fix: delegation is not permission for uncapped billing.**  
   Cases (b) and (c) derive unlimited backbilling and collection from the unprotected Texas row. Patch -18 instead delegates to the utility’s tariff and refuses evaluation without one. Gulf Plains has no applicable tariff in the Given. Ordinary limitations law also still applies.  
   **Evidence:** `sql/v5.4.2-18-backbilling-rule-terms.sql`, residual R10.  
   **Fix:** Expect refusal without a tariff. Supply explicit tariff and limitations rules before asserting the $4,350 charge or collection eligibility.

2. **SCN-0041(b) — must fix: the migrated test date is after go-live.**  
   Gulf Plains went live January 15, 2026. A March 10 date-only test cannot be migrated history: migrated tests must predate or coincide with cutover. The fixture fails before evaluation.  
   **Evidence:** `cast.md` §3; patch -12, cutover checks; `application/a2-rules-for-the-core.md` §9.1.  
   **Fix:** Use a valid migrated date, such as January 10. January then straddles the window, February–June total **$19.60**, and a fresh approval remains required.

3. **SCN-0034 — must fix: a missing payment date does not establish lateness.**  
   The final assertion says a check without the customer’s date is late. Patch -19 requires an effective payment date and its method for a posted payment; it provides no fallback to the recording date.  
   **Evidence:** patch -19, CI-058 and payment-date constraints; `cast.md` §2, postmark policy.  
   **Fix:** Refuse posting or leave intake unresolved until the date and method are supplied.

4. **SCN-0008 and SCN-0047(a) — must fix: the November penalty precedes the due date.**  
   The inherited November 15 bill is due November 30 under Bluebonnet’s fifteen-day term. It cannot generate a late penalty on November 20. March and July penalties also need their underlying bills identified.  
   **Evidence:** SCN-0007 When; SCN-0008 Given; `cast.md` §2.  
   **Fix:** Associate November 20 with an earlier bill, or move the penalty into December and update dependent facts.

5. **SCN-0011(b) — must fix: the retrospective $60 refund is not ruled.**  
   Kyle’s answer 16 establishes $100 without DOB evidence. It does not establish an automatic partial refund when evidence arrives later. The cast also says Pecan Flat makes no refund while service continues.  
   **Evidence:** Kyle’s November 3 answer 16; `cast.md` §1.  
   **Fix:** Ask whether later proof triggers a return and when, or explicitly invent a tariff provision authorizing it.

6. **SCN-0033 — must fix: preserving age is treated as preserving the due date.**  
   Answer 10 preserves aging and gives increases a new due date. It does not expressly preserve the original amount’s due date or require penalty reversal and reassessment. Those assumptions determine the expected penalties.  
   **Evidence:** Kyle’s November 3 answers 3 and 10; SCN-0024.  
   **Fix:** Make both due-date retention and reassessment provisional questions. Keep the amounts as conditional examples until settled.

7. **SCN-0040 — must fix: the corroboration rule is too narrow.**  
   The scenario requires the predecessor to come out when the replacement goes in. Its cited implementation permits removal **on or before** installation, provided the predecessor served into the window and passes the evidence fence.  
   **Evidence:** `application/a2-rules-for-the-core.md` §4.3, conditions 3 and 5.  
   **Fix:** Correct the condition and add a gap-between-meters variant, retaining the acknowledged provisional status.

8. **SCN-0010 / SCN-0042 — should add: permitted top-up and combined cap.**  
   Test usage reaching twice the estimate, with $100 held against a $160 total cap: the additional amount cannot exceed **$60**. Include below-threshold use and an excessive top-up.  
   **Evidence:** Kyle’s answer 15; deposit core rules §§2.2–2.3.

9. **SCN-0031 / SCN-0023 — should add: payment priority across bills.**  
   Existing variants put gas and backbilling on one bill. Add older protected backbilling of $28, newer gas of $42 and a $28 payment. Ask whether disconnectable-first overrides oldest-first across bills, then assert allocation, aging and disconnectable balance together.  
   **Evidence:** Kyle’s November 3 answer 12; October 15 K-05/R-06; patch -22 W1.

10. **SCN-0027 — should add: paid-bill correction.**  
    Both fixtures are unpaid. Add the cash-paid credit-and-rebill branch, preserving the receipt and preventing duplicate application. Assert the following bill’s starting read and the unchanged 9.5 Mcf total.  
    **Evidence:** Kyle’s answer 7 and flag 3; October 15 R-05.

11. **SCN-0037 / SCN-0040 — should add: one meter across different premises.**  
    Neither tests a meter moving between premises with different applicable rules. Add two deployments and assert each bill uses its own customer, premise and rule, with both deployments included in the candidate period set.  
    **Evidence:** R-37(b); backbilling core rules §§5.1, 6.1 and 13.3.

12. **SCN-0039 — should add: predecessor-record hold.**  
    Only the legacy-record hold is tested. Add predecessor records unavailable, including acquisition date and the supervisor, artifact and counsel-referral requirements for unrecoverable closure.  
    **Evidence:** R-37(c); backbilling core rules §10.

13. **SCN-0042–0044 / SCN-0007 — should add: regulated refund eligibility.**  
    Add Gulf Plains cases for eleven versus twelve qualifying bills, current delinquency and unevaluable eligibility inputs. Municipal anniversary-based eligibility cannot substitute for these.  
    **Evidence:** deposit core rules §§5.2–5.4, DG3 and B14; Kyle’s November 3 flag 1.

14. **SCN-0001 and cast — should add: newly settled billing branches.**  
    Add read-date rate selection, negative gas-cost adjustment, outside-city tax exclusion and safety-fee cases. For the fee, distinguish state agencies and billing before versus after remittance. Include a volume-billed line with a non-unit multiplier and its raw quantity.  
    **Evidence:** Kyle’s answers 1, 2 and 4; November 4 gas-unit decision.

15. **SCN-0046 / SCN-0047(b) — note: distinguish return due from settlement.**  
    SCN-0046 records $250 returned January 5; its inherited scenario establishes only that return became due then. SCN-0047 relies on withdrawing that decision before crediting.  
    **Evidence:** SCN-0007, 0046 and 0047; deposit core rules §§4 and 5.4.  
    **Fix:** Specify separate decision and settlement dates, and explicitly state that SCN-0047 has not settled before withdrawal.

16. **SCN-0048 — note: official text supports municipal reach and a combined exclusion.**  
    Section 182.001 includes publicly operated gas utilities. Section 182.005 joins its conditions with “and”; independent exclusions are not supported by the text. November 16 → December 11 is correct. [Texas Legislature, Utilities Code chapter 182](https://tcss.legis.texas.gov/resources/UT/htm/UT.182.htm).  
    **Fix:** Cite the official text, distinguish verification from pending Kyle acceptance, retain the cutoff-interaction question, and add the single-bill request branch.

The full review is saved to [codex.md](/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/review/2026-11-04/codex.md). No other file was changed.