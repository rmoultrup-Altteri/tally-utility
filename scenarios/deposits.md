# Deposits

Taking, holding, refunding and applying a customer's deposit. Invariants: CI-125 (interest accrual discipline), CI-129 to CI-131 (the Texas cap, interest and automatic refund, for a utility the Texas rule binds), CI-049 (a payment designated as a deposit). Schema at parity after v5.4.2-15. The rules the core evaluates are in `application/deposits-rules-for-the-core.md`; its boundary cases B1–B20 are the source of the Texas-law scenarios here.

**How a deposit rule is found.** A deposit cites the law's row for its place, service and customer class, and the utility's own tariff record for its own deposit category (Ryan 10-12, deposit decisions 2 and 5). For a city-owned system the Texas deposit rules (16 TAC §7.45) do not bind; the law row is a delegation, and the city's tariff is the whole policy. For a utility the Texas rule binds (Gulf Plains, unincorporated), the tariff may be stricter, never looser. A state's deposit interest rate is a floor only where it binds (deposit decision 4).

---

### SCN-0007 — A renter's deposit is credited back after twelve clean months

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a city system refunds a deposit on its own tariff's terms; the core records once that the return fell due, citing what it rests on. Sources: Bluebonnet's tariff (`cast.md` §2, from Brenham); the return-due record (deposit design §3.5; written once when the answer becomes "due", never per check).

**Given**
- Bluebonnet City Gas; customer BB-02, a renter outside the city (schedule R-R).
- On Jan 5, 2026 BB-02 pays $250.00 designated as a deposit (the only designation a customer can make besides "bill"; Kyle 10-15, K-05). Category "renter", which Bluebonnet's tariff maps to the law's residential class.
- Bluebonnet's tariff: refund as a bill credit after 12 months with no returned checks, no disconnect notices and no more than two late penalties (the second route, "also refunded if no bill is past due", is cast question 6 and not used here). No interest (**invented**; the source is silent, and no state floor binds a city system).
- Over the next twelve months BB-02 pays every bill; two are paid late and carry the 10% penalty, posted Mar 20 and Jul 20, 2026. No returned check, no disconnect notice.

**When** the deposit reaches twelve months on Jan 5, 2027 (bills are dated the 15th; the twelve counted are Jan 15 – Dec 15, 2026).

**Then**
- The core records that the return fell due on Jan 5, 2027, citing Bluebonnet's tariff record, the twelve bills, and the two late penalties counted. (Bluebonnet's tariff counts **months**, read here as the deposit's anniversary; the Texas rule counts twelve bills instead, and would fall due on the twelfth clean bill.)
- The next bill carries a credit of **$250.00**, with no interest line.
- Exactly one due record exists however many times the check runs.

---

### SCN-0008 — A third late penalty keeps the deposit

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* as SCN-0007; the tariff's limit on late penalties disqualifies the refund. Sources: as SCN-0007.

**Given** SCN-0007, except that the November 2026 bill is also paid late: a third penalty, posted Nov 20, 2026. The check runs daily.

**When** the deposit reaches twelve months on Jan 5, 2027.

**Then**
- No due record is written. The deposit stays held: $250.00.
- **Open (Kyle):** the tariff doesn't say over what window the penalties are counted. (For contrast, the build's reading of the Texas rule counts every late payment since the deposit was posted: deposit rules DG4, case B15.) If it is a rolling twelve months, the deposit falls due on Mar 21, 2027, the first day the Mar 20, 2026 penalty is more than twelve months old (two remain). If it is the whole time held, it never falls due by this route, only at move-out. And under the tariff's second route (cast question 6), it may fall due on Jan 5, 2027 regardless, since no bill is past due. Which do city systems mean?

---

### SCN-0009 — At move-out the deposit pays the final bill first, and the rest is refunded

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* at disconnection the deposit is applied to the final bill first, and the remainder is refunded; the refund draws on the customer's net position. Sources: Bluebonnet's tariff ("applied to the final bill at disconnection"); deposit rules for the core §4.4; a customer's credits are one balance (Kyle 10-30).

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

### SCN-0010 — A second disconnection for nonpayment calls for an extra deposit

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a city's tariff may require an additional deposit when a counted event recurs; the deposit records the trigger and the events it counted. Sources: Pecan Flat's tariff (`cast.md` §1, from Stinnett: an extra $125 after a second disconnection for nonpayment); deposit triggers and thresholds (deposit rules for the core §2.3).

**Given**
- Pecan Flat Municipal Gas; customer PF-01, residential deposit $100.00 held.
- PF-01's service is cut off for nonpayment on Feb 10, 2026 and again on Aug 10, 2026.

**When** PF-01 asks for reconnection after the second cut-off.

**Then**
- An additional deposit of **$125.00** is required, recorded as the "second disconnection for nonpayment" trigger, citing Pecan Flat's tariff record and the two disconnections.
- Deposits held after it is paid: $225.00.
- **Open (Kyle):** the tariff doesn't say whether the extra deposit must be paid before reconnection, or over what period the two disconnections are counted (ever, or within some months).

---

### SCN-0011 — A customer aged 65 or over pays the senior deposit

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a utility's own deposit category sets the amount; each category maps to one law class. Sources: Pecan Flat's tariff (senior deposit borrowed from Sealy); deposit decision 5 (utility categories, Ryan 10-12).

**Given**
- Pecan Flat; PF-02 is a renter aged 67 starting service.
- Pecan Flat's categories: residential $100.00; senior (65 or over) $40.00; both mapped to the law's residential class. For a city system the law row is a delegation, so nothing is compared against a state cap.

**When** PF-02's deposit is set.

**Then**
- The deposit is **$40.00**, category senior, law class residential, citing Pecan Flat's tariff record.
- **Open (Kyle):** if PF-02's date of birth is not on file, should the deposit be the $100 one until it is proven, or the $40 one? The Texas decision table's answer for the state's age-65 waiver was "no deposit when a waiver input is missing", but that is the Texas rule, not Pecan Flat's.

---

### SCN-0012 — Under the Texas rule, interest on a deposit held 30 days is nothing; held 31 days, it runs from day one

*Status:* draft (2026-11-02), not yet sent to Kyle. Gulf Plains' tariff is not yet drafted; this uses only the Texas law row.
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

*Status:* draft (2026-11-02), not yet sent to Kyle. Written against the ruling: how credits are tracked belongs to the cash family (v5.4.2-23, in review).
*Rule:* money movements are never edited: a void reverses the bill's charge, but the deposit's application and its refund stay as they happened. What results is shown to the customer as one net balance, and a credit owed to a former customer is paid out. Sources: every reversal names what it undoes (CI-017); a customer's credits are one pot, shown as one net balance (Kyle 10-30); a fully or partly applied deposit is settled before the customer can close (deposit rules §4.3–4.4).

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
- BB-01 sees one figure: a credit of $11.25. The account cannot close until it is paid out; with no service continuing, it is refunded.
- **Open (Kyle):** is the $11.25 a deposit refund (paid whatever its size, like any deposit refund) or an ordinary overpayment (subject to the utility's minimum refund amount and, if uncashed, unclaimed-property rules)? The money came from the deposit, but the deposit had already been settled.

---

### SCN-0032 — The same deposit in Fremont earns interest from the first day

*Status:* draft (2026-11-02), not yet sent to Kyle. Fremont's law is **invented**; this tests that a statutory rule is a row for its place.
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
