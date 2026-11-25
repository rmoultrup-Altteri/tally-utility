# Unmatched cash and agency pledges

Money the utility holds but cannot yet attribute to a customer, and pledges from assistance agencies. Invariants: CI-053 (no silent drop, no guessed account, no revenue; refund to whoever sent it), CI-055 (money recorded once), CI-056 (pledges and held money are worked within a service level; past it the system fails loud), CI-058 (the customer's date). Built by v5.4.2-24 (mirrored 2026-11-24, Ryan; design `application/wave2-build-2026-10-15/v5.4.2-24-design.md`; what the core must do, AC-48 to AC-53). Payments, refunds and bounces in general are `cash.md`; a customer's own money with no bill to pay (an overpayment) is SCN-0082, not this family.

**Common to every scenario here.**
- **Held money is not a customer's money.** Money nobody can attribute is held as a *receipt*: on no customer's ledger, earning nothing, never revenue. It leaves only by an operator's recorded act. It can become one or more payments of identified customers (with a reason and the operator), go back to whoever sent it, be taken back by the bank, or be reported as unclaimed property. What a receipt still holds is the amount, less what went to payments and what was disposed of, plus what came back. It is worked out, never stored.
- **A candidate is evidence, not an application.** Intake or an operator may list customers the money might belong to. Nothing moves on a candidate, and no guard reads one except the disconnection bar (SCN-0120).
- **What the database refuses and what the core decides.** The database refuses a payment or disposition past what a receipt holds (on every date), a second record of one provider transaction, a payment from a receipt dated before the money came or effective after it, and an agency payment that names no agency. It also refuses a refund of an agency's money to anyone but the agency, and a pledge's agreement or pay-by date sent by the app. Matching, the operator queue, when retention or the service level has run out, a pledge's lapse, the unclaimed-property timing and which acts a pledge or aged receipt bars are the core's, read from the records here and from the collections rules (-26; wave 7's law rows).
- **Dates are 2026 unless stated.** The utilities' suspense settings and agencies are in `cast.md` ("Held money and agencies"). Every agency and agreement is **invented**.
- **Customers used only here (invented):** **PF-06** and **PF-07** (Pecan Flat, two rented houses with the same landlord), **BB-16** (Bluebonnet, homeowner inside the city, R-U; a name like BB-01's). GP-06 and BB-09 are `cash.md`'s.

---

### SCN-0117 — A lockbox check with no account number is held, never guessed, and keeps the day it came

*Status:* draft (2026-11-25), not yet sent to Kyle. The receipt is built (CI-053, v5.4.2-24); the late-penalty rules are not (R-11).
*Rule:* money that cannot be attributed is held as a receipt with its evidence, apart from every customer, however good a guess looks. When it is identified it becomes that customer's payment, posted in the open period. The payment's customer's date is no later than the day the money came, so a customer who paid on time stays on time. Sources: Ryan 10-16 (suspense is never applied to a guessed account); CI-053; CI-058; design §2.3; SCN-0034 (a penalty reversed when the payment proves on time).

**Given**
- BB-01 owes the reference bill, **$65.83**, issued Mon Nov 16, due Tue Dec 1 (`cash.md`). BB-16 owes $71.40 (**invented**).
- Bluebonnet's lockbox file of Wed Dec 2 holds 40 items totalling $3,912.66 (**invented**). Thirty-nine match an account. The fortieth is a check for **$65.83**, signed "R. Alvarez", postmarked Sat Nov 28, with no account number and no stub. BB-01 and BB-16 are both named Alvarez (**invented**).
- Intake lists both as candidates: BB-01 because the amount equals its open bill, BB-16 by name only.
- On Wed Dec 2 the late penalty posts on BB-01's unpaid bill: $6.52 and city sales tax $0.07, **$6.59** (`cancel-rebill.md` SCN-0033's figures).

**When** (a) the file is loaded on Dec 2; (b) on Fri Dec 4 the operator reaches BB-01, who confirms the check, and resolves the receipt to BB-01.

**Then**
- **(a)** The 39 items post as payments, and the fortieth is a receipt of $65.83, received Dec 2, with the payer's name, the check number and the file row as evidence. The file reconciles: $3,846.83 in payments plus $65.83 held is $3,912.66. BB-01's and BB-16's ledgers do not change. Bluebonnet holds **$65.83** in suspense. Posting it to BB-01 because the amount matches is the core's to refuse: it is a guess (CI-053), and the database holds no rule that would catch it.
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
- Refused: the payment dated before Dec 2 (money is dated no earlier than it came); a customer's date after Dec 2 (the money was here by then); a payment from the receipt with no reason or no operator.
- Had the check come on Mon Nov 30 and November been closed before it was identified, the payment would still be posted in December, the open period, with customer's date Nov 28: a closed month does not stop held money from being resolved.
- **Open (Kyle):** the penalty posted on Dec 2 while the utility already held the customer's money unidentified. Should the core hold penalties on a receipt's candidates until it is resolved, or post and reverse them as here?

---

### SCN-0118 — One check pays two accounts, and nothing past what it holds

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-24).
*Rule:* one receipt may become several payments of different customers, each with its reason. Together they never exceed the receipt, on any date. Money not yet identified stays held, and its age runs from the day it came, not from the day part of it was resolved. A landlord's or relative's check is the customer's own payment, not an agency's. Sources: design §2.3 (the cap, the household paying two accounts); CI-053.

**Given**
- PF-06 owes $75.50, issued Nov 20, due Tue Dec 1: 5.0 Mcf × $9.00 = $45.00, and gas 5.0 Mcf × $6.10 = $30.50 (SCN-0084's bill). PF-07 owes **$45.30**: 3.0 Mcf × $9.00 = $27.00, and gas 3.0 Mcf × $6.10 = $18.30 (usage **invented**). Both are residential, so neither bill carries tax (`cast.md` §1).
- On Fri Nov 27 the landlord's check for **$120.80**, with no stub, reaches the counter. It is recorded as a receipt with the landlord's name and the check number.

**When** (a) on Thu Dec 3 the landlord's office says it is for both houses, and the operator makes two payments from it; or (b) on Dec 3 the office names only PF-06, and PF-07 is identified on Tue Dec 8.

**Then**
- **(a)**

| Payment | Account | Amount | Customer's date | Receipt holds after |
|---|---|---|---|---|
| 1 | PF-06 | $75.50 | Nov 27 | $45.30 |
| 2 | PF-07 | $45.30 | Nov 27 | $0.00 |

- Both bills were paid by the 1st, so neither takes Pecan Flat's 10% penalty.
- A third payment from the receipt, of any amount, is refused. So is payment 2 for $45.31 instead of $45.30.
- **(b)** On Dec 3 the receipt holds $45.30. It is 6 days old on Dec 3 (counted from Nov 27, not from the first resolution) and 11 on Dec 8, past Pecan Flat's 10-day service level from Dec 8 (SCN-0120). On Dec 2 PF-07's bill was unpaid on the books, so its penalty posts: 10% × $45.30 = **$4.53**. It is reversed when payment 2 is posted on Dec 8 with customer's date Nov 27, as in SCN-0117 (b).
- Each payment is the customer's own, not an agency's, so a later refund of it goes to the customer (SCN-0127 (b)).

---

### SCN-0119 — Money nobody claims goes back to whoever sent it, or to the state, and never to revenue

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-24); when the state's dormancy period ends is the core's, read from the state's rule.
*Rule:* once the utility's retention period has passed, held money is returned to whoever sent it if they can be found, or reported as unclaimed property. A return sent but not cashed is undone, and the money is held again. Nothing happens on a clock: the core flags the receipt past retention, and an operator acts. Sources: CI-053 (refund to the originating party after the tenant's retention; escheat per jurisdiction); design §2.3 and §2.4; Texas Property Code ch. 74 (a holder reports property whose owner is unknown).

**Given** Bluebonnet's retention is 180 days (`cast.md`). Two receipts are never identified (**invented**):
- **R1:** a check for $38.00 received Wed Dec 2, from "M. Ortiz, 1410 Pecan St." Bluebonnet has no account at that address or under that name.
- **R2:** $20.00 in cash in the night drop on Dec 2, in an envelope marked only "gas".

**When** (a) the core runs its daily check on Mon May 31, 2027 and on Tue Jun 1, 2027; (b) on Jun 1 the operator sends R1's $38.00 back by check; (c) that check comes back undeliverable on Jul 6, 2027; (d) R1 and R2 are reported to the state on the next annual report.

**Then**
- **(a)** On May 31, 2027 each receipt is 180 days old and not past retention; on Jun 1, 2027 it is 181, and both are listed as past retention. Nothing moves until an operator acts. Retention unset at Bluebonnet would not block the listing; it would show "past retention" as unknown.
- **(b)** R1: a return to sender of $38.00, dated Jun 1, 2027, with the outgoing check number and a reason. It now holds $0.00.
- **(c)** R1: an undo of $38.00 naming the return, dated Jul 6, 2027. It holds $38.00 again. A second undo of the same return is refused: nothing is left of it. An undo of an undo is refused.
- **(d)** Each receipt: a disposition "reported as unclaimed property", jurisdiction TX, with the report's reference, for what it still holds ($38.00; $20.00). Each then holds $0.00. A report with no jurisdiction or no reference is refused. Neither receipt ever reaches a customer's ledger or the utility's revenue.
- R2 has no sender to return it to, so it can only be held or reported.
- **Open (Kyle):** Texas's dormancy period for a utility's money with no known owner, and whether the retention setting should be set to match it, so the operator sees one deadline, not two.

---

### SCN-0120 — Held money past the service level bars disconnecting the customers it might belong to

*Status:* draft (2026-11-25), not yet sent to Kyle. The aged list and its candidates are built (CI-056, v5.4.2-24); the bar on disconnection is the collections rules' (-26 `aged_suspense`; wave 7's rule data).
*Rule:* a receipt still holding money past the utility's service level is aged: it is listed for the operator, oldest first, with its candidates, and it bars a disconnection of each candidate. A customer nobody listed is not protected. While a utility's service level is unset, which receipts are aged cannot be known: the reader refuses and the collections rule treats the bar as unevaluable, so the disconnection waits. Sources: CI-056 (fail loud: an operator surface, a disconnection pause); design §2.4; limit L1 (candidates are as good as intake made them).

**Given**
- Pecan Flat's service level is 10 days (`cast.md`). PF-07's receipt from SCN-0118 (b) is not resolved: $45.30, received Fri Nov 27, candidate PF-07, by the landlord's name.
- PF-07's $45.30 is still unpaid on the 10th, so Pecan Flat's cut-off at 1:00 p.m. on Thu Dec 10 applies (`cast.md` §1).

**When** the cut-off list is drawn on Dec 10; or (b) the same, but intake listed no candidate; or (c) the same, but Pecan Flat has never set its service level.

**Then**
- Day by day: the receipt is 10 days old on Mon Dec 7, not aged; it is 11 on Tue Dec 8, and aged from then.
- **(a)** On Dec 10 the receipt is aged and PF-07 is its candidate: PF-07 is held off the cut-off list, and the hold names the receipt. The $20 service charge is not added. When the receipt is resolved to PF-07 the bill is paid, as of Nov 27.
- **(b)** Nothing links the receipt to PF-07. PF-07 is cut off, and the aged receipt is on the operator's list with no candidate. This is the known limit: the record cannot prevent it.
- **(c)** The aged list refuses to run at Pecan Flat. To the cut-off rule the bar is unevaluable, so **no** Pecan Flat customer is cut off until the setting is entered. That blocks every account, not only PF-07.
- **Open (Kyle):** between Nov 27 and Dec 8 the receipt is within its service level, so nothing bars a cut-off of PF-07. Had the cut-off date fallen in those days, should a candidate be held off from the day the money came?
- **Open (Ryan):** (c) blocks every account at a utility for a missing setting. The alternative is to require the setting when a utility goes live (onboarding), which needs no schema change.

---

### SCN-0121 — Money resolved to the wrong customer comes back to the receipt and goes to the right one

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-23, the reversal; v5.4.2-24, the return; AC-53).
*Rule:* a payment from a receipt that went to the wrong customer is reversed as misposted. Its money is then returned to the receipt by a recorded return naming the payment, dated on or after the reversal, for exactly what was reversed. Only then can it be posted to the right customer. If the wrong customer's resulting credit was already refunded, that customer owes the refund as an ordinary debt. Sources: design §2.3 (a reversal gives the money back; a bounce does not); AC-53; R-02 and CI-017.

**Given** SCN-0117's receipt, but on Fri Dec 4 the operator resolved it to **BB-16**, whose bill was $71.40, without calling. On Mon Dec 7 BB-01 calls to say the check was theirs.

**When** (a) the payment to BB-16 is reversed on Dec 7 as misposted, the money is returned to the receipt the same day, and a payment to BB-01 is made from it; or (b) as (a), but on Dec 4 the operator had also applied the $65.83 to BB-16's bill; or (c) the operator tries to pay BB-01 from the receipt on Dec 7 before the return is recorded.

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
- **Variant (AC-53):** BB-16 had owed nothing and the $65.83 became a credit refunded to BB-16 on Dec 5. The reversal on Dec 7 leaves BB-16 owing $65.83, the refund. The receipt still gets its money back by the return, and BB-01 is paid. Collecting from BB-16 or writing it off is the core's ordinary debt process.

---

### SCN-0122 — A held check bounces: the bank takes back what is still held, and what became a payment bounces as that payment

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-23, the bounce; v5.4.2-24, the bank's return on a receipt; AC-51).
*Rule:* when the bank takes back money still held, the receipt records the bank's return, with the bank's code where it gave one. Money that already became a payment bounces as that payment, under the cash rules, and the bank's take-back stays spent: it never returns to the receipt. Sources: design §2.3 (kind 3); AC-51; SCN-0084.

**Given** SCN-0118 (b) on Dec 3: PF-06 was paid $75.50 from the landlord's $120.80 check; the receipt still holds $45.30.

**When** on Fri Dec 4 the bank returns the whole check unpaid (insufficient funds).

**Then**

| Record | Amount | Effect |
|---|---|---|
| PF-06's payment: returned check | +$75.50 on PF-06 | PF-06 owes $75.50 again, aged from Nov 20 (SCN-0084) |
| PF-06: returned-check charge, certified mail | +$25.00, +$7.00 | Pecan Flat's tariff (SCN-0084 (a)) |
| The receipt: returned by the bank | $45.30 | holds $0.00 |

- The receipt's $75.50 stays counted as spent. A return of it to the receipt is refused, because the bank took that money.
- A bank's return on the receipt larger than the $45.30 still held is refused.
- If PF-07 is identified later, nothing is left to pay it with: PF-07's bill is unpaid as of Nov 27.
- **Open (Kyle):** the landlord's check bounced, but the fees fall on the tenant's account (PF-06). Is that right for a third party's check, and does PF-07 owe a fee for the part that was never posted to it?

---

### SCN-0123 — An electronic payment for an unknown account is recorded once, as a receipt, and never again as a payment

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (CI-055, v5.4.2-23 and -24; AC-48).
*Rule:* a provider's transaction is recorded once across payments and receipts. A payment message for an account that does not exist becomes a receipt. When the processor re-sends the same transaction with a corrected account, the operator resolves the receipt; the re-sent message is not a second payment. Sources: CI-055; design §2.1; SCN-0094 (a message received twice posts once).

**Given** on Wed Dec 2 Bluebonnet's card processor sends a $65.83 payment, transaction T-88120 (**invented**), for account 10-4471, one digit off BB-01's account number. No account 10-4471 exists. It is recorded as a receipt with the transaction id and the account as written.

**When** (a) on Thu Dec 3 the processor re-sends T-88120 with BB-01's correct account; (b) the operator instead resolves the receipt to BB-01.

**Then**
- **(a)** Refused as a new payment: T-88120 is already recorded (as the receipt). The core's intake recognises the transaction and puts it on the receipt's work item.
- **(b)** BB-01's payment of $65.83 from the receipt, customer's date Dec 2 (the sent date: Bluebonnet's method for an electronic payment). The payment does not carry the transaction id again; the receipt keeps it, so the transaction stays recorded once. BB-01's penalty posted on Dec 2 is the core's to reverse, as in SCN-0117: the bill was due Dec 1, so paying on Dec 2 was late, and **the penalty stands**.
- The same transaction id from another processor is a different transaction and is not refused.

---

### SCN-0124 — A pledge from an energy-assistance agency stops a disconnection while the agency has time to pay

*Status:* draft (2026-11-25), not yet sent to Kyle. The pledge is built (CI-056, v5.4.2-24); its protection is the collections rules' (-26 `agency_pledge`) and, at Gulf Plains, Texas's law row (wave 7; limit L2).
*Rule:* a pledge records the agency, the amount, the agency's date, when the utility received it, the form it came in, and the agency's agreement in force on the pledge date. The database computes the date the agency must pay by from that agreement, and it never changes. Where 16 TAC §7.460(b)(2) binds, a delinquent residential customer is not disconnected for the billing period in which the utility receives a written pledge. At a city system the protection is whatever its own tariff says, and the platform holds no Texas default. Sources: design §4.1; 16 TAC §7.460(b)(2); the CEAP vendor agreement (design source VA-26: the agency pays within 45 days; the pledged portion is not delinquent if paid in that time); memory `texas-muni-outside-gura`.

**Given**
- GP-06 owes the July bill (issued Aug 5, **$47.80**) and the August bill (issued Sat Sep 5, **$39.60**), **$87.40** in all (SCN-0081). A disconnection for nonpayment is scheduled for Mon Sep 21 (**invented**). Gulf Plains bills monthly around the 5th (**invented**).
- Gulf Plains's agreement with the Coastal Prairie Community Action Agency (CEAP, `cast.md`): 45 days to pay, 5 business days' hold.
- The agency's written pledge of **$87.40**, dated Thu Sep 10, reaches Gulf Plains on Fri Sep 11.

**When** the pledge is recorded on Sep 11; (b) the same pledge reaches Pecan Flat for PF-01, from the Mesquite County Community Action Agency under its CEAP agreement with Pecan Flat (`cast.md`).

**Then**
- **(a)** The pledge: $87.40; pledged Sep 10; received Sep 11 (the database's time); written; agreement Coastal Prairie's of Jan 1, 2026; **pay by Sun Oct 25** (Sep 10 + 45 days). An app that sends its own agreement or pay-by date is refused.
- It reads *open* to Oct 25 and *overdue* from Oct 26 if not paid in full.
- The Sep 21 disconnection is not carried out. The pledge reached Gulf Plains in the billing period of the Sep 5 bill, and §7.460(b)(2) bars a disconnection for that period. The CEAP agreement also makes the pledged $87.40 not delinquent until Oct 25.
- **(b)** At Pecan Flat no state rule binds and the source tariff says nothing about pledges. Until Pecan Flat records a rule, the collections rule cannot evaluate the pledge and so blocks the disconnection (limit L2). The 45-day contract term is recorded all the same.
- **Open (Kyle):** "the billing period in which the provider receives" the pledge. Here that is the Sep 5 bill's period, which ends around Oct 4, three weeks before the agency's Oct 25. If the pledge is unpaid on Oct 5, may Gulf Plains disconnect for the pledged amount, or does the agreement's "not delinquent" hold it to Oct 25?
- **Open (Kyle):** §7.460(b)(2) speaks of a pledge of "sufficient payment to continue service". Is a pledge of less than the past-due amount (say $50.00 of $87.40) a protecting pledge? The vendor agreement says a short pledge does not oblige a *reconnection*.
- **Open (Kyle):** does a pledge by phone (the form "verbal") protect? The rule says written. The record carries the form either way.
- **Open (Kyle, for city systems):** what do the cities do with a pledge when their tariff is silent: follow the CEAP agreement's 45 days, or something else?

---

### SCN-0125 — Two agencies pledge for the same customer, and each pays only its own pledge

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-24; D7-1, an agency's restriction on the payment).
*Rule:* several pledges coexist, of different agencies or the same one. A payment naming a pledge must be of that pledge's agency and customer, and every agency payment names its agency. A pledge made toward one bill limits its payment to that bill. A pledge counts as paid by what its payments have brought and not taken back. Sources: design §4.1–§4.3 (several pledges; a key, not a name); D7-1 (an agency payment's restriction wins over the posting order); CI-064.

**Given** GP-06's $87.40 (SCN-0124 (a)). Coastal Prairie's pledge, dated Thu Sep 10 and received Sep 11, is **$47.80** toward the July bill, pay by Sun Oct 25. On Mon Sep 14 St. Brigid's Helping Hands (a charity, `cast.md`) pledges **$39.60** toward the August bill, pay by Wed Oct 14 (Sep 14 + 30 days).

**When** (a) Coastal Prairie's check of $47.80 naming its pledge posts on Tue Oct 20; (b) St. Brigid's sends $39.60 on Oct 2, but the clerk keys it as Coastal Prairie's; (c) St. Brigid's payment of $39.60 is keyed toward the July bill.

**Then**
- **(a)** Coastal Prairie's pledge reads *paid* from Oct 20. The payment is restricted to the July bill and pays it.
- **(b)** Refused: a payment naming St. Brigid's pledge must be St. Brigid's. A payment marked as an agency's with no agency named is also refused.
- **(c)** Refused: St. Brigid's pledge is toward the August bill, so its payment is restricted to that bill.
- While a payment is pending (not yet cleared) it does not count toward its pledge; one that bounces or is reversed counts nothing.
- The two pledges are listed separately on the open-pledge list, each with its own pay-by date. A second pledge from the same agency is also allowed.

---

### SCN-0126 — A pledge not paid in full lapses: what was paid is on record, the rest is the customer's, and late money is still taken

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-24); recording the lapse is the core's, once the date has passed.
*Rule:* a pledge ends once: withdrawn by the agency, lapsed after its pay-by date, or recorded in error. A lapse can be recorded only once the pay-by date has passed everywhere, and is dated after it. A pledge paid in full can be neither withdrawn nor lapsed. Money an agency sends after the pledge lapsed is still taken and still names it. A pledge cannot be recorded in error once a payment names it. Sources: design §4.2; VA-26 ("the gap is the customer's"); CI-056 (a pledge made and not honoured stays on record).

**Given** SCN-0124 (a): Coastal Prairie's $87.40 pledge, pay by Sun Oct 25.

**When** (a) the agency pays **$50.00** on Tue Oct 20 and nothing more by Oct 25; (b) as (a), and the agency's remaining $37.40 arrives on Mon Nov 2; (c) on Sep 18 the agency withdraws the pledge (the customer was found ineligible); (d) the operator finds the pledge was keyed for the wrong customer.

**Then**
- **(a)** From Oct 26 the pledge reads *overdue*: $50.00 paid, $37.40 outstanding. The core records the lapse dated Mon Oct 26, with a reason. A lapse dated Oct 25, or recorded before Oct 25 has ended everywhere, is refused. GP-06 owes $37.40 with no pledge behind it, and the collections rules may now act on it.
- **(b)** The $37.40 is taken and names the pledge. The pledge now reads *paid* ($87.40 of $87.40), and its history shows the lapse on Oct 26 and the late payment on Nov 2.
- **(c)** The withdrawal records the agency's reason and reference, dated Sep 18. The pledge protects nothing from Sep 18, so the Sep 21 disconnection is the collections rules' to decide again.
- **(d)** Before any payment names it, the pledge is recorded in error and then never counted. After the $50.00, recording it in error is refused: the money is real and names it, even once the payment is reversed as misposted. The operator reverses the payment under the cash rules and withdraws the pledge with the reason.
- A second ending of the same pledge is refused.

---

### SCN-0127 — An agency's leftover money goes back to the agency, never to the customer

*Status:* draft (2026-11-25), not yet sent to Kyle. Built for refunds of payments, overpayment credits and the two reissues (v5.4.2-24); not for a deposit or another kind of credit (limits L5, L6; AC-52).
*Rule:* an agency's money may pay the customer's bills, and what is left of it may be held as a credit for later bills. A refund of it goes to the agency, never to the customer or another agency. A refund of the customer's own money names no agency. Sources: Ryan 2026-11-07 (DECISION-LOG: for every agency); 10 TAC §6.312(f) ("a Vendor Refund … must be reimbursed to the Subrecipient, and not the customer"); VA-26; CI-053.

**Given** GP-06 owes $87.40. Coastal Prairie's pledge is $87.40, but on Oct 20 its check is for **$100.00**, more than it pledged. The pledge reads *paid*, and $12.60 is left on the agency's payment. GP-06 moves out on Mon Dec 14 and pays its final bill itself, so the agency's **$12.60** is still left.

**When** (a) the $12.60 is refunded on Dec 14; (b) GP-06 had also overpaid its own check by $5.00 in September, and that is refunded too; (c) the agency had paid GP-06's deposit, which is returned at move-out.

**Then**
- An agency that sends more than it pledged is not refused: the money is real.
- **(a)** The refund of $12.60 names Coastal Prairie as its payee. A refund of it to GP-06, or to St. Brigid's, is refused. The same holds if the $12.60 had first become a credit (with approval) and the credit is refunded, or the credit was reissued after an uncashed refund.
- **(b)** The $5.00 refund goes to GP-06 and names no agency. One naming an agency is refused.
- **(c)** The database does not trace an agency's money into a deposit (limit L5). The core returns the deposit, after anything owed, to the agency (VA-26; AC-52).
- **Open (Kyle):** R-06 holds a leftover as a credit only with the customer's approval. Is it the customer's approval or the agency's that lets an agency's leftover pay later bills?

---

### SCN-0128 — A pledge whose agreement is not yet on file is still recorded, and protects

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-24).
*Rule:* a pledge from an agency with no agreement in force on the pledge date is recorded with no agreement and no pay-by date, rather than refused, so the customer has a record of it. It cannot lapse. To the collections rules it is unevaluable, which blocks the act. An agency retired from the platform takes no new pledge or agreement, but its money is still taken. Sources: design §4.1 (fail toward protection); §3 (an agency is retired, never deleted).

**Given** Bluebonnet takes its first pledge from the Bluebonnet Area Ministries food pantry (a charity, `cast.md`) for BB-09: **$60.00**, dated Tue Dec 8 (**invented**), before Bluebonnet has entered an agreement with it.

**When** (a) the pledge is recorded on Dec 8; (b) on Dec 17 the agreement (30 days, from Dec 1) is entered; (c) Bluebonnet retires the pantry from its list in 2027 while a pledge of it is open.

**Then**
- **(a)** Recorded: no agreement, no pay-by date, state *no agreement*. It is on the open-pledge list first. A disconnection of BB-09 that reads it is blocked, because the condition cannot be evaluated. A lapse is refused, because it has no pay-by date.
- **(b)** The existing pledge keeps no agreement: the agreement is chosen when a pledge is recorded and never changes. To give it a pay-by date, the operator records it in error (no payment names it yet) and records it again; the new pledge takes the Dec 1 agreement, **pay by Thu Jan 7, 2027**.
- **(c)** The retirement is a stamp, with who and why. A new pledge or agreement of the pantry is refused. The open pledge stands, and the pantry's payment toward it is taken.

---

### SCN-0129 — An agency's remittance for several customers: what can be matched pays the pledges, and the rest is held as the agency's

*Status:* draft (2026-11-25), not yet sent to Kyle. Built (v5.4.2-24); matching a batch line to a pledge is the core's (limit L3).
*Rule:* an agency's check covering several customers is split into payments, one per pledge, each naming the agency and its pledge. A line that matches no customer is held as a receipt that names the agency, and any payment made from it later is that agency's. The leftover rule then follows the money (SCN-0127). Sources: design §2.1 (a remitting agency on the receipt), §4.3; limit L3.

**Given** Pecan Flat's agreement with the Mesquite County Community Action Agency (CEAP, `cast.md`). Open pledges: PF-01 $75.50 and PF-02 $40.00. On Mon Dec 7 the agency's check for **$180.30** arrives with a list of three names: PF-01 $75.50, PF-02 $40.00, and "D. Reyes" $64.80, whom Pecan Flat cannot find (**invented**).

**When** the remittance is recorded on Dec 7; and (b) on Dec 14 the agency says "D. Reyes" is PF-06, whose account is in another household member's name.

**Then**
- Dec 7: two agency payments, PF-01 $75.50 and PF-02 $40.00, each naming its pledge. Both pledges read *paid*. A receipt of $64.80 names the agency, with the list line as evidence. The check reconciles: $75.50 + $40.00 + $64.80 = $180.30.
- **(b)** PF-06's payment of $64.80 from the receipt is the agency's, naming the agency. A payment from that receipt marked as the customer's own is refused.
- If PF-06 had no pledge on record, the payment still posts, as the agency's, naming none.
- **Open (Kyle):** the agency paid for a customer with no pledge on file. Should the core ask the agency for the pledge, or is the payment enough?
