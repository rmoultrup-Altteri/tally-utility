# Scenarios round 6 — Codex review

2026-11-25. Reviewed SCN-0117–0129, the associated cast, and the second-pass changes in `177b9bf` to tax and periods/aging. Static review against the mirrored SQL and application contracts; no database tests run. Findings are ranked within each section. P2 means a behavioral error or material coverage gap; P3 means a narrower wording correction. Only this report was written.

## PRIMARY — unmatched cash and pledges

### 1. P2 — SCN-0117 / SCN-0121: missing pending-payment and reconciliation cases let held money disappear from the operator surface

**Claim / gap:** The examples move directly from a receipt to a posted payment, or immediately from a reversal to a return. SCN-0121 correctly shows the receipt holding $0 after reversal, but never asserts where the $65.83 must be reported while the return is outstanding. Neither example covers a resolution left pending beyond a day.

**Evidence:** `scenarios/unmatched-cash-and-pledges.md:130`–140; `application/APPLICATION-CONTRACTS.md:481`–485 and `:493`–495. AC-49 requires reconciliation to add money owed back to receipts to money currently held, at the same coordinates; the close snapshot has no suspense line (L4). AC-53 explicitly requires surfacing pending payments past a day. The receipt reader deducts nonvoid payments even before they post (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql:1407`–1411), and AC-53 identifies the resulting gap in aging/returns lists.

**Suggested fix:** Add two worked variants: (1) leave the Dec 7 reversal unreturned overnight and assert $0 held + $65.83 owed back = $65.83 to reconcile, with an operator item; (2) reserve the receipt in a pending payment, leave it unposted past a day, and assert the pending work item even though the receipt no longer appears as holding money. Include the close reconciliation, explicitly supplied by the core until L4 is built. This tests CI-053/CI-056 at their actual failure boundaries.

### 2. P2 — SCN-0127: L6 is named but its required core refusal is missing

**Claim / gap:** The status acknowledges other credits are not covered, but the Then section only exercises traced overpayment/reissue credits and an agency-paid deposit. It never tests the action that would erase the agency's ownership.

**Evidence:** `scenarios/unmatched-cash-and-pledges.md:246`–257. L6 says the core **must not move agency money into a credit without a typed source** (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql:92`–97; `application/APPLICATION-CONTRACTS.md:490`–491). The trace returns no agency for other credit origins (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql:590`–600), after which the refund check treats it as the customer's money (`:883`–893).

**Suggested fix:** Add a variant where an operator tries to move Coastal Prairie's $12.60 into an ordinary adjustment/transfer credit. The **core refuses**, preserving the agency-linked payment or supported credit. State that the database cannot enforce the agency refund destination after that unsupported conversion. Merely naming L6 does not specify the required protective behavior.

### 3. P2 — SCN-0126 / SCN-0128: “any payment names it” overstates the recorded-in-error refusal

**Claim:** “A pledge cannot be recorded in error once a payment names it” (SCN-0126 Rule); SCN-0128 similarly uses “no payment names it yet” as the correction precondition.

**Evidence:** `scenarios/unmatched-cash-and-pledges.md:229`, `:239`, `:273`. The actual guard excludes voided payments: it refuses only when a linked payment has a status other than voided (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql:1285`–1291; the explicit contract comment is at `:1320`). A pending payment blocks correction; a voided one does not. The existing $50 posted-then-reversed example is correctly refused.

**Suggested fix:** Say “while any payment that has not been voided names it.” Add a pending payment voided before posting, followed by an accepted recorded-in-error correction. Keep the reversed-payment refusal to distinguish a payment that never posted from real money later reversed.

### 4. P2 — SCN-0121 / SCN-0122: the AC-51 late bank notification and mixed-return paths are absent

**Claim / gap:** SCN-0122 cites AC-51 but only tests a straightforward whole-check bounce. Its rule says bank-taken money never returns to the receipt; that needs qualification for AC-51's bookkeeping route when the bank notification arrives after a payment ended as misposted.

**Evidence:** `scenarios/unmatched-cash-and-pledges.md:146`–162; `application/APPLICATION-CONTRACTS.md:487`–488. A bank code added after a receipt's payment ended reversed is refused, with the prescribed recovery path in `sql/v5.4.2-24-unmatched-cash-and-pledges.sql:762`–765. A payment ending bounced can nevertheless return a separately misposted share (`:1097`–1123). Neither guard has a worked example here.

**Suggested fix:** Add (a) a reversal initially treated as misposting, followed by a late bank notification: adding the code to the ended payment is refused; return the money to the receipt, then record the bank take-back there; and (b) a split such as $20 misposted and $55.50 taken by the bank from a $75.50 payment: exactly $20 returns, with a smaller or larger return refused. Explain that bank-taken money is never made available for another customer, even when the correction route briefly records it back in suspense.

### 5. P2 — SCN-0124: the billing-period end is asserted without a period fixture, and the contract conclusion contradicts its Open

**Claim:** The Sep 11 pledge is assigned to “the Sep 5 bill's period,” ending around Oct 4; the Then says the agreement makes the amount not delinquent until Oct 25, but the Open asks whether that same agreement protects it after Oct 5.

**Evidence:** `scenarios/unmatched-cash-and-pledges.md:190`–203. SCN-0081 calls the Sep 5 invoice the **August** bill (`scenarios/cash.md:21`); issuing monthly around the 5th does not define the legal billing period. The supplied law says the period in which the provider receives the written notification (`application/wave3-build-2026-10-18/sources/law-text/tac7-460.txt:33`–37). The design describes the contractual term conditionally—non-delinquent **if paid within** 45 days (`application/wave2-build-2026-10-15/v5.4.2-24-design.md:19`)—and leaves the statutory and contractual protection to the applicable rule (`:113`).

**Suggested fix:** Supply exact invented billing-period dates and distinguish the service period, issue date, and period used for the protection rule. Until the interpretation is confirmed, do not assert Oct 4 as the statutory protection endpoint. Make the contract-versus-statute question a precise Open about protection before payment and the consequence of failure to pay, and label the corresponding expected behavior provisional. The pay-by calculation, Oct 25, is correct and need not change. Separately narrow the verbal-pledge Open: the cited statutory provision already requires writing; any additional tariff/contract protection for a phone pledge is the question to ask.

### 6. P3 — SCN-0126: the post-lapse state should be explicit

**Claim:** “From Oct 26 the pledge reads overdue,” immediately followed by recording a lapse dated Oct 26.

**Evidence:** `scenarios/unmatched-cash-and-pledges.md:236`. The reader returns the ending event ahead of overdue (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql:1475`–1480), and the open list excludes lapsed pledges (`:1501`). Thus, after the lapse is recorded and visible at the read instant, the state is lapsed, not overdue. Late full payment does outrank the lapse, as (b) correctly states.

**Suggested fix:** State the sequence explicitly: overdue before the lapse is recorded; lapsed afterward, removed from the open list with $37.40 outstanding; paid after the Nov 2 payment, with the lapse retained in history. This prevents a test from asserting overdue after the event.

### 7. P3 — SCN-0123: the penalty sentence specifies opposite actions

**Claim:** “BB-01's penalty … is the core's to reverse, as in SCN-0117,” followed by “the penalty stands.”

**Evidence:** `scenarios/unmatched-cash-and-pledges.md:179`; the stated due date is Dec 1 (`scenarios/cash.md:8`), and this payment's customer date is Dec 2. SCN-0117's reversal depends on the earlier Nov 28 postmark, which is absent here.

**Suggested fix:** Remove the reversal instruction. Say that the penalty stands because payment was late; resolving an unidentified receipt alone does not justify reversing it. The outstanding balance remains $6.59 after the $65.83 payment, on these facts.

### Guard and consistency cross-check

References below abbreviate `sql/v5.4.2-24-unmatched-cash-and-pledges.sql` as **-24**. These are supporting checks, not additional findings.

| Scenario | Result and evidence |
|---|---|
| SCN-0117 | No-guess decision correctly assigned to core. Reason/operator requirement: -24:538–542; payment/customer dates: :828–836; instrument preservation: :838–843 and :748–753. Closing November does not prevent a December resolution of an already recorded receipt. Clarify in a future variant that the receipt itself was recorded before the close: its received date is frozen (:1664–1665). |
| SCN-0118 | Split and overspend refusals agree with cap at every date (-24:621–638). Landlord classification is explicit at :214–215. $75.50 + $45.30 = $120.80; 10% of $45.30 = $4.53. |
| SCN-0119 | Full undo followed by a second undo is refused by cumulative cap (:1181–1185); undo of undo refused at :1171; escheat jurisdiction/reference required at :440. No automatic retention disposal is claimed. The unspecified annual report must remain conditional on the dormancy Open; 180-day retention alone does not establish statutory reportability. |
| SCN-0120 | Aged list requires a service level, lists candidates, and uses age strictly greater than the level (-24:1432–1462). The disconnection effects are correctly identified as core/collections rules, not a new -24 SQL refusal. L1's unidentified-customer gap is covered. |
| SCN-0121 | Receipt must first receive its return; dated cap :621–638. Exact return :1116–1123, last underlying money date :1152–1156; one return per payment :453–454. Refund-to-wrong-customer debt matches AC-53 (:493–494). See findings 1 and 4 for gaps. |
| SCN-0122 | The stated whole bounce leaves no misposted share to return (:1097–1123); bank disposition over remaining money hits the cap. Amounts and fees agree with SCN-0084. Preserve that family's qualification that reopened balances exclude any unresolved ordinary late penalty (`scenarios/cash.md:11`, :100–101). |
| SCN-0123 | Provider deduplication is scoped by tenant, source and ID (:701–709); a resolution carries no provider ID (:538–542). Different processors remain distinct. See finding 7. |
| SCN-0124 | App-supplied agreement/pay-by refused (:1208–1211); date computed from pledge date (:1237–1240). Missing protective law data is L2 (:84–85), not a SQL prohibition on storing the pledge. See finding 5. |
| SCN-0125 | Agency/customer agreement :862–866; bill restriction :870–874; agency required :532–535. Multiple pledges have no customer/agency uniqueness (:461–491). Paid amount comes from ledger receipts (:1252–1259), not simply a status label: the normal pending example assumes no posting entry, as -23 explicitly explains at `sql/v5.4.2-23-cash-reversals-positions-application.sql:1779`–1790. |
| SCN-0126 | Full-payment refusal :1293–1297; lapse requires a deadline and must wait until it passed everywhere :1299–1313; only one ending :506. Late payment is not refused for a lapse/withdrawal: the payment guard checks recorded-in-error only (:875–879). See findings 3 and 6. |
| SCN-0127 | No pledge-amount cap in payment guard; refund destination :883–893; trace through overpayment and both reissues :590–597. Deposit limitation matches L5 and AC-52. See finding 2 for L6. |
| SCN-0128 | Active agency required for new pledge :1220–1224 and new agreement :273 onward; payment guard has no active-agency requirement. No agreement accepted :1237–1240; lapse refused :1300–1303; no-agreement state :1478 and first in open list :1502. See finding 3. |
| SCN-0129 | Agency preserved from receipt :845–848. No pledge required for agency payment (:534–535). $75.50 + $40.00 + $64.80 = $180.30. L3 is correctly assigned to intake/core. |

Dates checked: Nov 27 to Dec 3 = 6 days; to Dec 7 = 10; to Dec 8 = 11. Dec 2 to May 31, 2027 = 180 days; to Jun 1 = 181. Sep 10 + 45 = Sunday Oct 25; Sep 14 + 30 = Wednesday Oct 14; Dec 8 + 30 = Thursday Jan 7, 2027. The supplied weekday labels and these boundary calculations agree. The lockbox arithmetic ($3,846.83 + $65.83), $72.42 penalty-inclusive balance, and $12.60 agency surplus agree.

Cast additions agree with the examples: PF-06/PF-07 are residential rentals with one landlord; BB-16 is an inside-city homeowner; agency windows and utility affiliations match. The scenario prose is predominantly plain language; the literal collections identifiers in SCN-0120/0124 status lines can be replaced by “aged held-money condition” and “agency-pledge condition” to follow `scenarios/README.md:32`'s no-column/table-name convention without losing their source citations.

## SECONDARY — tax second pass (`177b9bf`)

### 1. P2 — SCN-0109 / SCN-0115 follow-on: an overlapping district does not categorically prohibit the city's increase

**Claim:** “Had either still overlapped, the city could not have raised its rate.”

**Evidence:** `scenarios/tax.md:171`. This contradicts the automatic district reduction already acknowledged in the same file at `:380`. [Texas Tax Code §321.102(e)–(h)](https://tcss.legis.texas.gov/resources/TX/htm/TX.321.htm#321.102) provides a reduction mechanism, a debt exception, and exclusion of transit authorities from that mechanism. An overlapping hospital district is not, by its presence alone, proof that an increase is prohibited; debt and the other overlapping rates matter.

**Suggested fix:** Keep the invented Sep 30 terminations and the resulting 2% total. Replace the counterfactual with “If an overlap continued, check whether an eligible district's rate must be reduced or the increase cannot be implemented.” The future scenario should state the debt facts and distinguish a district reduction from the transit authority's exclusion; it should not infer an absolute ban merely from transit overlap if another reducible district is present.

### Other second-pass checks

- SCN-0115's revised taxes are arithmetically correct: $187.40 × 0.125% = $0.23425, four-decimal working amount $0.2343, cent amount $0.23 each; $202.39 + $0.46 = $202.85. BB-10's absence from those memberships and BB-14's residential exclusion agree with the cast.
- SCN-0109's $2.0% total after both terminations agrees with the revised cast. Its same-transaction timing explanation and SCN-0110's run-instant qualification agree with AC-47 (`application/APPLICATION-CONTRACTS.md:463`–470).
- SCN-0108's revised distinction between municipal tax and district tax is appropriately narrower. However, retain the tax-advisor question: [§321.3025](https://tcss.legis.texas.gov/resources/TX/htm/TX.321.htm#321.3025) establishes revenue treatment and preserves refund rights; it does not itself settle every possible duty to correct an overcharge. The sentence “not owed back by law unless …” should be read as an unconfirmed interpretation, not an independently established rule.
- SCN-0111's added place memberships, SCN-0113's loaded-place prerequisite, and SCN-0114's explicit omission of December bills remove ambiguities without changing the worked amounts.
- SCN-0049's added straddling-period explanation leaves $65.83 as an invented fixture conditional on an unresolved tax timing question. Its Jan 15 to Feb 28 age is correctly 44 days, in the 31–60 bucket; the credit remains unbucketed. No additional aging defect found in that edit.

No scenario or SQL changes made.
