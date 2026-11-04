# Deposits

Taking, holding, refunding and applying a customer's deposit. Invariants: CI-125 (interest accrual discipline), CI-129 to CI-131 (the Texas cap, interest and automatic refund, for a utility the Texas rule binds), CI-049 (a payment designated as a deposit). Schema at parity after v5.4.2-15. The rules the core evaluates are in `application/deposits-rules-for-the-core.md`; its boundary cases B1–B20 are the source of the Texas-law scenarios here.

**How a deposit rule is found.** A deposit cites the law's row for its place, service and customer class, and the utility's own tariff record for its own deposit category (Ryan 10-12, deposit decisions 2 and 5). For a city-owned system the Texas deposit rules (16 TAC §7.45) do not bind; the law row is a delegation, and the city's tariff is the whole policy. For a utility the Texas rule binds (Gulf Plains, unincorporated), the tariff may be stricter, never looser. A state's deposit interest rate is a floor only where it binds (deposit decision 4).

---

### SCN-0007 — A renter's deposit is credited back after twelve clean months

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; variant (b) added at his request.
*Rule:* a city system refunds a deposit on its own tariff's terms; the core records once that the return fell due, citing what it rests on. Bluebonnet's tariff has two routes only: after twelve months of good payment, or at disconnection. On the first, the deposit is credited to future bills, or paid by check if the customer asks; "no bill is past due" is one of its conditions, and late penalties are counted over a rolling twelve months. Sources: Kyle 11-03, answers 13 and 14; Bluebonnet's tariff (`cast.md` §2, from Brenham); the return-due record (deposit design §3.5; written once when the answer becomes "due", never per check).

**Given**
- Bluebonnet City Gas; customer BB-02, a renter outside the city (schedule R-R).
- On Jan 5, 2026 BB-02 pays $250.00 designated as a deposit (the only designation a customer can make besides "bill"; Kyle 10-15, K-05). Category "renter", which Bluebonnet's tariff maps to the law's residential class.
- Bluebonnet's tariff: refund after 12 months with no returned checks, no disconnect notices, no more than two late penalties in a rolling 12 months, and no bill past due. No interest (**invented**; the source is silent, and no state floor binds a city system).
- Over the next twelve months BB-02 pays every bill; two are paid late and carry the 10% penalty, posted Mar 31 and Jul 31, 2026, the day after the March and July bills fell due (bills of the 15th are due the 30th). No returned check, no disconnect notice, and on Jan 5, 2027 no bill is past due.

**When** the deposit reaches twelve months on Jan 5, 2027 (bills are dated the 15th; the twelve counted are Jan 15 – Dec 15, 2026), (a) with no request from BB-02; (b) BB-02 having asked for a check.

**Then**
- The core records that the return fell due on Jan 5, 2027, citing Bluebonnet's tariff record, the twelve bills, the two late penalties counted, and that no bill was past due. (Bluebonnet's tariff counts **months**, read here as the deposit's anniversary; the Texas rule counts twelve bills instead, and would fall due on the twelfth clean bill.)
- **(a)** The next bill carries a credit of **$250.00**, with no interest line.
- **(b)** A check for **$250.00** is issued to BB-02, recording the customer's request; no bill credit.
- Had a bill been past due on Jan 5, 2027, no due record is written that day; the check runs again daily.
- Exactly one due record exists however many times the check runs.

---

### SCN-0008 — A third late penalty holds the deposit until the oldest is a year old

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; reworked to his answer 14 (rolling twelve months). Kyle checked Mar 21, 2027 on penalty dates that did not fit Bluebonnet's due dates; re-dated in review round 2 (all three reviewers), which moves it to Apr 1, 2027. The reading that it falls due on Jan 5 by a second route is withdrawn (answer 13).
*Rule:* as SCN-0007; the tariff's limit on late penalties disqualifies the refund while more than two fall in the last twelve months. Sources: as SCN-0007.

**Given** SCN-0007, except that the November 2026 bill is also paid late: a third penalty, posted Dec 1, 2026 (the November bill fell due Nov 30). The check runs daily.

**When** the deposit reaches twelve months on Jan 5, 2027, and the check runs daily after it. BB-02 pays every bill after November on time, so no bill is past due (**invented**).

**Then**
- On Jan 5, 2027 no due record is written: three penalties fall in the last twelve months (Mar 31, Jul 31, Dec 1, 2026). The deposit stays held: $250.00.
- On **Apr 1, 2027**, the first day the Mar 31, 2026 penalty is more than twelve months old, two remain, and the due record is written that day, citing the two counted. The next bill carries the $250.00 credit.
- Exactly one due record, however many daily checks ran before it.
- For contrast: the build's reading of the Texas rule counts every late payment since the deposit was posted (deposit rules DG4, case B15). Kyle reads §7.45(5)(F)(ii) as rolling too (11-03, flag 1); revisiting the build is the money stream's (board note).

---

### SCN-0009 — At move-out the deposit pays the final bill first, and the rest is refunded

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* at disconnection the deposit is applied to the final bill first, and the remainder is refunded; if the deposit falls short, the customer owes the rest; the refund draws on the customer's net position. Sources: Kyle 11-03, answer 13 (the second route); Bluebonnet's tariff ("applied to the final bill at disconnection"); deposit rules for the core §4.4; a customer's credits are one balance (Kyle 10-30).

**Given**
- BB-01 holds a $150.00 homeowner deposit (no interest; city system).
- BB-01 moves out on Apr 2, 2027. The final bill is $41.37 (its own arithmetic belongs to the account-lifecycle family). No other balance or credit.

**When** the final bill is issued.

**Then**

| Step | Amount |
|---|---|
| Deposit held | $150.00 |
| Applied to the final bill | −$41.37 |
| Refunded to BB-01 | **$108.63** |
| Final bill owed | $0.00 |

- The application is recorded before the refund. The refund is not shown as available while the final bill is unpaid.
- If BB-01 also owed an earlier unpaid bill, the deposit would cover it too before any refund (the net position).

---

### SCN-0010 — A second disconnection for nonpayment tops up the deposit

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; reworked to his answer 15.
*Rule:* a city's tariff may require an additional deposit when a counted event recurs. An account holds one deposit balance, topped up by a recorded event that cites its trigger and the events it counted, not a second deposit. Reconnection is not held for the top-up unless the tariff says so. Where §7.45 binds instead, a disconnection cannot trigger an additional deposit at all (only use at least twice the estimate can, §7.45(5)(C)(ii)), and the total is checked against the one-sixth-of-annual-billings cap. Sources: Kyle 11-03, answer 15; Pecan Flat's tariff (`cast.md` §1, from Stinnett: an extra $125 after a second disconnection for nonpayment); deposit triggers and thresholds (deposit rules for the core §2.3).

**Given**
- Pecan Flat Municipal Gas; customer PF-01, residential deposit $100.00 held.
- PF-01's service is cut off for nonpayment on Feb 10, 2026 and again on Aug 10, 2026.

**When** PF-01 asks for reconnection after the second cut-off.

**Then**
- A top-up of **$125.00** is required, recorded as the "second disconnection for nonpayment" trigger, citing Pecan Flat's tariff record and the two disconnections, both within the last twelve months.
- PF-01's one deposit balance after it is paid: **$225.00**.
- Reconnection goes ahead whether or not the top-up has been paid: Pecan Flat's tariff doesn't make it a condition.
- Had the first cut-off been on Jul 10, 2025 (more than twelve months before Aug 10, 2026), no top-up is required: only one disconnection falls in the window.
- The same two cut-offs at Gulf Plains, where §7.45 binds: no additional deposit may be demanded for them.

---

### SCN-0011 — A customer aged 65 or over pays the senior deposit

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; the missing-birth-date case settled (answer 16).
*Rule:* a utility's own deposit category sets the amount; each category maps to one law class. A customer is placed in the senior category only on a date of birth on file. Sources: Kyle 11-03, answer 16; Pecan Flat's tariff (senior deposit borrowed from Sealy); deposit decision 5 (utility categories, Ryan 10-12).

**Given**
- Pecan Flat; PF-02 is a renter aged 67 starting service.
- Pecan Flat's categories: residential $100.00; senior (65 or over) $40.00; both mapped to the law's residential class. For a city system the law row is a delegation, so nothing is compared against a state cap.

**When** PF-02's deposit is set, (a) with PF-02's date of birth on file; (b) without it.

**Then**
- **(a)** The deposit is **$40.00**, category senior, law class residential, citing Pecan Flat's tariff record.
- **(b)** The deposit is **$100.00**, category residential. Once PF-02 provides a date of birth, the senior category applies to the deposit from then on.
- **Open (Kyle, next batch):** when the date of birth arrives after a $100.00 deposit was paid, is $60.00 returned, and when? Pecan Flat's tariff makes no refund while service continues (`cast.md` §1, invented), and answer 16 rules only the amount at the start.

---

### SCN-0012 — Under the Texas rule, interest on a deposit held 30 days is nothing; held 31 days, it runs from day one

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03. Gulf Plains' tariff is not yet drafted; this uses only the Texas law row.
*Rule:* where 16 TAC §7.45 binds, a cash deposit held 30 days or less earns no interest; one held longer earns it from the day it was posted. Interest is simple, actual days over 365, rounded per accrual. Sources: deposit rules for the core §3.1 and cases B1–B2 (CI-130).

**Given**
- Gulf Plains Gas Company (`cast.md` §3), a customer in the unincorporated area, where the Texas rule binds.
- A $200.00 cash deposit posted Jan 1, 2026. The interest rate in force for the period is 3% (**invented**), the rate the accrual cites; where §7.45 binds, it is the state-set rate the utility must pay (CI-130), and the accrual cites the rule the deposit was decided under (deposit rules §5.5).

**When** the deposit is refunded (a) on Jan 31, 2026, 30 days held; (b) on Feb 1, 2026, 31 days held.

**Then**
- **(a)** No interest. An accrual for these 30 days is refused, though the formula would give $0.49.
- **(b)** One accrual, Jan 1 – Jan 31 (31 days): $200.00 × 3% × 31/365 = 0.5096 → **$0.51**, credited before the refund. Refund: $200.00 principal and $0.51 interest, shown separately.

---

### SCN-0029 — A final bill paid from the deposit is later voided: the customer is owed the difference

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; the $11.25 settled as a deposit refund (answer 17). Written against the ruling: how credits are tracked belongs to the cash family (v5.4.2-23, in review).
*Rule:* money movements are never edited: a void reverses the bill's charge, but the deposit's application and its refund stay as they happened. What results is shown to the customer as one net balance, and a credit left when a deposit-paid final bill is corrected down is a deposit refund, paid out whatever its size. Sources: Kyle 11-03, answer 17; every reversal names what it undoes (CI-017); a customer's credits are one pot, shown as one net balance (Kyle 10-30); a fully or partly applied deposit is settled before the customer can close (deposit rules §4.3–4.4).

**Given**
- SCN-0009: BB-01 moved out Apr 2, 2027; the final bill of $41.37 was paid from the $150.00 deposit, and $108.63 was refunded by check on Apr 6 (**invented** date).
- On Apr 20 the final read is found keyed high. The corrected final bill is **$30.12** (**invented**; its arithmetic belongs to the account-lifecycle family).

**When** the operator voids the final bill and issues the correction.

**Then**

| Entry | Amount | Names |
|---|---|---|
| Final bill charge | +$41.37 | — |
| Deposit applied to the final bill | −$41.37 | the deposit |
| Void reversal | −$41.37 | the final bill's charge |
| Correction (final) bill charge | +$30.12 | — (names the voided bill) |
| **Balance** | **−$11.25**, a credit owed to BB-01 | |

- The deposit's own history is unchanged: $150.00 held, $41.37 applied, $108.63 refunded. Neither the application nor the refund is edited, and the deposit does not reappear as held.
- BB-01 sees one figure: a credit of $11.25. The account cannot close until it is paid out.
- The $11.25 is paid out as a **deposit refund**: a utility's minimum refund amount for ordinary overpayments does not apply to it.

---

### SCN-0032 — The same deposit in Fremont earns interest from the first day

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03. Fremont's law is **invented**; this tests that a statutory rule is a row for its place.
*Rule:* the deposit's law row is found by the premise's state, service and customer class; where a state's interest rate binds, it is a floor, and the utility's tariff may pay more, never less. Sources: deposit decisions 4 and 5 (Ryan 10-12); the rule-terms convention (Ryan 10-06: law rows are typed keys with terms, per place); "launch scope is not architecture scope".

**Given**
- Prairie Line Gas Company, an investor-owned utility in the State of Fremont (`cast.md` §4); customer PL-01, residential.
- Fremont's law row (**invented**): a gas utility it regulates pays simple interest on a residential cash deposit from the day it is posted, at the state's yearly rate, 2% for 2026; actual days over 365, rounded per accrual. No minimum holding period.
- A $200.00 cash deposit posted Jan 1, 2026 and refunded Jan 31, 2026: held 30 days, accrued Jan 1–30.

**When** the refund is made with Prairie Line's own tariff stating (a) no rate; (b) 1%; (c) 3%.

**Then**
- **(a)** One accrual: $200.00 × 2% × 30/365 = 0.3288 → **$0.33**, citing Fremont's row. Refund: $200.00 principal and $0.33 interest, shown separately. The same deposit under Texas law earns nothing (SCN-0012 a).
- **(b)** Prairie Line's tariff record is refused when entered: 1% is below the floor of the law row it maps to.
- **(c)** $200.00 × 3% × 30/365 = 0.4932 → **$0.49**, citing the tariff record and the law row.
- Nothing in the calculation names Texas or Fremont: the same steps read a different row.

---

### SCN-0042 — Under the Texas rule, a deposit is capped at a sixth of the year's bills, and a waiver in force excuses it

*Status:* draft (2026-11-04), not yet sent to Kyle. Gulf Plains' tariff is not drafted; its deposit amount and the customer's estimated annual billing are **invented**. Reviewer gap (Codex, Opus, 2026-11-02). Case (c)'s fail-open rests on GBM's decision table #53 (rank 4), carried into the deposit rules as DG3, not on a Kyle ruling.
*Rule:* where §7.45 binds, a deposit may not exceed one-sixth of the customer's estimated annual billing; the deposit records the cap, where it came from, and that it reduced the amount, so the customer can be told. A waiver in force on the posting date (both ends of its dates included) excuses the deposit it reaches. Where an input the waiver needs is missing, such as a date of birth, no deposit is taken. Sources: deposit rules for the core §2.1 (waivers; #53 rank 4, fail open: DG3), §2.2 (the cap); cases B11; CI-129.

**Given**
- Gulf Plains (`cast.md` §3), where the Texas rule binds. Its tariff deposit for a residential customer is $200.00 (**invented**).
- A new residential applicant, **GP-05 (invented)**, whose estimated annual billing is $960.00 (**invented**; how it is estimated for a new applicant is not yet specified, deposit rules §2.2, #53 OQ5). The deposit is set on Mar 1, 2026.

**When** the deposit is set for GP-05 (a) with no waiver; (b) aged 66 and owing nothing to Gulf Plains; (c) with no date of birth on file; (d) with a family-violence certification that expires on Mar 1, 2026.

**Then**
- **(a)** The cap is $960.00 ÷ 6 = **$160.00**, less than the tariff's $200.00. The deposit is **$160.00**, recording the cap, its source (the Texas rule), its basis ($960.00) and that it reduced the amount.
- **(b)** No deposit: the age-65 waiver is in force and reaches the rule.
- **(c)** No deposit: the waiver can't be evaluated, and the Texas rule fails toward the customer. (Pecan Flat, a city system, charges $100.00 in the same case, because its own tariff governs: SCN-0011 b.)
- **(d)** No deposit: the certification is in force through the posting date.

---

### SCN-0043 — Deposit interest splits at a rate change and at a partial application

*Status:* draft (2026-11-04), not yet sent to Kyle. Gulf Plains' interest rates are **invented**. Reviewer gap (Opus, 2026-11-02).
*Rule:* as SCN-0012, and an accrual period never spans a change of the interest rate or a part of the deposit applied to the balance: it splits at that day, and each part runs at its own rate on the principal then held. A period with no rate in force is refused, never filled from the nearest rate. Sources: deposit rules for the core §3.3–3.5 and cases B4, B5, B6.

**Given** Gulf Plains; $200.00 cash deposits; interest simple, actual days over 365, rounded per period.

**When**
- (a) a deposit posted Dec 1, 2026, the rate 3% to Dec 31 and 2.5% from Jan 1, 2027 (**invented**), is refunded on Feb 1, 2027;
- (b) a deposit posted Jan 1, 2026 at 3%, of which $50.00 is applied to the customer's balance on Feb 15, 2026, is refunded on Apr 1, 2026;
- (c) as (a), but the first rate on record starts Dec 15, 2026.

**Then**
- **(a)** Two periods: Dec 1–31 at 3%, $200.00 × 3% × 31/365 = 0.5096 → **$0.51**; Jan 1–31 at 2.5%, $200.00 × 2.5% × 31/365 = 0.4247 → **$0.42**. Interest $0.93; refund $200.00 principal and $0.93 interest, shown separately. One period across Jan 1 is refused.
- **(b)** Jan 1 – Feb 14 on $200.00: × 3% × 45/365 = 0.7397 → **$0.74**; Feb 15 – Mar 31 on $150.00: × 3% × 45/365 = 0.5548 → **$0.55**. Refund $150.00 principal and **$1.29** interest. One period across Feb 15 is refused.
- **(c)** The accrual is refused: no rate is in force on Dec 1.

---

### SCN-0044 — A final bill that uses up the whole deposit: the refund is zero, and it is still recorded

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02).
*Rule:* at close the deposit pays what is owed first. A deposit used up entirely is settled by a refund of zero, recorded and disclosed; until it is, the account cannot close. Where interest is owed, it runs on the whole deposit up to the day it was applied, and is paid out separately. Sources: deposit rules for the core §4.2–4.4 and cases B7, B18; Kyle 11-03, answer 13 (route b, at disconnection).

**When**
- (a) at Gulf Plains, a $200.00 cash deposit posted Jan 1, 2026 at 3% (**invented**) is applied in full on Mar 2, 2026 to a final bill of exactly $200.00 (**invented**);
- (b) at Bluebonnet, BB-01's $150.00 deposit (no interest) is applied in full to a final bill of exactly $150.00 (**invented**).

**Then**
- **(a)** Interest through Mar 1 (60 days): $200.00 × 3% × 60/365 = 0.9863 → **$0.99**, credited before the refund. The refund is **$0.00** principal, with $0.99 interest paid to the customer.
- **(b)** The refund is **$0.00**, with no interest line.
- In both, the account can close only once the zero refund is recorded.
- Had (a)'s deposit been used up within 30 days of posting, no interest would be owed at all, and the zero refund carries none (case B8).

---

### SCN-0045 — A returned check holds the deposit until it is a year old

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02, A9). The rolling window is this stream's reading of Kyle's answers 13 and 14 for returned checks (he ruled it for late penalties); confirming it goes to Kyle.
*Rule:* Bluebonnet refunds a deposit after twelve consecutive months of good payment; a returned check breaks that run. Sources: Bluebonnet's tariff (`cast.md` §2: no returned checks); Kyle 11-03, answers 13 and 14.

**Given** SCN-0007 (a), except that BB-02's check for the July bill comes back unpaid on **Aug 10, 2026** (**invented**), and is made good on Aug 12. No other returned check; two late penalties, as SCN-0007; no bill past due from then on.

**When** the deposit reaches twelve months on Jan 5, 2027, and the check runs daily after it.

**Then**
- On Jan 5, 2027 no due record is written: a returned check falls in the last twelve months.
- On **Aug 11, 2027**, the first day the returned check is more than twelve months old, the due record is written, citing the clean months. The next bill carries the $250.00 credit, unless BB-02 asks for a check.
- **Open (Kyle, next batch):** is a returned check counted over the same rolling twelve months as the late penalties, or does it disqualify the refund for the whole time the deposit is held?

---

### SCN-0046 — A deposit credit larger than the next bill joins the customer's one credit balance

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02, A9). How credits are tracked belongs to the cash family (v5.4.2-23, in review).
*Rule:* a deposit returned as a bill credit pays the next bill, and what is left joins the customer's credit, which is shown as one balance and applied to later bills; the customer may ask for a check instead. Sources: Kyle 11-03, answer 13; a customer's credits are one pot, shown as one net balance (Kyle 10-30).

**Given** SCN-0007 (a): the $250.00 return falls due on Jan 5, 2027. BB-02's next bill, issued Jan 15, 2027, is **$61.40** (**invented**).

**When** the January bill is issued, and then the February bill of $58.20 (**invented**).

**Then**
- The return fell due on Jan 5 (the decision); it is settled by the credit on the Jan 15 bill (the movement).
- The January bill is paid by the deposit credit: $250.00 − $61.40 leaves a credit of **$188.60**, shown to BB-02 as one figure.
- The February bill is paid from it: the credit is then **$130.40**.
- The deposit shows $250.00 returned on Jan 15, 2027, by bill credit; it does not reappear as held.
- **Open (Kyle, next batch):** (1) Answer 13 offers a bill credit or, if the customer asks, a check. Once the $250.00 is credited, can BB-02 later ask for what is left by check, and is that still a deposit refund (no minimum refund amount) or an ordinary credit refund? (2) If a bill falls past due between the Jan 5 decision and the Jan 15 credit, does the return still stand (deposit rules K6)?

---

### SCN-0047 — The facts behind a refund decision change: the decision is withdrawn or made, never edited

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Codex, 2026-11-02, item 18).
*Rule:* the record that a deposit's return fell due is written once, citing what it rests on. If those facts later prove wrong, it is withdrawn with a reason, and its history is kept; if corrected facts make a return due that wasn't, it is written then. Neither the original decision nor the penalties it counted are edited. Sources: deposit rules for the core §5.4; v5.4.2-15 (withdrawal and supersession); SCN-0034 (a penalty reversed for being wrongly assessed).

**When**
- (a) SCN-0008: on Dec 3, 2026 the Dec 1, 2026 penalty is found wrongly assessed (BB-02's check was postmarked on time) and reversed, as SCN-0034;
- (b) SCN-0007 (a): the due record was written Jan 5, 2027. On Jan 10 a returned check of Nov 12, 2026, posted by mistake to another customer, is moved to BB-02's account (**invented**).

**Then**
- **(a)** Two penalties now fall in the twelve months. The deposit falls due on **Jan 5, 2027**, not Apr 1; one due record is written that day.
- **(b)** The Jan 5 due record is withdrawn on Jan 10, with the reason citing the returned check; no credit is given on the Jan 15 bill. The deposit is held until the returned check is more than twelve months old: due **Nov 13, 2027**, on SCN-0045's reading, which is still open with Kyle. Nothing had been settled: the withdrawal comes before the Jan 15 credit. The withdrawn record stays readable beside the new one.
