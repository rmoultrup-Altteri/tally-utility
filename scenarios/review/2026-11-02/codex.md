The worked arithmetic checks out: bill totals, reversals, deposit interest, backbilling sums, and aging allocations. The main problems are rule conflicts and incomplete test fixtures. No repository files were changed.

Source abbreviations below: **A2** = `application/a2-rules-for-the-core.md`; **Deposits** = `application/deposits-rules-for-the-core.md`; patch numbers identify the corresponding `sql/v5.4.2-NN-*.sql` files.

1. **SCN-0003 — must fix: a never-issued bill cannot anchor a correction.**  
   The replacement “names” the held, voided bill. Canonical CI-005 and patch **-10**, `invoice_snapshot_coordinate_error()`, require a correction’s predecessor to have actually been issued. **Fix:** issue a fresh ordinary bill after discarding the held one; distinguish any audit association from correction lineage. The $65.83 ledger result remains correct.

2. **SCN-0022 — must fix: snapshot aging uses the wrong date.**  
   “Aging buckets as they stood on Oct 10” should be **aging as of September 30, using information recorded by the October 10 close**. Patch **-22**, “The close snapshot” and `close_accounting_period()`, explicitly use the period’s last day. **Fix:** assert both dates separately. The September 18 charge is 12 days old, not 22.

3. **SCN-0015 — must fix: the mandatory refund leaves fourteen days uncovered.**  
   The window ends June 14, but the supplied periods stop May 31 despite continuous deployment. A2 **§11.3** refuses completion of a mandatory favorable case with uncovered days. **Fix:** supply the June 1–14 disposition and amount, or the applicable supported hold. $33.00 is the six listed periods’ subtotal, not yet a complete payable refund.

4. **SCN-0013 / SCN-0016 — must fix: charging assumes an unresolved approval gate.**  
   Both have no prior test, but neither supplies Gulf Plains’ cutover date or approval. Under A2 **§9.1–9.3 and §11.2**, an adverse correction with weak history requires approval when the window reaches before cutover—or cutover is unknown. **Fix:** specify a cutover that makes the gate lapse, or require approval before the $26.80/$2.10 charge lands.

5. **SCN-0025 — must fix: “most specific” omits the actual precedence rule.**  
   Patch **-22**, `gl_mapping_as_of()`, ranks **charge, then customer class, then territory, then tax jurisdiction**; it does not merely count populated dimensions. **Fix:** state that order and add competing mappings—for example, class-specific versus territory-and-tax-specific—to prove which wins.

6. **SCN-0025 — must fix: the export has another unmapped charge.**  
   Both residential bills contain customer charges, but the Given maps only distribution, commodity, adjustment, and tax. Under **-22 G2**, those customer charges also fail export. **Fix:** add their mapping, or explicitly expect those failures as well as the pilot-relight failure.

7. **SCN-0005 / SCN-0006 — note: the correction’s cause is ambiguous.**  
   A “meter test” establishes that September usage should be lower, yet the scenario voids and reissues. A2 **§12, R-33** distinguishes a meter that measured wrong—later-bill adjustment—from a bill computed wrong—reissue. **Fix:** explicitly make this a transcription/billing error, or supply the city tariff’s meter-error delivery rule. Carry that clarification into SCN-0024.

8. **SCN-0019 — note: the successful branch lacks its delegated law row.**  
   Branch (b) adds only Bluebonnet’s tariff, then expects a citation to a delegation. The family introduction and patch **-18**, “What changes,” establish that municipal coverage is absent from the seeded rows. **Fix:** explicitly provide the applicable delegated law row, tariff effective dates, and correction amounts before asserting success.

9. **SCN-0020 — should add: isolate the chronological-close refusal.**  
   Attempting to close October on October 10 fails because October has not ended, independently of September remaining open. Patch **-22 P3** checks both conditions. **Fix:** attempt October’s close after November 1 at 12:00 UTC while September remains open; separately test the exact UTC−12 eligibility boundary.

10. **SCN-0017 — should add: actually exercise opposite treatment of charge and refund.**  
    All periods are inside the claimed range and the cause has no window, so even a wrongly netted implementation can produce the same $15 net result. A2 **§6.1–6.3, R-25** requires independent period decisions. **Add:** an explicitly invented utility limit that excludes February’s +$10 but preserves March’s −$5; assert both disposition and payable total.

11. **Backbilling family — should add: a non-registering meter.**  
    Zero registration has a distinct three-month rule; a very slow meter remains a six-month meter-error case. A2 **§1.1, §2.3–2.4** distinguishes them and identifies the unresolved discovery-date versus test-date anchor. **Add:** discovery and bench test on different dates, with the anchor question explicitly open rather than silently adopting the implementation.

12. **Backbilling family — should add: newly migrated meter history.**  
    A deployment date introduced during migration must not automatically shorten a refund. A2 **§4.3** requires corroboration for the favorable deployment bound but treats the adverse direction differently. **Add:** identical recent deployment dates with and without predecessor evidence; assert the resulting charge/refund windows.

13. **Backbilling family — should add: evidence changes after evaluation.**  
    A prior test loaded later can shorten the window and invalidate an approved evaluation. A2 **§8, §9.2 and §11.2** requires fresh evaluation, approval where applicable, and delivery-time freshness checks. **Add:** evaluate and approve, then load an earlier test before posting; the stale charge must not land.

14. **Cancel-rebill × backbilling — should add: an upward correction.**  
    Every worked replacement reduces the original charge. A2 **§12.1–12.4** separately gates increases: a rate-misapplication reissue requires its cause and unchanged units; other causes cannot borrow that path. **Add:** an unchanged-usage price increase that passes and an increased-usage “rate correction” that fails.

15. **Deposits family — should add: cap and waiver decisions under binding law.**  
    SCN-0012 tests Texas interest, but none exercises CI-129. **Deposits §2.1–2.2** distinguishes the statutory cap, applicable waivers, missing waiver inputs, and trigger-time waiver rechecking. **Add:** a Gulf Plains deposit capped by annual billing and an otherwise valid additional deposit excused by an applicable waiver.

16. **Deposits family — should add: interest across a rate change and partial application.**  
    The only accrual example has constant principal and rate. **Deposits §3.2–3.5, B4–B6** requires contiguous periods split at either change, with each event rounded separately. **Add:** those splits plus refusal when no utility rate covers the first accrual day.

17. **SCN-0009 / deposits — should add: the final bill consumes the entire deposit.**  
    The $108.63 remainder exercises only a positive refund. **Deposits §4.3, B7–B8 and B18** requires an explicit zero-refund settlement when fully applied, with interest settled where owed before account closure. **Add:** a final bill equal to or greater than the deposit; assert settlement and closure eligibility.

18. **SCN-0007 / SCN-0008 — should add: incorrect refund evidence is later corrected.**  
    “Exactly one due record” tests rerun idempotence but not changed facts. **Deposits §5.4** allows withdrawal when supporting facts prove wrong; patch **-15**, return-due withdrawals and supersession, preserves that history. **Add:** a wrongly attributed late penalty is corrected, changing eligibility without editing or duplicating the original decision.

19. **Deposits × cancel-rebill — should add: a deposit paid a subsequently voided final bill.**  
    SCN-0009 applies $41.37 and refunds $108.63; no case then corrects that final bill. The digest’s **§1, add-only money and Kyle’s one-pot ruling**, requires preserving actual movements and showing the resulting net position. **Add:** void/correct after the refund; specify the application reversal and remaining customer credit rather than silently restoring a deposit already paid out.

20. **SCN-0026 — should add: account balance after reversing the recovery.**  
    Reversing the +$50 recovery restores the write-off capacity, but the −$50 payment still exists. Under **-22 W3** and CI-019, the account now has a **$50 credit** unless the payment is separately reversed. **Fix:** assert that balance and date branch (c); test that its later reversal cannot authorize an earlier-dated over-recovery.

21. **Across families — should add: a non-Texas rule produces a different answer.**  
    Fremont is introduced but never exercised. The digest’s **Standing rules** and **-17 rule-terms convention** require jurisdiction-driven evaluation. **Add:** an explicitly invented Fremont deposit earning interest from day one, or a backbilling window measured in days, alongside the Texas example.

22. **SCN-0008 — note: April 5 is not derivable from the Given.**  
    The March late penalty has no date, and no monthly review schedule is supplied. **Deposits §5.4** records when the obligation becomes due; a rolling twelve-month interpretation alone does not establish April 5. **Fix:** supply exact event dates and evaluation cadence, or leave the next eligibility date unresolved with the window question.