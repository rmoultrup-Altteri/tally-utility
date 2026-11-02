# Opus review: scenarios SCN-0001 to SCN-0026 (2026-11-02)

Read-only. Every worked bill, ledger, deposit and aging table was recomputed. **All figures are right** (SCN-0001 $64.61 and $65.18; the reference bill $65.83; SCN-0002 $52.61; SCN-0003 $541.97; SCN-0004 $55.83; SCN-0005 $54.34, $45.85, −$8.49; SCN-0006 $48.20, +$2.35; SCN-0009 $108.63; SCN-0012 $0.49 and $0.51; SCN-0013/14/16 $26.80, $22.50, $5.40, $21.40, $2.10; SCN-0020 07:00 CDT; SCN-0023 $138.55 at 17/47/78 days; SCN-0024 $130.06 at 5/41/102 days, checked against `receivables_aging_as_of`). Tax on rounded vs unrounded lines gives the same cent in every bill here, so that question is never exercised (see N3).

The findings are about rules, sources and test-readiness. They are ranked, most important first.

---

## Must fix

**M1. SCN-0005 (and SCN-0006, which reuses its facts): a meter-test finding is corrected by void and rebill. The sources say a meter error goes the other way.**
- What it says: "On Nov 20 a meter test shows the September read should have been 4.0 Mcf", then the bill is voided and reissued.
- Evidence: a2-rules §12 opening (R-33): "a bill computed wrong is not the same as a meter that measured wrong. A meter error is corrected by an adjustment on a later bill, not by voiding and reissuing." A meter test is the trigger for the backbilling path (`meter_error`, test-anchored, §2.2–2.4). Bluebonnet is a city system, and SCN-0019(a) says that same correction is **refused** at Bluebonnet today. So SCN-0005 and SCN-0019 contradict each other on the same facts.
- Fix: make the September error a bill computed wrong (a keying or transcription error found on review, or a wrong read entered), not a meter test. SCN-0005's rule (a closed period never reopens) is unaffected.

**M2. SCN-0006: a "current" rate basis on a gas correction is shown as accepted. Kyle already ruled it must be refused, so the Open question is already answered.**
- What it says: Current gives $48.20, "recorded as current"; Open asks Kyle whether current is ever lawful for a misread.
- Evidence: GBM `application/configurable-rules/de-review-answers.md` DE-3 (Kyle, 2026-06-12): "`correction_rate_mode=current` needs a hard enforcement guard on gas correction runs … gas corrections must rate at the historical period; `current` is selectable for non-gas only" (action item 3). Kyle 10-14 Q6 (rulings digest §6) agrees: the platform keeps every past gas-cost factor "so a rebill uses the one in effect then". DE-3 was never written into canonical invariants (CI-007 still lists `current` without a gas carve-out), and the scenarios' source inventory doesn't cite it.
- Fix: for gas, Then = "Current: refused". Keep the $48.20 bill only as a non-gas illustration, or drop it. Ask Ryan whether DE-3 should become a recorded rule (its absence from the invariants is a gap in its own right).

**M3. SCN-0021: Texas's postmark rule for whether a payment is on time is applied to Bluebonnet, a city system.**
- What it says: "For on-time questions the customer's date is Sep 27 [postmark]", citing Kyle 06-12.
- Evidence: Kyle's 06-12 answer is "**Texas** timeliness keys off postmark date" (de-review-answers.md, payment-policy-gaps). That is a state customer-service rule, which does not bind city systems (standing rule; K-07). -19's own vocabulary comment says the method is configuration: "Which method a jurisdiction or channel uses is tariff/operations configuration … `postmark`: (states that treat the postmark as the timely date)". Brenham's tariff (cast-sources §1) says nothing about postmarks.
- Fix: add to the cast "Bluebonnet treats the postmark as the payment date (**invented**)", or make it Open. Separately, **Oct 3, 2026 is a Saturday**: under Bluebonnet's own rule (a due date on a weekend moves to the next workday) the September bill is due **Mon Oct 5**. The outcome doesn't change, but a test computing the due date will get Oct 5.

**M4. SCN-0008 and the cast: one clause of the Brenham deposit-refund rule is dropped, and it may decide SCN-0008.**
- Evidence: cast-sources §1, Deposits: "refunded as a bill credit after 12 months if … no more than 2 late penalties. **It is also refunded if no bill is past due.**" `cast.md` §2 leaves the second sentence out.
- Effect: in SCN-0008, BB-02 has three late penalties but every bill is paid, so no bill is past due. On a plain reading of that clause the deposit **does** fall due. The scenario says it is kept.
- Fix: add the clause to the cast, then either rule on how it reads (a second way to qualify, or part of the first condition) or put it in SCN-0008's Open for Kyle.

**M5. SCN-0022: the close snapshot ages the balance at the wrong date.**
- What it says: "the aging buckets as they stood on Oct 10."
- Evidence: -22 header, "The close snapshot (S)": aging is "at the period's last day by the edges on the tenant's row at that instant". So aging is at **Sep 30**, as recorded at the close instant (Oct 10).
- Fix: "the aging as of Sep 30, as recorded when the period closed on Oct 10" ($54.34 in 0–30 days).

**M6. SCN-0025: the GL mapping rule is misstated. The precedence is weighted, not "most specific".**
- What it says: "the most specific mapping in force wins; two equally specific ones are an error"; "refused as a tie".
- Evidence: `gl_mapping_as_of` comment (-22 ~L1610): "the highest precedence wins: charge (8), customer class (4), territory (2), tax jurisdiction (1), summed". Two different keys can never tie. Only the **same key** with overlapping dates collides, and the `gl_account_mappings_no_overlap` exclusion refuses it when it is entered. Under the weights, a (distribution, residential, any, any) row beats a (distribution, any, rural, city) row, even though the second names more parts.
- Fix: restate the rule as written. Call the last bullet "refused: the same key overlaps in time". Add one row where the weights decide (class against territory plus tax jurisdiction). Also **give the relight fee a date**: the mapping is looked up at the line's date, so a mapping effective Nov 1 exports the fee only if the fee is dated Nov 1 or later.

**M7. SCN-0026(c): reversing the recovery leaves the $50 payment standing. The Then doesn't say so.**
- Arithmetic: write-off −120, recovery +50, payment −50, recovery reversed −50. BB-02's balance is now **−$50.00, a $50 credit**. The scenario says only "the full $120 is written off again", which a reader takes to mean the account is back where it was.
- Fix: state the balance (−$50.00, a credit owed to BB-02), or change the facts so the payment is undone too, for example a payment posted to the wrong customer and reversed with its recovery.

**M8. SCN-0013 and SCN-0016 (and SCN-0014's Given): a supervisor's approval is required, and the scenarios leave it out.**
- Evidence: a2-rules §9.1 (R-36). A charge to the customer whose governing prior test is weak ("none at all", or a migrated date only) needs a supervisor's approval when the six-month reach falls before the utility's cutover date, **or the utility has no cutover date**. The approver must not be the case's opener (§9.2). The case cannot freeze without it (§11.2.4). The cast gives Gulf Plains no cutover date, and SCN-0013 and SCN-0016 have no prior test, so both are gated. That is G1's exact shape.
- Fix: give Gulf Plains a cutover date in the cast. Add to the Then: "approval required (a supervisor, not the opener) before the $26.80 can post", or choose a cutover so that the gate lapses, and say so. SCN-0014: state that the Mar 10 test was recorded with readings. If it was a migrated date-only row, that test is weak too and the case is gated.

**M9. SCN-0001 (and every Bluebonnet and Pecan Flat bill): a gas usage line cannot be issued with only quantity, unit and rate.**
- Evidence: -21 `invoice_line_missing_arithmetic` (L458–475) refuses a gas usage line at issue unless it also carries `gas_meter_factor`, `gas_ccf_used`, `gas_therms_billed` and `gas_commodity_rate`. The 10-14 ruling (digest §6) says the commodity rate is the **usage line's** figure. Bluebonnet bills by the Mcf with no therm conversion, and it shows the commodity charge as its **own line**. SCN-0001's Then ("quantity, unit and rate") would fail the issuance check, and it doesn't say which line is the "usage line".
- Fix: either give the factor, Ccf, therms and commodity rate on the distribution line (for example factor 1.000, 60 Ccf, a stated therms figure, commodity $5.35), or open a question for Ryan and Kyle: how does an Mcf-billed city with a separate commodity line meet the line-arithmetic rule? This affects every worked bill in the folder.

**M10. SCN-0018: the evidence doesn't fit the rule, and part (a) fails for two reasons at once.**
- Evidence: a2-rules §3.3 requires "**exactly one** evidence reference of one of three kinds" (a service order on this meter, the meter's removal for tampering, or a field report). A photo is not one of the kinds, and "a photo and the field report" is two references.
- Fix: (b) "with the field report as its evidence". Split (a) into a clerk with evidence (refused: not a supervisor) and a supervisor with none (refused: no evidence). As written, a test cannot tell which rule refused it.

**M11. SCN-0020(c): two refusal reasons again.**
- On Oct 10, October has not ended anywhere, as well as September still being open. Move (c) to Nov 2, or later, so that "September must close first" is the only reason.

---

## Should add

**A1. Cancel-rebill: a correction that charges more.** a2-rules §12: when a reissue charges more for days already billed, it is refused unless it is a correction whose cause is a rate misapplication, with usage exactly matching. A downward reissue is never gated (residual R3). Every scenario in the family goes down. Add:
- (a) at Gulf Plains, a rate applied wrongly, units the same: accepted;
- (b) a misread corrected **upward** by void and rebill: refused, because it has to be an adjustment;
- (c) the same upward correction at Bluebonnet: refused, because no rule is found (it ties to SCN-0019).

This is the commonest real correction at a small system.

**A2. Rebill of a bill whose period straddles a rate change, after its month has closed.** Void and rebill SCN-0001's October bill once September and October are closed. On the historical basis, the split by days must be applied again from the recorded policy. The correction posts into the open month. That is the closed-period and rate-change interaction the brief names.

**A3. A deposit applied to a final bill that is later voided** (the brief's own example). Take SCN-0009, then find the final read wrong. What happens to the $41.37 application and the $108.63 refund already paid? The cash family is pending, so write it with an Open, but write it.

**A4. Pecan Flat at move-out.** The cast says Pecan Flat's deposit refund is "**none (invented)**". Read literally, the deposit is never returned. The standing rule that a city with no tariff row has no rule would leave it held forever. Ryan needs to decide whether "none" means no interest, or no refund rule on record (in which case is refusing correct?). Add a move-out scenario for PF-01, with the question open.

**A5. SCN-0019's refund side.** The city-system refusal ("unknown law is not permission") is written for a charge. For a **fast** meter at Bluebonnet with no rule on record, the refusal holds back money owed **to** the customer. Add part (c), or an Open, on whether the refusal should block a refund.

**A6. Backbilling cases a small system meets at onboarding:**
- (a) A fast meter whose six-month window reaches before go-live. The pre-go-live stretch is held under `legacy_records_not_loaded`, and the case cannot freeze while any in-window day is uncovered (a2-rules §10.2, §11.3; H7, H2).
- (b) A meter that has had two customers in the window. The case follows the meter, and each period is judged under its own customer's class (§5.1, §6.1, R-37(b)).

**A7. The other backbilling causes and classes.** A non-registering meter has a three-month window. Its anchor, test date or discovery date, is disagreement D1, pending Kyle (§2.4, §1.1). A large-volume customer outside the protected class is uncapped, through a delegated row (§1.1). Neither is exercised.

**A8. Late penalties for customers aged 60 or over at a city system.** The rulings digest §4 (10-18, for Kyle) says Texas Utilities Code §182.002 (for customers 60 or over: due 25 days after issue, no late fee) **binds city gas systems**. PF-02 is 67. At Bluebonnet, a 60+ customer's "late" payment on day 20 would carry no penalty, and so would not count toward SCN-0008's limit. Write it as pending Kyle.

**A9. Deposits, the other branches of Bluebonnet's rule:**
- a returned check, or a disconnect notice, disqualifies the refund;
- the $250 bill credit is larger than the next bill, so what is left over joins the customer's single credit balance (K-11, 10-30).

SCN-0007 and SCN-0008 test only the late-penalty count.

**A10. Periods and aging, from -22's stated behaviour:**
- an account in credit ages as one row with no bucket;
- a ledger entry dated before the first period is accepted (onboarding history);
- the latest open period, mistyped, is withdrawn and then created again correctly.

**A11. Across families: a backbilled charge that can never ground a disconnection still sits in the aging buckets** (SCN-0013, enforceable scope "never"). Aging carries no marker for it. Add it when collections (-26) mirrors. Until then, put an Open on SCN-0013 that aging, and so collections, cannot tell this charge apart.

---

## Notes

**N1. The cancel-rebill and aging dates disagree.** SCN-0005 posts the September bill on **Sep 18**. SCN-0023 dates it **Sep 15**, and SCN-0024 combines the two. The ages change (47 days against 44), though not the buckets. Use one date.

**N2. Tariff effective dates are missing from the cast.** Bluebonnet's tariff is modelled on one effective Oct 1, 2026, yet SCN-0007 takes a deposit on Jan 5, 2026. Pecan Flat's source ordinance is dated Feb 11, 2026, and SCN-0010's first cut-off is Feb 10, 2026. A test needs each tariff record dated in force before its first use. Also, "commodity $5.35" before Oct 1 is invented (the source sheet is effective 10/1/2026) and is not marked.

- Also not marked "(invented)": the July and August bills and the $100 payment (SCN-0023), the $41.37 final bill (SCN-0009), calendar-month accounting periods (periods common section), Gulf Plains' calendar-month bills, and the meter count (the decision log says about 500 for the small system; the cast says 400).

**N3. Test-readiness of the Givens:**
- Tax base: rounded or unrounded lines. No bill here changes cent between the two, so no test pins the rule. Add one bill where they differ, or state the rule in the README.
- SCN-0008's "Apr 5, 2027" assumes monthly anniversary checks. The late penalties have no dates, so a rolling-window date cannot be computed.
- SCN-0013 and SCN-0017 should say June is not yet billed. The period set takes issued bills overlapping the window, up to the anchor.
- SCN-0009 should give the deposit's posting date, and state that the twelve-month refund has not already fallen due.
