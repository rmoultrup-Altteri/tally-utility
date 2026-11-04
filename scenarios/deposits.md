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
- Over the next twelve months BB-02 pays every bill; two are paid late and carry the 10% penalty, posted Mar 20 and Jul 20, 2026. No returned check, no disconnect notice, and on Jan 5, 2027 no bill is past due.

**When** the deposit reaches twelve months on Jan 5, 2027 (bills are dated the 15th; the twelve counted are Jan 15 – Dec 15, 2026), (a) with no request from BB-02; (b) BB-02 having asked for a check.

**Then**
- The core records that the return fell due on Jan 5, 2027, citing Bluebonnet's tariff record, the twelve bills, the two late penalties counted, and that no bill was past due. (Bluebonnet's tariff counts **months**, read here as the deposit's anniversary; the Texas rule counts twelve bills instead, and would fall due on the twelfth clean bill.)
- **(a)** The next bill carries a credit of **$250.00**, with no interest line.
- **(b)** A check for **$250.00** is issued to BB-02, recording the customer's request; no bill credit.
- Had a bill been past due on Jan 5, 2027, no due record is written that day; the check runs again daily.
- Exactly one due record exists however many times the check runs.

---

### SCN-0008 — A third late penalty holds the deposit until the oldest is a year old

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; reworked to his answer 14 (rolling twelve months). The reading that it falls due on Jan 5 by a second route is withdrawn (answer 13).
*Rule:* as SCN-0007; the tariff's limit on late penalties disqualifies the refund while more than two fall in the last twelve months. Sources: as SCN-0007.

**Given** SCN-0007, except that the November 2026 bill is also paid late: a third penalty, posted Nov 20, 2026. The check runs daily.

**When** the deposit reaches twelve months on Jan 5, 2027, and the check runs daily after it. BB-02 pays every bill after November on time, so no bill is past due (**invented**).

**Then**
- On Jan 5, 2027 no due record is written: three penalties fall in the last twelve months (Mar 20, Jul 20, Nov 20, 2026). The deposit stays held: $250.00.
- On **Mar 21, 2027**, the first day the Mar 20, 2026 penalty is more than twelve months old, two remain, and the due record is written that day, citing the two counted. The next bill carries the $250.00 credit.
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
- Had the first cut-off been on Jul 15, 2025 (more than twelve months before Aug 10, 2026), no top-up is required: only one disconnection falls in the window.
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
- **(b)** The deposit is **$100.00**, category residential. Once PF-02 provides a date of birth, the senior category applies and $60.00 is owed back to PF-02 (how it is paid back is not ruled).

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
