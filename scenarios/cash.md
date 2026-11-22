# Cash

Payments, what they pay, what is left over, refunds, and payments that come back. Invariants: CI-049 (allocation follows a rule), CI-050 (regulated charges first), CI-017 (every reversal names what it undoes), CI-013 (money is add-only), CI-052 (bank-return codes), CI-055 (one posting per payment), CI-057 (bank-detail changes), CI-058 (the customer's date). Built by v5.4.2-19, -23 and -27 (all mirrored). Unmatched cash and agency pledges are a later family (v5.4.2-24, not mirrored), as are payments on a disputed bill (-25). Already written elsewhere: a payment in a closed month (SCN-0021), an on-time payment recorded late (SCN-0034), a backbill beside ordinary gas (SCN-0031, 0058), a deposit credit joining the pot (SCN-0046), a lockbox file re-sent (SCN-0066).

**Common to every scenario here.**
- In the ledger, a charge is positive and a payment negative; the balance is the sum. An application says what a payment pays. It moves no money and posts no ledger entry.
- **What the database refuses and what the core decides.** The database refuses an application past the line or past the payment, a refund past what is held, and a bounce while the payment is still paying something. Choosing the bills and lines is the core's, so an order that breaks a rule is "refused" here by the core, and the test is the core's; the database keeps the basis of each choice.
- BB-01's November bill is the reference bill of `cancel-rebill.md`: **$65.83**, issued Mon Nov 16, 2026, due Tue Dec 1.
- GP-01's rates are SCN-0027's (**invented**): $15.00 a month and $4.10 per Mcf, no tax line. Gulf Plains charges no late penalty here (**invented**).
- Within one bill, every utility here pays the fixed charge, then usage, then riders, then taxes, then fees (**invented**; each utility enters its own order at setup, Kyle 10-15, K-05).

---

### SCN-0081 — A payment too small for both bills pays the oldest first, and within a bill the utility's order

*Status:* draft (2026-11-22), not yet sent to Kyle. The records are built (CI-049, CI-050, REP+PROT; v5.4.2-23); choosing the lines is the core's.
*Rule:* a payment with no direction pays the oldest bill first, each line no further than its open balance, in the within-bill order of the utility's own tariff. Each application records that it was chosen oldest first, and which tariff order was in force. Sources: Kyle 10-15, R-06 and K-05; CI-049.

**Given** GP-01 owes the July bill, issued Aug 5: $15.00 + 8.0 Mcf × $4.10 ($32.80) = **$47.80**, and the August bill, issued Sep 5: $15.00 + 6.0 Mcf × $4.10 ($24.60) = **$39.60** (usage **invented**). Every charge on both can ground a disconnection, so Kyle's two tiers (SCN-0058) make one tier here.

**When** GP-01 pays **$60.00** on Sep 15, with no direction.

**Then**

| Applied to | Amount | Left on it |
|---|---|---|
| July, fixed charge | $15.00 | $0.00 |
| July, gas | $32.80 | $0.00 |
| August, fixed charge | $12.20 | $2.80 |
| August, gas | $0.00 | $24.60 |
| **Total** | **$60.00** | **$27.40** |

- Balance: $47.80 + $39.60 − $60.00 = **$27.40**, all of it August's.
- Applying $0.01 more to the July bill, or $60.01 in all from this payment, is refused.
- A utility with no within-bill order on record has no order to name, so the payment posts but nothing is applied by rule until the order is entered; there is no default (K-07).

---

### SCN-0082 — A customer pays more than is owed: the extra is not taken, or is held with the customer's approval

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23: a held overpayment names its approval, once, for exactly its amount).
*Rule:* what a payment leaves after every open bill is either not taken, or held as a credit when the customer approves applying it to later bills; the approval records the amount, who recorded it and when, and is never edited. Sources: Kyle 10-15, R-06; a customer's credits are one pot (Kyle 10-30).

**Given** BB-01 owes only the November bill, $65.83.

**When** on Fri Nov 20 BB-01 brings $80.00 in cash to the counter, and (a) wants the change; (b) approves keeping the rest toward later bills. BB-01's December bill is **$70.00** (**invented**).

**Then**
- **(a)** A payment of **$65.83** is recorded; $14.17 is handed back and is on no record. Balance $0.00.
- **(b)** A payment of $80.00: $65.83 applied to November, an approval of **$14.17** (the clerk, Nov 20), and a credit of $14.17 that names it. Balance $65.83 − $80.00 = **−$14.17**. The December bill takes it first: **$55.83** left to pay.
- Refused in (b): a credit with no approval; a credit of a different amount than its approval; a second credit from the same approval; a credit and an application that together pass $80.00.
- **Open (Kyle):** a mailed or online payment of $80.00 has no one at a counter to ask. R-06 makes the credit wait for the customer's approval. Until then, does the extra $14.17 stay unassigned on the payment and pay the next bill anyway, go back to the customer, or become a credit under a standing approval taken when the customer enrolled? Each utility already has a setting, hold or refund automatically, whose "hold" conflicts with R-06's approval. It matters for unclaimed property: money left unassigned on a payment is not a credit and runs no dormancy clock.

---

### SCN-0083 — A credit is refunded in part, never past what is left

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23, the cap).
*Rule:* a refund names the credit or payment it returns and never exceeds what is left of it; how much to refund is the utility's policy. A refund is its own movement of money, not an undo of the payment. Sources: Kyle 10-30 (partial refunds allowed); Kyle 10-21 (K-10, answer 1 and the two caps).

**Given** SCN-0082 (b) on Nov 23, before the December bill: BB-01's credit is $14.17.

**When** BB-01 asks for $10.00 of it by check, and on Nov 24 asks for another $5.00.

**Then**
- The $10.00 goes out. Ledger: $65.83 − $80.00 + $10.00 = **−$4.17**; the credit is **$4.17**.
- The $5.00 is refused: $4.17 is left. A refund of $4.17 is accepted.
- The refund does not reopen the November bill and does not change the $80.00 payment.

---

### SCN-0084 — A check comes back unpaid: the bill reopens at its own age, and the tariff's fees are charged

*Status:* draft (2026-11-22), not yet sent to Kyle. The reversal is built (v5.4.2-23); the fee is a one-off charge the tariff allows (Kyle 10-15, R-01); the late-penalty rules are not built (R-11).
*Rule:* a returned payment is reversed in full by an entry that names it, after the bills it was paying are opened again. The bill keeps its own date and age. A returned-payment fee is charged only where the utility's tariff states one, with no default. Sources: R-02 and CI-017; Kyle 10-15 (R-05: money is add-only; a status names the entry behind it); CI-052; Pecan Flat's tariff (`cast.md` §1, from Stinnett).

**Given** PF-01's bill, issued Nov 20, 2026, due Dec 1 (issue date **invented**): 5.0 Mcf × $9.00 = $45.00, plus gas 5.0 Mcf × $6.10 (**invented**) = $30.50: **$75.50**. PF-01 pays it by check on Mon Nov 30.

**When** the bank returns the check for insufficient funds, and Pecan Flat sends the certified letter the same day: (a) on Fri Dec 4; (b) on Mon Dec 14.

**Then**

| Entry | (a) Dec 4 | (b) Dec 14 | Names |
|---|---|---|---|
| Bill (Nov 20) | +$75.50 | +$75.50 | — |
| Payment (Nov 30) | −$75.50 | −$75.50 | — |
| Returned check | +$75.50 | +$75.50 | the payment |
| Returned-check charge | +$25.00 | +$25.00 | — (a charge, for the returned payment) |
| Certified mail | +$7.00 | +$7.00 | — (as above) |
| Late fee, after the 10th | — | +$20.00 | — (as above) |
| **Balance** | **$107.50** | **$127.50** | |

- The application to the bill is undone first, with a reason and a user; recording the return while the payment still pays the bill is refused.
- The bill's $75.50 is owed again and ages from Nov 20, not from the return.
- A second return of the same payment, for any amount, is refused: nothing is left of it.
- **At Bluebonnet** the tariff survey found no returned-check fee, so the same event charges none.
- **Open (Kyle):** the check reached Pecan Flat before the 1st, but never paid. Does the ordinary 10% late penalty ($7.55 here) post as well, because the bill turns out unpaid on the 1st? If so, is it dated the 2nd or the day the check comes back? The $20 fee may be Stinnett's substitute for it.
- **Open (Kyle):** is the fee charged when the bank, not the customer, caused the return? (His flag 2 asks the same of the deposit count, SCN-0045.)

---

### SCN-0085 — A payment is refunded in part and then bounces: the customer owes what was paid out

*Status:* draft (2026-11-22). The base case is Kyle's own example (2026-10-21); the variants are not yet sent to Kyle. Built (v5.4.2-23).
*Rule:* a bounce takes back the whole payment less earlier reversals; a refund does not reduce it. A refund takes at most the payment less earlier refunds and earlier reversals. A bounce waits while a refund of the payment is still waiting to go out, until an operator cancels it; nothing cancels it automatically. Sources: Kyle 10-21 (K-10, answers 1 and 2, and the cap math).

**Given** BB-02 owes nothing and mails a $50.00 check, posted Dec 1 (**invented**).

**When** $30.00 is refunded on Dec 8 and the check is returned on Dec 11; or (b) the refund is still waiting to go out on Dec 11; or (c) the check is returned first and then the refund is asked for; or (d) after the $30.00, another $21.00 is asked for on Dec 9.

**Then**

| Entry | Amount | Names |
|---|---|---|
| Payment (Dec 1) | −$50.00 | — |
| Refund (Dec 8) | +$30.00 | — (the refund names its payment; it reverses nothing) |
| Returned check (Dec 11) | +$50.00 | the payment |
| **Balance** | **$30.00** | |

- No charge is invented: the $30.00 is on no bill.
- **(b)** The return is refused until an operator cancels the refund, and the cancel is on record. Then +$50.00, balance **$0.00**.
- **(c)** The refund is refused: nothing is left of the payment.
- **(d)** The $21.00 is refused; $20.00 is the most.

---

### SCN-0086 — A payment whose extra became a credit bounces

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23, r4 and r5).
*Rule:* when an overpaid payment bounces, the credit made from it goes with it: what the credit still held is gone, what it already paid out stands and is owed. While the credit is paying a bill, or a refund of it is waiting, the bounce waits. Sources: Kyle 10-21 (K-10); Kyle 10-30.

**Given** BB-01 pays the November bill with a $100.00 check on Nov 20: $65.83 applied, **$34.17** held as a credit with approval.

**When** the check is returned on Dec 4, and the credit is (a) untouched; (b) $20.00 of it was refunded on Nov 25; (c) it paid $34.17 of another bill.

**Then**
- **(a)** $65.83 − $100.00 + $100.00 = **$65.83** owed, the November bill. The credit is $0.00.
- **(b)** $65.83 − $100.00 + $20.00 + $100.00 = **$85.83** owed: the November bill and the $20.00 paid out. The credit's other $14.17 is gone.
- **(c)** Refused until the credit's application is undone; then as (a), and the other bill is open again.
- In each, the November application is undone first, as in SCN-0084.

---

### SCN-0087 — A credit from one payment covers what another payment's bounce left owed

*Status:* draft (2026-11-22), not yet sent to Kyle. Built as a record (v5.4.2-27); deciding to net, and refusing the refund, are the core's (AC-44).
*Rule:* all of a customer's credits are one pot, shown as one net figure. A bounce's shortfall uses up the pot and the customer owes the rest. The netting is recorded as money applied to the bounced payment's shortfall, never as a charge. Sources: Kyle 10-30; Ryan 11-02.

**Given** SCN-0085: BB-02 owes $30.00 on the bounced payment, on no bill. Earlier, a different payment left BB-02 a credit of **$20.00** (approved, **invented**).

**When** BB-02's account is read on Dec 12, and BB-02 asks for the $20.00 back.

**Then**
- BB-02 sees one figure: **$10.00 owed**. Never "credit $20.00" beside "owed $30.00".
- The $20.00 is applied to the shortfall. The credit then holds $0.00, the shortfall is $10.00, and the ledger does not move: −$50.00 + $30.00 + $50.00 − $20.00 = **$10.00** before and after.
- The refund is refused by the core. **The database alone would allow it** if the netting had not been recorded first; a test pins the core's order.
- Applying more than $20.00 from the credit, or more than $30.00 to the shortfall, is refused.

---

### SCN-0088 — A refund check is never cashed: the money comes back to the customer

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23 and -27).
*Rule:* a refund that comes back puts the money back where it came from. If its shortfall has since been repaid, the repayment is undone in the same step. If its credit has since gone to the state as unclaimed property, the money becomes a new credit: what went to the state is never reopened. Sources: Ryan 10-21 (r4); Ryan 11-05 (-27).

**Given** and **When**
- **(a)** SCN-0083's $10.00 refund comes back on Jan 12, 2027 (BB-01 still holds the $4.17 credit; suppose no December bill took it, **invented**).
- **(b)** SCN-0087, after the netting: BB-02's $30.00 refund turns out never to have been cashed and comes back.
- **(c)** As (a), but the $4.17 had been sent to the state first, when its dormancy period ended (the period is the state's rule).

**Then**
- **(a)** The credit is **$14.17** again; balance −$14.17.
- **(b)** The check was never cashed, so the $30.00 never left and BB-02 never owed it. The $20.00 repayment is undone and the return recorded together; recording the return alone is refused. Balance: $10.00 − $30.00 = **−$20.00**, the original credit.
- **(c)** The old credit stays at nothing, closed. A new credit of **$10.00** names the returned refund. Balance: −$4.17 + $4.17 (sent to the state) − $10.00 = **−$10.00**. It pays bills, is refunded, or reaches the state on its own clock. Recording the return without the new credit is refused.

---

### SCN-0089 — A bill already paid is found wrong: the payment moves to the corrected bill

*Status:* draft (2026-11-22), not yet sent to Kyle. The void, the correction and the applications are built (v5.4.2-21, -23); a void does not move the payment, the core does (-23's residual R4). It writes Kyle's answer 7 of 11-03 (credit and rebill if paid) and SCN-0027's note.
*Rule:* a paid bill corrected for a keying error is credited and rebilled: its charge is reversed, the correction issued, and the money that paid it is released and applied to the correction. Nothing is lost between the two. Sources: Kyle 11-03, answer 7; Kyle 10-15 (R-02); Kyle 11-05, answer 2 and Ryan 11-22 (an amount the error hid moves to the next bill).

**Given** BB-01 paid the November bill, $65.83, on Wed Nov 18. On Nov 20 the read is found keyed wrong. The true usage is (a) 4.5 Mcf, a correction of **$52.61** (SCN-0002); (b) 7.5 Mcf, **$79.06** (SCN-0033).

**When** the operator chooses to credit and rebill on Nov 20.

**Then**

| Entry | (a) | (b) | Names |
|---|---|---|---|
| Bill (Nov 16) | +$65.83 | +$65.83 | — |
| Payment (Nov 18) | −$65.83 | −$65.83 | — |
| Credit of the bill (Nov 20) | −$65.83 | −$65.83 | the bill's charge |
| Correction (Nov 20) | +$52.61 | +$79.06 | — (names the voided bill) |
| Moved to the next bill (Nov 20) | — | −$13.23 | the correction |
| **Balance** | **−$13.22** | **$0.00** | |

- The application to the old bill is undone and $52.61 (a) or $65.83 (b) applied to the correction, each step with its reason. The payment's date is still Nov 18: no penalty.
- **(b)** The December bill carries the $13.23 (SCN-0033).
- The next bill's starting read is the true read; a December bill that starts from the keyed one is refused (SCN-0027 b; Kyle's flag 3 of 11-03).
- This stream's reading: "credit and rebill" makes the same records as "void and rebill", and differs only in the payment. **Open (Kyle):** is that right, or should the customer see a separate credit memo?
- **Open (Kyle):** in (a) the $13.22 left over comes from our error, not from the customer paying too much. Must BB-01 approve holding it (R-06), or is it held as a credit, or sent back, without asking?

---

### SCN-0090 — An application to the wrong bill is undone and made again, and both stay on record

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23).
*Rule:* an operator may apply a payment out of order, with a reason and a name. A wrong application is undone by a new negative row that names it; neither is edited or deleted, and an undo is not itself undone. Sources: CI-049 (overrides carry a reason); Kyle 10-15 (R-05); -23 A2.

**Given** SCN-0081's two bills and the $60.00 payment. The clerk applies $39.60 to August by override, reason "customer asked", and $20.40 to July. The customer had not asked.

**When** on Sep 16 the clerk undoes the August application and applies the money by the rule.

**Then**
- Before: July owes $27.40, August $0.00. After: $27.40 more to July and $12.20 to August: July $0.00, August **$27.40**, as SCN-0081.
- The records: the override, its undo (−$39.60, with reason and user) and the new rows. The balance is $27.40 throughout: no entry posts.
- As of Sep 15, what was recorded by then still shows August paid.
- Refused: an override with no reason or no user; an undo of $39.61; a second undo past what is left; undoing the undo; an undo dated before its application.

---

### SCN-0091 — A customer may mark a payment as a deposit, or direct it to a bill, and nothing finer

*Status:* draft (2026-11-22), not yet sent to Kyle. The deposit mark is built (v5.4.2-23).
*Rule:* a customer may designate a payment only as a deposit or as a bill; a payment marked a deposit pays no bill. A customer who directs a payment to a bill is followed, with a warning when that leaves more open to disconnection; the direction is never to a single charge. Sources: Kyle 10-15, K-05 (which replaced his 07-10 ruling D7-1 (c): no designation at all); Kyle 11-05, answer 16; SCN-0058.

**Given** BB-02 owes a $250.00 deposit and a $60.00 bill (**invented**).

**When** BB-02 (a) pays $250.00, "for the deposit"; (b) pays $60.00, with a note "for the gas only, not the tax"; (c) pays $310.00 by one check, for both.

**Then**
- **(a)** A deposit payment: the deposit is funded, the bill still owes $60.00. Applying it to the bill is refused.
- **(b)** A bill payment, applied by the rule (SCN-0081), tax included; the note is kept and has no effect.
- **(c)** This stream's reading: two payments, $250.00 (deposit) and $60.00 (bill), with one check number. **Open (Ryan, with the money stream):** when the check comes through a processor under one transaction number, the database accepts one receipt per number, so the second is refused. How is one receipt split between a deposit and a bill?

---

### SCN-0092 — A late penalty is paid before any bill shows it

*Status:* draft (2026-11-22), not yet sent to Kyle. The penalty rules are not built (R-11). It tests a gap: a payment can be applied only to a bill line.
*Rule:* the customer's balance is the sum of the ledger, penalties included, whether or not a bill has shown them yet. Sources: Ryan 10-13 (a balance is a sum); CI-049; SCN-0033 (the penalty is its own charge).

**Given** SCN-0033's November bill with no misread: $65.83, unpaid on Dec 1; on Dec 2 a penalty of $6.52 and its tax of $0.07. BB-01 asks the balance and is told **$72.42**.

**When** BB-01 pays $72.42 on Sat Dec 5, before the December bill.

**Then**
- Balance **$0.00**. $65.83 is applied to the bill.
- The other **$6.59** has no bill line yet. It stays on the payment, is not an overpayment, and is not offered back or held as a credit: BB-01 owes exactly that much. The December bill shows the penalty, and the $6.59 pays it.
- **Open (Ryan, with the money stream):** should a payment be able to pay a penalty directly, before a bill shows it? Until then, a report of "unapplied money" must leave out money already owed, or it would be refunded in error.

---

### SCN-0093 — Regulated charges are paid before unregulated ones, even on an older bill

*Status:* draft (2026-11-22), not yet sent to Kyle. The class on every line and the recorded basis are built (CI-050, v5.4.2-23); the order is the core's.
*Rule:* every regulated charge is paid before any unregulated one, whatever the age of either: the floor ranks above oldest bill first. Unregulated debt never grounds a disconnection. Sources: CI-050; D7-2 (Kyle 07-10); Kyle 11-05, answer 16 (two tiers).

**Given** SCN-0081's two bills, each also carrying an $18.00 appliance service plan, unregulated (**invented**): July $65.80, August $57.60. GP-01 pays **$100.00** on Sep 15.

**When** the payment is applied.

**Then**

| Applied to | Amount | Left on it |
|---|---|---|
| July's gas service | $47.80 | $0.00 |
| August's gas service | $39.60 | $0.00 |
| July's plan | $12.60 | $5.40 |
| August's plan | $0.00 | $18.00 |
| **Total** | **$100.00** | **$23.40** |

- What may ground a disconnection: **nothing**. Oldest bill first without the floor would pay July whole ($65.80) and $34.20 of August, leaving $5.40 of gas open to disconnection: refused.
- This stream's reading where a regulated backbill (which cannot ground a disconnection) and an unregulated charge are both open: the backbill first, by CI-050's floor. Kyle's second tier says oldest first among charges that cannot ground one, and names only backbills.
- **Open (Kyle):** GP-01 directs the $100.00 to the July bill, plan included (answer 16 says follow the customer). CI-050 says the floor ranks above the customer's direction. Which wins?
- **Open (Kyle):** an agency's payment restricted to an unregulated charge. Restriction wins over the posting order (D7-1 (b)), but the floor ranks above the order. Which wins? The database records either.

---

### SCN-0094 — A payment message received twice posts once

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (CI-055, REP+PROT; v5.4.2-19). Matching one transaction that arrives by two channels is the core's.
*Rule:* one payment per processor transaction and source, and one money-out per processor transaction and source; a confirmation is sent only after the processor accepts the payment. A repeat is compared with the first before it is called a harmless repeat. Sources: CI-055; v5.4.2-19 (AC-35).

**Given** BB-01 pays $65.83 online on Nov 20; the processor's transaction is **T-100** (**invented**).

**When** (a) the processor sends T-100 again, $65.83; (b) it sends T-100 with $56.83; (c) BB-01 presses Pay twice and the processor takes both, T-100 and T-101; (d) T-100 is refunded twice, $10.00 and $5.00, the second under the first refund's own number; (e) T-100 arrives again in the bank's settlement file.

**Then**
- **(a)** Refused as a second posting, and recognized as a repeat: the same payer and amount. One payment of $65.83.
- **(b)** Refused, and not treated as a repeat: the amounts differ, so it goes to an operator.
- **(c)** The app's own token stops the second press before it reaches the processor. If both were taken, both really arrived: two payments, the second left over (SCN-0082's Open).
- **(d)** The second is refused; under its own number it is accepted.
- **(e)** The database does not catch it, since the source differs; the core matches the two and posts one.

---

### SCN-0095 — A bank return is handled by its code, and a bank's correction replaces the stored account

*Status:* draft (2026-11-22), not yet sent to Kyle. Recording is built (CI-052 and CI-057; v5.4.2-19); retries, contact and the timer are the core's.
*Rule:* each bank return keeps its own code, and what happens next follows the code: insufficient funds may be presented again as a new payment; an unauthorized debit is never debited again; an unknown code goes to an operator. A notice of change is not a failure: the stored account is replaced by a new record, within the bank network's window, and the old one is kept. Sources: CI-052; CI-057 (6 banking days); Ryan 10-14 and 10-28 (a re-presentment is a new payment).

**Given** BB-01 pays by automatic bank draft; the November draft is $65.83, settled Nov 30 (**invented**).

**When** it comes back (a) R01, insufficient funds; (b) R10, unauthorized; (c) R99, a code not on file; (d) with no code; or (e) instead it clears and the bank sends notice C01, a corrected account number, on Mon Nov 30.

**Then**
- **(a)** The draft is reversed as in SCN-0084 (no fee at Bluebonnet). It may be presented once more: a new payment with its own number, which may name the first.
- **(b)** Reversed; no new debit; BB-01 is contacted and the draft suspended.
- **(c)** Reversed with its code, and sent to an operator; no new debit meanwhile.
- **(d)** Refused: a returned bank draft carries its code.
- **(e)** The payment stands. The corrected account is a new record naming the old one, the code and the day it came; the old record stays, unchanged and unusable. The last day to act is **Tue Dec 8**, the sixth banking day after Nov 30.
- A late penalty caused by a draft that failed because the notice was not acted on in time is not charged (CI-057). **Open (Kyle):** is it never charged, or charged and reversed? And is the fee of SCN-0084 charged in (b)?

---

### SCN-0096 — A payment keyed for the wrong amount is reversed and entered again

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23).
*Rule:* a payment's amount, date and customer are never edited. A wrong one is reversed in full, naming it, and the right one entered; the customer's date stays the true one. A payment still pending moved no money, so it is voided instead. Sources: Kyle 10-15 (R-05); CI-013; CI-058.

**Given** BB-01 pays $65.83 in cash on Tue Dec 1, the due date; the clerk keys **$56.83** and posts it. On Dec 2 the drawer is $9.00 over.

**When** the clerk (a) changes the amount; (b) reverses and re-enters it on Dec 2, with Dec 1 as the customer's date; (c) had caught it while the payment was pending.

**Then**
- **(a)** Refused.
- **(b)** $65.83 − $56.83 + $56.83 − $65.83 = **$0.00**. The Nov bill was paid on time: no penalty. The reversal names the $56.83 payment; both payments stay on record.
- **(c)** The pending payment is voided; nothing was on the ledger to reverse. A posted payment cannot be voided, and a reversed one cannot be reopened.

---

### SCN-0097 — A check bounces after its month is closed

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-22, -23).
*Rule:* the return posts in the open month; the closed month still shows the payment. Aging nets the payment and its return, so the bill ages from its own date. Sources: CI-110 and SCN-0005 (a closed period never reopens); SCN-0023 (aging).

**Given** BB-01 pays the November bill by check on Nov 20. November is closed on Dec 10 with BB-01 at $0.00.

**When** the check is returned on Mon Dec 14, and is recorded (a) dated Nov 30; (b) dated Dec 14.

**Then**
- **(a)** Refused: November is closed. **(b)** Accepted.
- November's closed figures still show $0.00. On Dec 15 BB-01 owes **$65.83**, aged 29 days, from Nov 16: in 0–30 days.
- A refund of that payment dated in November is refused too.

---

### SCN-0098 — The same mailed check is on time at one utility and late at another

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (CI-058, REP+PROT; v5.4.2-19): the date and its method are recorded and never change once the payment takes effect.
*Rule:* whether a payment was on time is judged by the customer's date, set by the method the utility's tariff or its law states, and kept with the payment. Sources: CI-058; SCN-0021; SCN-0034.

**Given** two checks, each postmarked Tue Dec 1, the due date, and received Thu Dec 3: BB-01's, at Bluebonnet (postmark, `cast.md` §2), and GP-01's, at Gulf Plains, which counts the day received (**invented**; due date **invented**). Gulf Plains charges a late penalty for this scenario only (**invented**).

**When** both are posted on Dec 3.

**Then**
- BB-01's customer date is **Dec 1**, method postmark: on time. GP-01's is **Dec 3**, method receipt: late.
- A payment cannot be posted without the date and its method; changing either afterwards is refused.
- A utility that changes its method does so from a date; payments already posted keep theirs.
- **Open (citation check):** whether 16 TAC §7.45 states when a mailed payment counts for a utility it binds; if it does, Gulf Plains' method is the law's, not its choice.
