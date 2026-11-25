# Unmatched cash and agency pledges

Money the utility holds but cannot yet attribute to a customer, and pledges from assistance agencies. Invariants: CI-053 (no silent drop, no guessed account, no revenue; refund to whoever sent it), CI-055 (money recorded once), CI-056 (pledges and held money are worked within a service level; past it the system fails loud), CI-058 (the customer's date). Built by v5.4.2-24 (mirrored 2026-11-24, Ryan; design `application/wave2-build-2026-10-15/v5.4.2-24-design.md`; what the core must do, AC-48 to AC-53). Payments, refunds and bounces in general are `cash.md`. A customer's own money with no bill to pay (an overpayment) is SCN-0082, not this family. Reviewed in round 6 (`review/2026-11-25/`).

**Common to every scenario here.**
- **Held money is not a customer's money.** Money nobody can attribute is held as a *receipt*: on no customer's ledger, earning nothing, never revenue. It leaves only by an operator's recorded act. It can become one or more payments of identified customers (with a reason and the operator), go back to whoever sent it, be taken back by the bank, or be reported as unclaimed property. What a receipt still holds is the amount, less what went to payments and what was disposed of, plus what came back. It is worked out, never stored. A receipt must carry at least one thing to research it by: a name, an account as written, a check or reference number, a file row, an image, or the agency that sent it.
- **A candidate is evidence, not an application.** Intake or an operator may list customers the money might belong to. Nothing in the database acts on a candidate. The list of aged receipts returns them, and the collections rules read that list for the disconnection bar (SCN-0120).
- **What the database refuses and what the core decides.** The database refuses a payment or disposition past what a receipt holds (on every date), a second record of one provider transaction, a payment from a receipt dated before the money came or with a customer's date after it, and an agency payment that names no agency. It also refuses a refund of traced agency money to anyone but the agency, and a pledge's agreement or pay-by date sent by the app. The core decides matching, the operator queue, and when retention, the service level or a state's dormancy period has run out. It also records a pledge's lapse, and decides which acts a pledge or an aged receipt bars, read from the records here and from the collections rules (-26; wave 7's law rows).
- **Dates are 2026 unless stated.** A date later than the real today is refused by the database (a money date, a pledge, a disposition), so tests of these scenarios run under a controlled clock. A pledge "passes its pay-by date everywhere" when that day has ended in every time zone.
- **The cast.** The utilities' settings for held money and the agencies are in `cast.md` §5. Every agency and agreement is **invented**. New customers (**invented**): **PF-06** and **PF-07** (Pecan Flat, two rented houses with the same landlord) and **BB-16** (Bluebonnet, a homeowner inside the city named like BB-01) and **GP-07** (Gulf Plains, residential). GP-06 and BB-09 are `cash.md`'s. Each scenario stands alone unless it says it continues another; the same customer may be on different facts elsewhere.

---

### SCN-0117 — A lockbox check with no account number is held, never guessed, and keeps the day it came

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. The receipt is built (CI-053, v5.4.2-24); the late-penalty rules are not (R-11).
*Rule:* money that cannot be attributed is held as a receipt with its evidence, apart from every customer, however good a guess looks. When it is identified it becomes that customer's payment, posted in the open period. The payment's customer's date is no later than the day the money came, so a customer who paid on time stays on time. Sources: CI-053 (no guessed account); the wave-2 inventory, U2 (resolved by a payment naming the receipt, with its reason and user); CI-058; design §2.3; SCN-0034 (a penalty reversed when the payment proves on time).

**Given**
- BB-01 owes the reference bill, **$65.83**, issued Mon Nov 16, due Tue Dec 1 (`cash.md`). BB-16 owes $71.40 (**invented**).
- Bluebonnet's lockbox file of Wed Dec 2 holds 40 items totalling $3,912.66 (**invented**). Thirty-nine match an account. The fortieth is a check for **$65.83**, signed "R. Alvarez", postmarked Sat Nov 28, with no account number and no stub. BB-01 and BB-16 are both named Alvarez (**invented**).
- Intake lists both as candidates: BB-01 because the amount equals its open bill, BB-16 by name only.
- On Wed Dec 2 the late penalty posts on BB-01's unpaid bill: $6.52 and city sales tax $0.07, **$6.59** (`cancel-rebill.md` SCN-0033's figures).

**When** (a) the file is loaded on Dec 2; (b) on Fri Dec 4 the operator reaches BB-01, who confirms the check, and resolves the receipt to BB-01.

**Then**
- **(a)** The 39 items post as payments, and the fortieth is a receipt of $65.83, received Dec 2, with the payer's name, the check number and the file row as evidence. The file reconciles: $3,846.83 in payments plus $65.83 held is $3,912.66. BB-01's and BB-16's ledgers do not change. Bluebonnet holds **$65.83**. The core must refuse to post it to BB-01 because the amount matches: that is a guess (CI-053), and no database rule would catch it.
- **(b)**

| Entry (BB-01) | Amount | Names |
|---|---|---|
| November bill (Nov 16) | +$65.83 | — |
| Late penalty (Dec 2) | +$6.52 | the November bill |
| City sales tax on the penalty (Dec 2) | +$0.07 | the penalty |
| Payment (posted Dec 4; customer's date Nov 28, the postmark) | −$65.83 | the receipt; reason: customer confirmed by phone; the operator |
| Penalty reversal (Dec 4) | −$6.52 | the Dec 2 penalty; reason: paid on time, postmark Nov 28 |
| Tax reversal (Dec 4) | −$0.07 | the Dec 2 tax on the penalty |
| **Balance** | **$0.00** | |

- The receipt now holds $0.00. The payment carries the check's details exactly as the receipt records them (number, date, bank, channel), and a payment that differs is refused.
- Refused: the payment dated before Dec 2 (a payment is dated no earlier than the money came); a customer's date after Dec 2 (the money was here by then); a payment from the receipt with no reason or no operator.
- **A closed month.** Had the check come on Mon Nov 30, been recorded that day, and November been closed before it was identified, the payment would still be posted in December with customer's date Nov 28. A closed month does not stop a held receipt from being resolved. A check *found* after November closed, with a bank date of Nov 30, is another matter: a receipt cannot be recorded with a date in a closed month. It is recorded with the first open day as its date, and the bank's date goes in its evidence. Its age then starts late, and its payment's customer's date can be no later than that recorded date. (Board note to money: a found-late receipt's true date.)
- **Open (Kyle):** the penalty posted on Dec 2 while the utility already held the customer's money unidentified. Should the core hold penalties on a receipt's candidates until it is resolved, or post and reverse them as here?

---

### SCN-0118 — One check pays two accounts, and nothing past what it holds

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-24).
*Rule:* one receipt may become several payments of different customers, each with its reason. Together they never exceed the receipt, on any date. Money not yet identified stays held, and its age runs from the day it came, not from the day part of it was resolved. A landlord's or relative's check is the customer's own payment, not an agency's. Sources: design §2.3 (the cap; the household paying two accounts); CI-053; Ryan 2026-11-07 (DECISION-LOG: "a relative or landlord paying is the customer's own payment").

**Given**
- PF-06 owes $75.50, issued Nov 20, due Tue Dec 1: 5.0 Mcf × $9.00 = $45.00, and gas 5.0 Mcf × $6.10 = $30.50 (SCN-0084's bill). PF-07 owes **$45.30**: 3.0 Mcf × $9.00 = $27.00, and gas 3.0 Mcf × $6.10 = $18.30 (usage **invented**). Both are residential, so neither bill carries tax (`cast.md` §1).
- On Fri Nov 27 the landlord's check for **$120.80**, with no stub, reaches the counter. It is recorded as a receipt with the landlord's name and the check number. It lists no candidate.
- On Wed Dec 2 both bills are unpaid on the books, so Pecan Flat's 10% penalty posts on each: 10% × $75.50 = **$7.55** on PF-06 and 10% × $45.30 = **$4.53** on PF-07.

**When** (a) on Thu Dec 3 the landlord's office says it is for both houses, and the operator makes two payments from it; or (b) on Dec 3 the office names only PF-06, and PF-07 is identified on Tue Dec 8.

**Then**
- **(a)**

| Payment | Account | Amount | Customer's date | Receipt holds after |
|---|---|---|---|---|
| 1 | PF-06 | $75.50 | Nov 27 | $45.30 |
| 2 | PF-07 | $45.30 | Nov 27 | $0.00 |

- Both bills were paid on time (the day received counts at Pecan Flat, `cast.md` §1), so both Dec 2 penalties, $7.55 and $4.53, are reversed on Dec 3, each naming its penalty, as in SCN-0117 (b).
- A third payment from the receipt, of any amount, is refused. So is payment 2 for $45.31 instead of $45.30.
- **(b)** On Dec 3 the receipt holds $45.30, and PF-06's $7.55 is reversed. The receipt is 6 days old on Dec 3 (counted from Nov 27, not from the first resolution) and 11 on Dec 8, past Pecan Flat's 10-day service level from Dec 8 (SCN-0120). PF-07's $4.53 is reversed on Dec 8 when payment 2 is posted with customer's date Nov 27.
- SCN-0117's Open (hold penalties on a receipt's candidates?) would not help here: this receipt lists no candidate.
- Each payment is the customer's own, so a later refund of it names no agency. **Open (Kyle):** if the landlord's check had overpaid, is the refund check made out to the tenant (the account holder) or to the landlord who wrote the check?

---

### SCN-0119 — Money nobody claims goes back to whoever sent it, or is reported as unclaimed property, and never becomes revenue

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-24). When the state's dormancy period ends is the core's to compute, from the state's rule.
*Rule:* once the utility's retention period has passed, held money is returned to whoever sent it if they can be found. Money whose owner cannot be found is held until the state's dormancy period has run, and is then reported as unclaimed property. A return that is sent but never cashed is undone, and the money is held again. Nothing happens on a clock: the core flags each step and an operator acts. Sources: CI-053 (refund to the originating party after the tenant's retention; escheat per jurisdiction); design §2.3 and §2.4; Texas Property Code §72.101(a) (presumed abandoned after more than three years with the owner's location unknown and no claim), §76.001 and §76.301(a) (a municipality holding property of $100 or less that is presumed abandoned delivers it, with its report, to its own treasurer by Nov 1 after the June 30 it holds it; texas.public.law, verified May 26, 2025).

**Given** Bluebonnet's retention is 180 days (`cast.md` §5). Two receipts are never identified (**invented**):
- **R1:** a check for $38.00 received Wed Dec 2, from "M. Ortiz, 1410 Pecan St." Bluebonnet has no account at that address or under that name.
- **R2:** $20.00 in cash in the night drop on Dec 2, in an envelope marked only "gas". It is recorded with the night-drop log entry and a photo of the envelope as its evidence.

**When** (a) the core runs its daily check on Mon May 31, 2027 and on Tue Jun 1, 2027; (b) on Jun 1, 2027 the operator sends R1's $38.00 back by check; (c) that check comes back undeliverable on Tue Jul 6, 2027; (d) the core's check after the dormancy period has run.

**Then**
- R2 recorded with no evidence at all (no name, no number, no log entry, no image) is refused.
- **(a)** On May 31, 2027 each receipt is 180 days old and not past retention. On Jun 1, 2027 it is 181, and both are listed as past retention. Nothing moves until an operator acts. If retention were unset, the list would still run and show "past retention" as unknown; if the *service level* were unset, the list would not run at all (SCN-0120 (c)).
- **(b)** R1: a return to sender of $38.00, dated Jun 1, 2027, with the outgoing check number and a reason. It now holds $0.00.
- **(c)** R1: an undo of $38.00 naming the return, dated Jul 6, 2027. It holds $38.00 again, and the sender's location is now unknown. A second undo of the same return is refused, because nothing is left of it. An undo of an undo is refused.
- R2 has no sender, so it can only be held until the dormancy period ends.
- **(d)** R2 is presumed abandoned once more than three years have passed since Dec 2, 2026 with its owner unknown and no claim: from Mon Dec 3, 2029. On Sun Jun 30, 2030 Bluebonnet still holds it. Bluebonnet is a city and R2 is $100 or less, so it goes to the city's own treasurer with the report by Fri Nov 1, 2030 (SCN-0103 uses the same date). R1 is the same if its owner counts as unknown from the start. If the three years run only from Jul 6, 2027, when its address proved wrong, R1 is presumed abandoned from Jul 7, 2030 and reported by Nov 1, 2031 (Open, below). Each receipt then records "reported as unclaimed property", state TX, with the report's reference, for what it holds ($38.00; $20.00), and holds $0.00. A report with no state or no reference is refused. Neither receipt ever reaches a customer's ledger.
- At Gulf Plains, which is not a city, the same money would be reported to the state under Property Code ch. 74.
- **Open (Kyle or a tax advisor):** does R1's three years run from the day the money came or from the day its sender's address proved wrong?
- **Open (a citation check):** what the city's treasurer does with property delivered under chapter 76 (§76.601–§76.602, not yet read). Is it held for the owner in the city's own fund, and is that fund ever the city's revenue?
- **Open (Kyle):** retention (180 days here) and dormancy (more than three years) are two deadlines, and only a return to the sender fits inside the shorter one. Is 180 days a sensible default suggestion at onboarding for a city system, and does a city really return checks to senders it can find before the dormancy period?

---

### SCN-0120 — Held money past the service level bars disconnecting the customers it might belong to

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. The aged list and its candidates are built (CI-056, v5.4.2-24); the bar on disconnection is the collections rules' condition for aged held money (-26; which acts it bars is wave 7's rule data).
*Rule:* a receipt still holding money past the utility's service level is aged. It is listed for the operator, oldest first, with its candidates, and it bars a disconnection of each candidate. A customer nobody listed is not protected. While a utility's service level is unset, which receipts are aged cannot be known: the list refuses to run, and the collections rule treats the bar as unevaluable, so the disconnection waits. Sources: CI-056 (fail loud: an operator surface, a disconnection pause); design §2.4; -26 (an unevaluable condition blocks the act); limit L1 (candidates are as good as intake made them).

**Given**
- Pecan Flat's service level is 10 days (`cast.md` §5). PF-07's $45.30 from the landlord's check of Fri Nov 27 is still held. Here, unlike SCN-0118, intake listed PF-07 as its candidate, by the landlord's name on PF-07's file.
- PF-07's $45.30 bill is still unpaid on the books on the 10th, so Pecan Flat's cut-off at 1:00 p.m. on Thu Dec 10 applies (`cast.md` §1).

**When** the cut-off list is drawn on Dec 10; or (b) the same, but intake listed no candidate; or (c) the same, but Pecan Flat has never set its service level.

**Then**
- Day by day: the receipt is 10 days old on Mon Dec 7, not aged. It is 11 on Tue Dec 8, and aged from then.
- **(a)** On Dec 10 the receipt is aged and PF-07 is its candidate. PF-07 is held off the cut-off list, and the hold names the receipt. When the receipt is resolved to PF-07, the bill is paid, with customer's date Nov 27.
- **(b)** Nothing links the receipt to PF-07. PF-07 is cut off, and the aged receipt is on the operator's list with no candidate. This is the known limit: the record cannot prevent it.
- **(c)** The aged list refuses to run at Pecan Flat. To the cut-off rule the bar is unevaluable, so **no** Pecan Flat customer is cut off until the setting is entered. That blocks every account, not only PF-07.
- **Open (Kyle):** between Nov 27 and Dec 8 the receipt is within its service level, so nothing bars a cut-off of PF-07. Had the cut-off date fallen in those days, should a candidate be held off from the day the money came?
- **Open (Kyle):** Pecan Flat adds a $20 service charge when a bill is unpaid at 1:00 p.m. on the 10th, and cuts service off. When the cut-off is held for unidentified money, is the $20 still added? Does the charge go with being unpaid at that hour, or with the cut-off itself?
- **Settled (Ryan, 2026-11-25, DECISION-LOG):** a utility cannot go live until its service level, its retention and its pledge rule are entered, so (c) is a safety net a live utility never meets. Onboarding that leaves any of them blank is refused by the core; the database keeps blocking if one is ever missing.

---

### SCN-0121 — Money resolved to the wrong customer comes back to the receipt and goes to the right one

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-23, the reversal; v5.4.2-24, the return; AC-49, AC-53).
*Rule:* a payment from a receipt that went to the wrong customer is reversed as misposted. Its money is then returned to the receipt by a recorded return naming the payment, dated on or after the reversal, for exactly what was reversed. Only then can it be posted to the right customer. Until the return is recorded, the money is on no customer's account and in no receipt's figure: it is on the list of returns owed, and a reconciliation adds that list to what receipts hold. A payment caught before it posted is voided instead, and a voided payment never took the receipt's money. Sources: design §2.3 (a misposting return gives the money back; a bounce does not); AC-49; AC-53; R-02 and CI-017.

**Given** SCN-0117's receipt, but on Fri Dec 4 the operator resolved it to **BB-16**, whose bill was $71.40, without calling. The payment posted the same day. On Mon Dec 7 BB-01 calls to say the check was theirs.

**When** (a) the payment to BB-16 is reversed on Dec 7 as misposted, the money is returned to the receipt the same day, and a payment to BB-01 is made from it; or (b) as (a), but on Dec 4 the operator had also applied the $65.83 to BB-16's bill; or (c) the operator tries to pay BB-01 from the receipt on Dec 7 before the return is recorded; or (d) the return is not recorded until Mon Dec 21; or (e) the operator catches the mistake on Dec 4, before BB-16's payment posted.

**Then**
- **(a)**

| Step | Date | BB-16 | Receipt holds | BB-01 |
|---|---|---|---|---|
| Payment to BB-16 | Dec 4 | −$65.83 | $0.00 | owes $72.42 |
| Reversal, misposted | Dec 7 | +$65.83 | $0.00 | owes $72.42 |
| Return to the receipt, naming the payment | Dec 7 | — | $65.83 | owes $72.42 |
| Payment to BB-01, customer's date Nov 28 | Dec 7 | — | $0.00 | owes $6.59, then $0.00 when the penalty is reversed |

- BB-16 owes $71.40 again, at its bill's own age. Any late penalty the payment had kept off BB-16 is the late-penalty rule's to assess now.
- BB-01's $72.42 is the bill plus SCN-0117's $6.59 penalty. The penalty is reversed as in SCN-0117 (b).
- **(b)** The same. The application to BB-16's bill is undone before the reversal, as for any reversal (`cash.md`).
- **(c)** Refused: the receipt holds $0.00 until the return. A reversal alone gives nothing back, because a bank's take-back is also recorded as a reversal, and that money is gone.
- A return of $65.84, or of $65.83 dated Dec 6, is refused.
- **(d)** From Dec 7 to Dec 20 the receipt holds $0.00, BB-16 owes $71.40, and the $65.83 is only on the list of returns owed. Bluebonnet's held total read alone is $65.83 short against the bank. Held ($0.00) plus owed back ($65.83) is $65.83, and that is what reconciles. A month-end close in that window carries no held-money line, so the reconciliation uses the two figures (limit L4). The return owed is listed for the operator once it is past the service level.
- **(e)** BB-16's payment is voided on Dec 4, before it posted. The receipt holds $65.83 again at once, with no return, and a return naming the voided payment is refused. A pending payment that is neither posted nor voided holds the receipt's money but is on no aging list: the core surfaces any such payment left pending past a day (AC-53).
- **Variant (AC-53):** BB-16 had owed nothing and the $65.83 became a credit refunded to BB-16 on Dec 5. The reversal on Dec 7 leaves BB-16 owing $65.83, the refund. The receipt still gets its money back by the return, and BB-01 is paid. Collecting from BB-16 or writing it off is the core's ordinary debt process.

---

### SCN-0122 — A held check bounces: the bank takes back what is still held, and what became a payment bounces as that payment

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-23, the bounce; v5.4.2-24, the bank's return on a receipt; AC-51 for (b)).
*Rule:* when the bank takes back money still held, the receipt records the bank's return, with the bank's code where it gave one. Money that already became a payment bounces as that payment, under the cash rules, and stays spent: it never becomes available to another customer. A bank's code learned only after a payment was reversed as misposted is not added to that payment. The money is returned to the receipt as misposted, and the bank's return is then recorded on the receipt. Sources: design §2.3 (the bank takes it back); AC-51; SCN-0084.

**Given** SCN-0118 (b) on Dec 3: PF-06 was paid $75.50 from the landlord's $120.80 check, and its $7.55 penalty reversed; the receipt still holds $45.30.

**When** (a) on Fri Dec 4 the bank returns the whole check unpaid (insufficient funds); or (b) on Dec 3 the operator, wrongly believing the $75.50 was PF-07's, reverses PF-06's payment as misposted with no bank code, and the bank's notice that the check bounced arrives on Dec 4.

**Then**
- **(a)**

| Record | Amount | Effect |
|---|---|---|
| PF-06's payment: returned check | +$75.50 on PF-06 | PF-06 owes $75.50 again, aged from Nov 20 (SCN-0084) |
| PF-06: returned-check charge, certified mail | +$25.00, +$7.00 | Pecan Flat's tariff (SCN-0084 (a)) |
| The receipt: returned by the bank | $45.30 | holds $0.00 |

- The $75.50 stays counted as spent from the receipt. A return of it to the receipt is refused, because the bank took that money.
- A bank's return on the receipt larger than the $45.30 still held is refused.
- If PF-07 is identified later, nothing is left to pay it with: PF-07's bill was never paid.
- Whether PF-06's Dec 2 penalty, reversed on Dec 3, is charged again now that the check never paid is SCN-0084's Open.
- **(b)** On Dec 4, adding the bank's code to PF-06's reversed payment is refused. The operator returns the $75.50 to the receipt as misposted (it then holds $120.80), then records the bank's return of $120.80 on the receipt with the bank's code. The receipt holds $0.00. The core records the return and the bank's return together, so the $75.50 is never available for PF-07 in between. PF-06 owes $75.50 again by the reversal, and the returned-check charges follow from the bank's return as in (a).
- **Open (Kyle):** the landlord's check bounced, but the fees fall on the tenant's account (PF-06). Is that right for a third party's check? Does PF-07 owe a fee for the part that was never posted to it?

---

### SCN-0123 — An electronic payment for an unknown account is recorded once, as a receipt, and never again as a payment

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (CI-055: v5.4.2-19 within payments, v5.4.2-24 across payments and receipts; AC-48).
*Rule:* a provider's transaction is recorded once across payments and receipts. A payment message for an account that does not exist becomes a receipt. When the processor re-sends the same transaction with a corrected account, the operator resolves the receipt; the re-sent message is not a second payment. The same holds the other way round. Sources: CI-055; design §2.1; SCN-0094 (a message received twice posts once).

**Given** on Wed Dec 2 Bluebonnet's card processor sends a $65.83 payment, transaction T-88120 (**invented**), for account 10-4471, one digit off BB-01's account number. No account 10-4471 exists. It is recorded as a receipt with the transaction id and the account as written.

**When** (a) on Thu Dec 3 the processor re-sends T-88120 with BB-01's correct account; (b) the operator instead resolves the receipt to BB-01; (c) the other order: T-88121 posts on Dec 2 as BB-01's payment, and the processor's settlement file of Dec 3 lists it again as an item with no account.

**Then**
- **(a)** Refused as a new payment: T-88120 is already recorded (as the receipt). The core's intake recognises the transaction and puts it on the receipt's work item.
- **(b)** BB-01's payment of $65.83 from the receipt, with customer's date Dec 2 (the sent date: Bluebonnet's method for an electronic payment). The payment does not carry the transaction id again; the receipt keeps it, so the transaction stays recorded once. Unlike SCN-0117, the customer's date (Dec 2) is after the due date (Dec 1), so the penalty posted on Dec 2 **stands**. Resolving a receipt does not by itself reverse a penalty.
- **(c)** Recording T-88121 as a receipt is refused: it is already recorded as a payment.
- The same transaction id from another processor is a different transaction and is not refused.

---

### SCN-0124 — A pledge from an energy-assistance agency stops a disconnection while the agency has time to pay

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. The pledge is built (CI-056, v5.4.2-24). Its protection is the collections rules' condition for a pledge (-26) and, at Gulf Plains, Texas's law row (wave 7; limit L2). Neither is written yet, so the protection below is the stream's reading of the rule, to be confirmed.
*Rule:* a pledge records the agency, the amount, the agency's date, the day the utility received it (Ryan 2026-11-25; not yet built) beside when it was keyed, the form it came in, and the agency's agreement in force on the pledge date. The database computes the date the agency must pay by from that agreement. That date never changes, even if a new agreement is entered later. Where 16 TAC §7.460(b)(2) binds, a delinquent residential customer is not disconnected "for a billing period in which the provider receives a written pledge … from an energy assistance provider that it is forwarding sufficient payment to continue service". At a city system no statute binds, and what a pledge does is the city's own rule. Sources: design §4.1; 16 TAC §7.460(b)(2); 16 TAC §7.45 (a bill is due no sooner than 15 days after issue, is delinquent if unpaid by then, and may ground a disconnection five working days after that, with notice); the CEAP vendor agreement (design source VA-26: the agency pays within 45 days; the pledged portion is not delinquent if paid in that time); memory `texas-muni-outside-gura`.

**Given**
- Gulf Plains reads meters on the 1st and bills on the 5th for the month before; a bill is due 20 days after issue (`cast.md` §3, **invented**).
- GP-06 owes the July bill (issued Wed Aug 5, due Tue Aug 25, **$47.80**) and the August bill (issued Sat Sep 5, due Fri Sep 25, **$39.60**), $87.40 in all (SCN-0081). The July bill is delinquent from Aug 26, and after notice a disconnection for its $47.80 is scheduled for Mon Sep 21 (**invented**). The August bill is not yet due.
- Gulf Plains's agreement with the Coastal Prairie Community Action Agency (CEAP, `cast.md` §5): 45 days to pay, 5 business days' hold.
- The agency's letter pledging **$87.40** (both bills, the agency's choice), dated Thu Sep 10, reaches Gulf Plains on Fri Sep 11 and is keyed that day.

**When** (a) the pledge is recorded on Sep 11; (b) the same, but the agency had phoned on Sep 9 and the letter follows on Sep 16; (c) on Thu Oct 1 Gulf Plains enters a new agreement with Coastal Prairie, 60 days to pay, and the agency pledges again for another customer on Fri Oct 2; (d) a pledge of PF-01's $75.50 reaches Pecan Flat from the Mesquite County Community Action Agency (`cast.md` §5).

**Then**
- **(a)** The pledge: $87.40; pledged Sep 10; received Sep 11, keyed Sep 11; written; Coastal Prairie's agreement in force on Sep 10; **pay by Sun Oct 25** (Sep 10 + 45 days). An app that sends its own agreement or pay-by date is refused.
- It reads *open* to Oct 25, and *overdue* from Oct 26 if not paid in full (SCN-0126).
- The Sep 21 disconnection is not carried out. The pledge was received in the billing period Sep 1 – Sep 30 (read Oct 1, billed Oct 5), which Sep 21 also falls in, and the $87.40 pledged is more than the $47.80 delinquent.
- **(b)** By its text §7.460(b)(2) needs a written notice, so the phone call alone does not protect at Gulf Plains. A pledge recorded as "verbal" on Sep 9 reads as such. When the letter comes on Sep 16, the record cannot change the pledge's form: the operator records the letter as a pledge of its own, received Sep 16, and the phone pledge in error.
- **(c)** The Sep 10 pledge still reads pay by Oct 25. The Oct 2 pledge takes the new agreement: pay by Tue Dec 1.
- **(d)** At Pecan Flat no statute binds and the source tariff says nothing about pledges. Whether the pledge stops a cut-off there is Pecan Flat's own rule, stated at go-live (below). The 45-day term is recorded either way, pay by Jan 4, 2027 if the pledge is dated Nov 20.
- **Open (Kyle):** the protection lasts "for a billing period", here to Sep 30, while the agency has to Oct 25. If the pledge is unpaid on Oct 1, may Gulf Plains disconnect for the July bill? Or does the agreement's "not delinquent if paid within 45 days" hold the pledged amount to Oct 25? The agreement is between the agency and the utility, not a rule the customer holds.
- **Open (Kyle):** "sufficient payment to continue service". A pledge of $30.00 against the $47.80 delinquent: does it protect? The vendor agreement says a short pledge does not oblige a *reconnection*.
- **Open (Kyle):** does a pledge entered in the agency's web portal count as "other written notification"?
- **Open (Kyle):** the pay-by date, Oct 25, is a Sunday. Does the agency have until Monday?
- **Open (Kyle):** the vendor agreement keeps service on for up to five business days while the agency checks eligibility, before any pledge exists. Nothing records "the agency is checking this customer": a pledge needs an amount. How do the utilities learn of it, and what should hold the cut-off in those days? (Board note to money.)
- **Settled (Ryan, 2026-11-25, DECISION-LOG): a pledge carries the day the utility received it**, entered by the operator, no earlier than the agency's date and no later than the day it is keyed, written once; the protection reads it, and the keying stamp stays as the audit trail. A letter that arrives Wed Sep 30 and is keyed Thu Oct 1 reads as received Sep 30, in September's period. **Not yet built** (money's patch): until it is, the record holds only the keying time.
- **Settled (Ryan, 2026-11-25, DECISION-LOG):** a city states its pledge rule before it goes live, even if the rule is "a pledge gives no protection", so (d) never meets a silent tariff on a live utility. Pecan Flat's rule is not yet in the cast: until a scenario needs it, (d) shows only what is recorded.
- **Open (Kyle, for city systems):** what do the cities do with a pledge in practice: follow the CEAP agreement's 45 days, or something else?

---

### SCN-0125 — Two agencies pledge for the same customer, and each pays only its own pledge

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-24; D7-1, an agency's restriction on the payment).
*Rule:* several pledges coexist, of different agencies or the same one. A payment naming a pledge must be of that pledge's agency and customer, and every agency payment names its agency. A pledge made toward one bill limits its payment to that bill. A pledge counts as paid by what its payments have brought and not taken back: a pending payment counts nothing yet, and one that bounces or is reversed counts nothing. Which agency wrote a check is the operator's to key right: the database cannot tell. Sources: design §4.1–§4.3 (several pledges; a key, not a name); D7-1 (an agency payment's restriction wins over the posting order); CI-064.

**Given** GP-06's two bills (SCN-0124). Here, in place of SCN-0124's pledge, there are two pledges. Coastal Prairie's, dated Thu Sep 10 and received Sep 11, is **$47.80** toward the July bill, pay by Sun Oct 25. St. Brigid's Helping Hands (a charity, `cast.md` §5) pledges **$39.60** toward the August bill on Mon Sep 14, pay by Wed Oct 14 (Sep 14 + 30 days).

**When** (a) Coastal Prairie's check of $47.80 naming its pledge posts on Tue Oct 20; (b1) St. Brigid's sends $39.60 on Oct 2, and the clerk names St. Brigid's pledge but keys the agency as Coastal Prairie; (b2) the clerk keys St. Brigid's check wholly as Coastal Prairie's: that agency, its pledge, toward the July bill; (c) St. Brigid's payment of $39.60 is keyed toward the July bill; (d) after (a), Coastal Prairie's check is returned unpaid on Wed Oct 28.

**Then**
- **(a)** Coastal Prairie's pledge reads *paid* from Oct 20. The payment is restricted to the July bill and pays it.
- **(b1)** Refused: a payment naming St. Brigid's pledge must be St. Brigid's. A payment marked as an agency's with no agency named is also refused.
- **(b2)** Accepted. Coastal Prairie's pledge reads paid with St. Brigid's money, and a later refund of any of it would go to Coastal Prairie. Matching a check's signer to its agency is the core's and the operator's; the reconciliation with each agency is where it shows.
- **(c)** Refused: St. Brigid's pledge is toward the August bill, so its payment is restricted to that bill.
- **(d)** The pledge read *paid* from Oct 20 to Oct 27. From Oct 28 the bounce leaves it unpaid, and it is past its pay-by date, so it reads *overdue*. The core may record its lapse, dated Oct 28. The July bill is delinquent again under the cash rules. **Open (Kyle):** does GP-06 get a fresh notice before a disconnection for the July bill resumes?
- The two pledges are listed separately on the open-pledge list, each with its own pay-by date. A second pledge from the same agency is also allowed.

---

### SCN-0126 — A pledge not paid in full lapses: what was paid is on record, the rest is the customer's, and late money is still taken

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-24). Recording the lapse is the core's, once the date has passed.
*Rule:* a pledge ends once: withdrawn by the agency, lapsed after its pay-by date, or recorded in error. A lapse can be recorded only once the pay-by date has passed everywhere, and is dated after it. A pledge paid in full can be neither withdrawn nor lapsed. Money an agency sends after the pledge lapsed is still taken and still names it, and full payment outranks the lapse. A pledge cannot be recorded in error while any payment that was not voided names it. Sources: design §4.2; VA-26 ("the gap is the customer's"); CI-056 (a pledge made and not honoured stays on record).

**Given** SCN-0124 (a): Coastal Prairie's $87.40 pledge for GP-06, pay by Sun Oct 25.

**When** (a) the agency pays **$50.00** on Tue Oct 20 and nothing more by Oct 25; (b) as (a), and the agency's remaining $37.40 arrives on Mon Nov 2; (c) apart from (a), on Fri Sep 18 the agency withdraws the pledge (the customer was found ineligible); (d) apart from (a), the operator finds the pledge was keyed for GP-06 but meant for another customer, GP-07 (**invented**).

**Then**
- **(a)** From Oct 26 the pledge reads *overdue*: $50.00 paid, $37.40 outstanding. The core records the lapse dated Mon Oct 26, with a reason. From then on it reads *lapsed*, still $37.40 outstanding, and leaves the open-pledge list. A lapse dated Oct 25, or recorded before Oct 25 has ended everywhere, is refused. GP-06 owes the rest with no pledge behind it, and the collections rules may act on it.
- **(b)** The $37.40 is taken and names the pledge. The pledge reads *paid* ($87.40 of $87.40) from Nov 2, and its history keeps the lapse on Oct 26.
- **(c)** The withdrawal records the agency's reason and reference, dated Sep 18. The pledge protects nothing from Sep 18, so the Sep 21 disconnection is the collections rules' to decide again.
- **(d)** Before any payment names it, the pledge is recorded in error and never counted, and the operator records a new pledge for GP-07. A payment that was voided before it posted does not stop this. After the agency's $50.00 has posted, recording the pledge in error is refused, even once the payment is reversed as misposted: the money was real and names it. The operator reverses the $50.00 off GP-06 under the cash rules and withdraws the pledge, with the keying error as the reason. The record offers no other way out, so the reason carries the truth (board note to money). The operator then records a new pledge for GP-07, and the agency's $50.00 is posted there as a new agency payment naming it. GP-06's history shows a pledge that protected it from Sep 11 until the withdrawal.
- A second ending of the same pledge is refused. Once (a)'s lapse is recorded, (d)'s withdrawal is refused too.

---

### SCN-0127 — An agency's leftover money goes back to the agency, never to the customer

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. The database enforces this for refunds of payments, overpayment credits and the two reissues (v5.4.2-24). It does not for a deposit or another kind of credit (limits L5, L6; AC-52), where the core must.
*Rule:* an agency's money may pay the customer's bills, and what is left of it may be held as a credit for later bills. A refund of it goes to the agency, never to the customer or another agency. A refund of the customer's own money names no agency. The core never moves an agency's money into a credit the database cannot trace back to the agency. Sources: Ryan 2026-11-07 (DECISION-LOG: for every agency; the two limits recorded as limits); 10 TAC §6.312(f) ("a Vendor Refund … must be reimbursed to the Subrecipient, and not the customer"); VA-26; CI-053.

**Given** GP-06 owes $87.40 for the July and August bills. Coastal Prairie's pledge is $87.40, but on Oct 20 its check is for **$100.00**, more than it pledged, restricted by the agency to the July and August bills (D7-1). The pledge reads *paid*. Because of the restriction, the **$12.60** left on the agency's payment cannot pay the September bill. It is neither applied nor approved as a credit (SCN-0082's Open: who is asked when an agency's check overpays?). GP-06 moves out on Mon Dec 14 and pays its final bill itself.

**When** (a) the $12.60 is refunded on Dec 14; (b) GP-06 had also overpaid its own check by $5.00 in September, and that is refunded too; (c) the agency had paid GP-06's deposit, which is returned at move-out; (d) GP-06 has a second account, and the operator tries to move the agency's $12.60 there as a transfer credit.

**Then**
- An agency that sends more than it pledged is not refused, because the money is real.
- **(a)** The refund of $12.60 names Coastal Prairie as its payee. A refund of it to GP-06, or to St. Brigid's, is refused. The same holds if the $12.60 had first become a credit (with approval) and the credit is refunded, or the credit was reissued after an uncashed refund.
- **(b)** The $5.00 refund goes to GP-06 and names no agency. One naming an agency is refused.
- **(c)** The database does not trace an agency's money into a deposit (limit L5). The core returns the deposit, after anything owed, to the agency (VA-26; AC-52).
- **(d)** The core refuses the transfer (AC-52). The database would accept it, and a refund of the transferred credit would then read as GP-06's own money and go to GP-06 (limit L6).
- **Open (Kyle):** R-06 holds a leftover as a credit only with the customer's approval. Is it the customer's approval or the agency's that lets an agency's leftover pay later bills?

---

### SCN-0128 — A pledge whose agreement is not yet on file is still recorded, and blocks the act that reads it

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-24).
*Rule:* a pledge from an agency with no agreement in force on the pledge date is recorded with no agreement and no pay-by date, rather than refused, so the customer has a record of it. It cannot lapse. To the collections rules it is unevaluable, which blocks the act. The agreement is chosen once, when the pledge is recorded. An agency retired from the platform takes no new pledge or agreement, but its money is still taken. Sources: design §4.1 (fail toward protection; -26 reads "no agreement" as unevaluable); §3 (an agency is retired, never deleted).

**Given** Bluebonnet takes its first pledge from the Bluebonnet Area Ministries food pantry (a charity, `cast.md` §5) for BB-09: **$60.00**, dated Tue Dec 8 (**invented**), before Bluebonnet has entered an agreement with it.

**When** (a) the pledge is recorded on Dec 8; (b) on Thu Dec 17 the agreement (30 days, in force from Dec 1) is entered; (c) Bluebonnet retires the pantry from its list in 2027 while a pledge of it is open.

**Then**
- **(a)** Recorded with no agreement and no pay-by date; it reads as having no agreement. It heads the open-pledge list. A disconnection of BB-09 that reads it is blocked, because the condition cannot be evaluated. A lapse is refused, because it has no pay-by date.
- **(b)** The existing pledge keeps no agreement: the agreement is chosen when a pledge is recorded and never changes. To give it a pay-by date, the operator records it in error (no payment names it yet) and records it again, dated Dec 8. The new pledge takes the Dec 1 agreement, **pay by Thu Jan 7, 2027**. The cost: the history shows an error that was not one. The new pledge keeps its true received day, Dec 8, though it is keyed on Dec 17 (SCN-0124, Ryan 2026-11-25).
- **(c)** The retirement is a stamp, with who and why. A new pledge or agreement of the pantry is refused. The open pledge stands, and the pantry's payment toward it is taken.

---

### SCN-0129 — An agency's remittance for several customers: what can be matched pays the pledges, and the rest is held as the agency's

*Status:* draft (2026-11-25); in batch 6 for Kyle (K-19), not yet sent. Built (v5.4.2-24); matching a batch line to a pledge is the core's (limit L3).
*Rule:* an agency's check covering several customers is split into payments, one per pledge, each naming the agency and its pledge. A line that matches no customer is held as a receipt that names the agency, and any payment made from it later is that agency's. The leftover rule then follows the money (SCN-0127). Sources: design §2.1 (a remitting agency on the receipt), §4.3; limits L1 and L3.

**Given** Pecan Flat's agreement with the Mesquite County Community Action Agency (CEAP, `cast.md` §5). Open pledges: PF-01 $75.50, dated Fri Nov 20 (pay by Mon Jan 4, 2027), and PF-02 $40.00, dated Mon Nov 23 (pay by Thu Jan 7, 2027). On Mon Dec 7 the agency's check for **$180.30** arrives with a list of three names: PF-01 $75.50, PF-02 $40.00, and "D. Reyes" $64.80, whom Pecan Flat cannot find (**invented**). PF-06 owes $64.80 here (**invented**) and has no pledge on record.

**When** (a) the remittance is recorded on Dec 7; (b) on Dec 14 the agency says "D. Reyes" is PF-06, whose account is in another household member's name; (c) Pecan Flat's cut-off list is drawn on Thu Dec 10, with PF-06's bill unpaid.

**Then**
- **(a)** Two agency payments, PF-01 $75.50 and PF-02 $40.00, each naming its pledge. Both pledges read *paid*. A receipt of $64.80 names the agency, with the list line as evidence. The check reconciles: $75.50 + $40.00 + $64.80 = $180.30.
- **(b)** PF-06's payment of $64.80 from the receipt is the agency's, naming the agency and no pledge. A payment from that receipt marked as the customer's own is refused.
- **(c)** The receipt is 3 days old, not aged, and lists no candidate, so nothing bars the cut-off: PF-06 is cut off on Dec 10 while the agency's money for it sits held. This is limit L1, and SCN-0120's first Open.
- **Open (Kyle):** should intake list as candidates every customer with an open pledge from the agency that sent the money, or every customer the agency is known to serve?
- **Open (Kyle):** the agency paid for a customer with no pledge on file. Should the core ask the agency for the pledge, or is the payment enough?
