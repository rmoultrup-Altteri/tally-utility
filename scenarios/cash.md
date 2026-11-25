# Cash

Payments, what they pay, what is left over, refunds, and payments that come back. Invariants: CI-049 (allocation follows a rule), CI-050 (regulated charges first), CI-017 (every reversal names what it undoes), CI-013 (money is add-only), CI-052 (bank-return codes), CI-055 (one posting per payment), CI-057 (bank-detail changes), CI-058 (the customer's date). Built by v5.4.2-19, -23 and -27 (all mirrored). Unmatched cash and agency pledges are `unmatched-cash-and-pledges.md` (v5.4.2-24, mirrored 2026-11-24), as are payments on a disputed bill (-25). Already written elsewhere: a payment in a closed month (SCN-0021), an on-time payment recorded late (SCN-0034), a backbill beside ordinary gas (SCN-0031, 0058), a deposit credit joining the pot (SCN-0046), a lockbox file re-sent (SCN-0066).

**Common to every scenario here.**
- In the ledger, a charge is positive and a payment negative; the balance is the sum. An application says what a payment pays. It moves no money and posts no ledger entry.
- **What the database refuses and what the core decides.** The database refuses an application past the line or past the payment, a refund past what is held, and a bounce while the payment is still paying something. Choosing the bills and lines is the core's, so an order that breaks a rule is "refused" here by the core, and the test is the core's; the database keeps the basis of each choice.
- BB-01's November bill is the reference bill of `cancel-rebill.md`: **$65.83**, issued Mon Nov 16, 2026, due Tue Dec 1.
- GP-06's rates are SCN-0027's (**invented**): $15.00 a month and $4.10 per Mcf, no tax line. Gulf Plains charges no late penalty here (**invented**).
- Each scenario stands alone unless it says it continues another; the same customer may be on different facts elsewhere. New customers (**invented**; GP-06 and BB-09 are also in `unmatched-cash-and-pledges.md` and the cast): **GP-06** (Gulf Plains, residential, unincorporated area), **BB-09** (Bluebonnet, renter outside the city, R-R, deposit $250) and **PL-02** (Prairie Line, Fremont, residential). Dates are 2026 unless stated.
- A balance after a bounce is **before any late penalty** for the bill it reopens: whether one posts is SCN-0084's Open.
- Within one bill, every utility here pays the fixed charge, then usage, then riders, then taxes, then fees (**invented**; each utility enters its own order at setup, Kyle 10-15, K-05).

---

### SCN-0081 — A payment too small for both bills pays the oldest first, and within a bill the utility's order

*Status:* draft (2026-11-22), not yet sent to Kyle. The records are built (CI-049, CI-050, REP+PROT; v5.4.2-23); choosing the lines is the core's. The within-bill order is checked when it is entered: every charge type once, regulated types before unregulated; a missing or repeated type is refused.
*Rule:* a payment with no direction pays the oldest bill first, each line no further than its open balance, in the within-bill order of the utility's own tariff. Each application records that it was chosen oldest first, and which tariff order was in force. Sources: Kyle 10-15, R-06 and K-05; CI-049.

**Given** GP-06 owes the July bill, issued Aug 5: $15.00 + 8.0 Mcf × $4.10 ($32.80) = **$47.80**, and the August bill, issued Sep 5: $15.00 + 6.0 Mcf × $4.10 ($24.60) = **$39.60** (usage **invented**). Every charge on both can ground a disconnection, so Kyle's two tiers (SCN-0058) make one tier here.

**When** GP-06 pays **$60.00** on Tue Sep 15, with no direction.

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
- Pecan Flat's cut-off on the 10th and its separate $20 service charge follow from the unpaid bill; this scenario stops at the return.
- (b)'s $20.00 is this stream's reading of "insufficient-funds late fee $20 if after the 10th" as the day the check comes back. **Open (Kyle):** or does it mean not made good by the 10th, so that (a) owes it too once the 10th passes? Is it charged beside the $20 service charge? And are the $25, $7 and $20 in next month's penalty base (full amount owed, excluding earlier penalties)?
- **Open (Kyle):** the check reached Pecan Flat before the 1st, but never paid. Does the ordinary 10% late penalty ($7.55 here) post as well, because the bill turns out unpaid on the 1st? If so, is it dated the 2nd or the day the check comes back? The $20 fee may be Stinnett's substitute for it. The same question at Bluebonnet, whose gross rate would add $6.52 and $0.07 to the reference bill.
- **Open (Kyle):** is the fee charged when the bank, not the customer, caused the return? (His flag 2 asks the same of the deposit count, SCN-0045.)

---

### SCN-0085 — A payment is refunded in part and then bounces: the customer owes what was paid out

*Status:* draft (2026-11-22). The base case is Kyle's own example (2026-10-21); the variants are not yet sent to Kyle. Built (v5.4.2-23).
*Rule:* a bounce takes back the whole payment less earlier reversals; a refund does not reduce it. A refund takes at most the payment less earlier refunds and earlier reversals. A bounce waits while a refund of the payment is still waiting to go out, until an operator cancels it; nothing cancels it automatically. Sources: Kyle 10-21 (K-10, answers 1 and 2, and the cap math).

**Given** BB-09 owes nothing and mails a $50.00 check, posted Dec 1 (**invented**).

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

**When** the check is returned on Dec 4, and the credit is (a) untouched; (b) $20.00 of it was refunded on Nov 25; (c) the return comes on Dec 18 instead, after the credit paid $34.17 of the December bill ($70.00, issued Wed Dec 16, **invented**).

**Then**
- **(a)** $65.83 − $100.00 + $100.00 = **$65.83** owed, the November bill. The credit is $0.00.
- **(b)** $65.83 − $100.00 + $20.00 + $100.00 = **$85.83** owed: the November bill and the $20.00 paid out. The credit's other $14.17 is gone.
- **(c)** Refused until the credit's application is undone. Then the credit is $0.00, and both bills are open: $65.83 + $70.00 − $100.00 + $100.00 = **$135.83**.
- In each, the November application is undone first, as in SCN-0084.

---

### SCN-0087 — A credit from one payment covers what another payment's bounce left owed

*Status:* draft (2026-11-22), not yet sent to Kyle. Built as a record (v5.4.2-27); deciding to net, and refusing the refund, are the core's (AC-44).
*Rule:* all of a customer's credits are one pot, shown as one net figure from the day of the bounce. A bounce's shortfall uses up the pot and the customer owes the rest. The netting is recorded, before any refund of a credit, as money applied to the bounced payment's shortfall, never as a charge. Sources: Kyle 10-30; Ryan 11-02; AC-44.

**Given** SCN-0085's base case, with one change: before it, a different payment had left BB-09 a credit of **$20.00** (approved, **invented**), so BB-09 starts at −$20.00. BB-09 owes $30.00 on the bounced payment, on no bill.

**When** BB-09's account is read on Dec 12, and BB-09 asks for the $20.00 back.

**Then**
- BB-09 sees one figure: **$10.00 owed**. Never "credit $20.00" beside "owed $30.00".
- The figure is net at once; the record is made on Dec 12, because a refund is asked for. This stream's reading: not at the bounce, since Ryan's rule of 11-02 (a state may bar the setoff before escheat, SCN-0103) would then never apply. The $20.00 is applied to the shortfall. The credit then holds $0.00, the shortfall is $10.00, and the ledger does not move: −$50.00 + $30.00 + $50.00 − $20.00 = **$10.00** before and after. **Open (Kyle):** his words are "use up whatever is in the total credit"; does he mean it recorded at the bounce?
- The refund is refused by the core. **The database alone would allow it** if the netting had not been recorded first; a test pins the core's order.
- Applying more than $20.00 from the credit is refused. With a credit of $40.00 instead, applying $30.01 to the shortfall is refused and $30.00 accepted.

---

### SCN-0088 — A refund check is never cashed: the money comes back to the customer

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23 and -27), except the ledger entry for money sent to the state: the database neither posts nor requires it, so the core does (board note).
*Rule:* a refund that comes back puts the money back where it came from. If its shortfall has since been repaid, the repayment is undone in the same step. If its credit has since gone to the state as unclaimed property, the money becomes a new credit: what went to the state is never reopened. Sources: Ryan 10-21 (r4); Ryan 11-05 (-27).

**Given** and **When**
- **(a)** SCN-0083's $10.00 refund comes back on Jan 12, 2027. BB-01 still holds the $4.17 credit and has had no bill after November's: the service had passed to a new customer at the Nov 13 read, which the utility learned on Nov 25, and the deposit was paid back whole, off these figures (**invented**).
- **(b)** SCN-0087, after the netting: BB-09's $30.00 refund turns out never to have been cashed and comes back on Jan 12, 2027.
- **(c)** As (a), but the check comes back on Mar 3, 2031, after the $4.17 was sent to the state on Nov 1, 2030, at the end of its dormancy period (dates **invented**; the period is the state's rule).

**Then**
- **(a)** The credit is **$14.17** again; balance **−$14.17**.
- **(b)** The check was never cashed, so the $30.00 never left and BB-09 never owed it. The $20.00 repayment is undone and the return recorded together; recording the return alone is refused. Balance: $10.00 − $30.00 = **−$20.00**, the original credit.
- **(c)** The old credit stays at nothing, closed. A new credit of **$10.00** names the returned refund. Balance: −$4.17 + $4.17 (sent to the state) − $10.00 = **−$10.00**. It pays bills, is refunded, or reaches the state on its own clock. Recording the return without the new credit is refused. **Open (counsel):** an uncashed refund check is itself unclaimed property; must it be reported before this date, and from which day does the new credit's clock run (SCN-0100 too)?

---

### SCN-0089 — A bill already paid is found wrong: the payment moves to the corrected bill

*Status:* draft (2026-11-22), not yet sent to Kyle. The void, the correction and the applications are built (v5.4.2-21, -23); a void does not move the payment, the core does (-23's residual R4). **Not built in (b):** the record that $13.23 is due later (SCN-0033). It writes Kyle's answer 7 of 11-03 (credit and rebill if paid) and SCN-0027's note.
*Rule:* a paid bill corrected for a keying error is credited and rebilled: its charge is reversed, the correction issued, and the money that paid it is released and applied to the correction. Nothing is lost between the two. Sources: Kyle 11-03, answer 7; Kyle 10-15 (R-02); Kyle 11-05, answer 2 and Ryan 11-22 (an amount the error hid is due with the next bill).

**Given** BB-01 paid the November bill, $65.83, on Wed Nov 18. On Nov 20 the read is found keyed wrong by the utility (in (b), inside Bluebonnet's six-month default, SCN-0028). The true usage is (a) 4.5 Mcf, a correction of **$52.61** (SCN-0002); (b) 7.5 Mcf, **$79.06** (SCN-0033).

**When** the operator chooses to credit and rebill on Nov 20.

**Then**

| Entry | (a) | (b) | Names |
|---|---|---|---|
| Bill (Nov 16) | +$65.83 | +$65.83 | — |
| Payment (Nov 18) | −$65.83 | −$65.83 | — |
| Credit of the bill (Nov 20) | −$65.83 | −$65.83 | the bill's charge |
| Correction (Nov 20) | +$52.61 | +$79.06 | — (names the voided bill) |
| **Balance** | **−$13.22** | **$13.23**, not yet due | |

- The application to the old bill is undone and $52.61 (a) or $65.83 (b) applied to the correction, each step with its reason. The payment's date is still Nov 18: no penalty.
- **(b)** The $65.83 fills the part of each line due now, as SCN-0033's table, leaving the $13.23 on its four lines. It is due with the December bill, which prints it without charging it again.
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
- Applications are per line, so August's $39.60 is two rows ($15.00 and $24.60), each undone by its own row.
- The records: the override, its undo (−$39.60, with reason and user) and the new rows. The balance is $27.40 throughout: no entry posts.
- As of Sep 15, what was recorded by then still shows August paid.
- Refused: an override with no reason or no user; an undo of $24.61 on the gas row; a second undo past what is left; undoing the undo; an undo dated before its application.

---

### SCN-0091 — A customer may mark a payment as a deposit, or direct it to a bill, and nothing finer

*Status:* draft (2026-11-22), not yet sent to Kyle. The deposit mark is built (v5.4.2-23). **Not built:** a customer's direction has no record of its own; it can only be stored as an operator's override, with a user and a reason (board note).
*Rule:* a customer may designate a payment only as a deposit or as a bill; a payment marked a deposit pays no bill. A customer who directs a payment to a bill is followed, with a warning when that leaves more open to disconnection; the direction is never to a single charge. Sources: Kyle 10-15, K-05 (which replaced his 07-10 ruling D7-1 (c): no designation at all); Kyle 11-05, answer 16; SCN-0058.

**Given** BB-09 owes a $250.00 deposit and a $60.00 bill (**invented**).

**When** BB-09 (a) pays $250.00, "for the deposit"; (b) pays $60.00, with a note "for the gas only, not the customer charge"; (c) pays $310.00 by one check, for both; or (d) owing instead two bills, an older $47.80 and a newer $39.60 (**invented**; they replace the $60.00 bill), pays $39.60 online and directs it to the newer.

**Then**
- **(a)** A deposit payment: the deposit is funded, the bill still owes $60.00. Applying it to the bill is refused.
- **(b)** A bill payment, applied by the rule (SCN-0081), customer charge first; the note is kept and has no effect.
- **(c)** This stream's reading: two payments, $250.00 (deposit) and $60.00 (bill), with one check number. **Open (Ryan, with the money stream):** when the check comes through a processor under one transaction number, the database accepts one receipt per number, so the second is refused. How is one receipt split between a deposit and a bill?
- **(d)** The newer bill is paid, and the operator is warned that the older $47.80 stays open to disconnection (answer 16). The record says the customer directed it. This stream's reading until it is built: an override whose reason is the customer's direction; an online payment has no operator to name.

---

### SCN-0092 — A late penalty is paid before any bill shows it

*Status:* draft (2026-11-22), not yet sent to Kyle. The penalty rules are not built (R-11). It tests a gap: a payment can be applied only to a bill line.
*Rule:* the customer's balance is the sum of the ledger, penalties included, whether or not a bill has shown them yet. Sources: Ryan 10-13 (a balance is a sum); CI-049; SCN-0033 (the penalty is its own charge).

**Given** SCN-0033's November bill with no misread: $65.83, unpaid on Dec 1; on Dec 2 a penalty of $6.52 and its tax of $0.07. BB-01 asks the balance and is told **$72.42**.

**When** BB-01 pays $72.42 on Sat Dec 5, before the December bill.

**Then**
- Balance **$0.00**. $65.83 is applied to the bill.
- The other **$6.59** has no bill line yet. It stays on the payment, is not an overpayment, and is not offered back or held as a credit: BB-01 owes exactly that much. The December bill (**$70.00** of December's own charges, **invented**) lists the $6.59 penalty as already charged: its ledger charge is $70.00, not $76.59, and the $6.59 pays the penalty's lines there. (A penalty has no other line to pay; SCN-0033's $13.23 does, on the November correction, so the December bill only prints it.) Balance after it: **$70.00**.
- **Open (Ryan, with the money stream):** should a payment be able to pay a penalty directly, before a bill shows it? Until then, a report of "unapplied money" must leave out money already owed, or it would be refunded in error. Today only the core can refuse the refund or the hold: the database accepts both, since the payment holds $6.59 that nothing draws on.

---

### SCN-0093 — Regulated charges are paid before unregulated ones, even on an older bill

*Status:* draft (2026-11-22), not yet sent to Kyle. The class on every line and the recorded basis are built (CI-050, v5.4.2-23); the order is the core's.
*Rule:* every regulated charge is paid before any unregulated one, whatever the age of either: the floor ranks above oldest bill first. Unregulated debt never grounds a disconnection. Sources: CI-050; D7-2 (Kyle 07-10); Kyle 11-05, answer 16 (two tiers).

**Given** SCN-0081's two bills, each also carrying an $18.00 appliance service plan, unregulated (**invented**): July $65.80, August $57.60. GP-06 pays **$100.00** on Sep 15.

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
- This stream's reading where a regulated backbill (which cannot ground a disconnection) and an unregulated charge are both open: the backbill first, by CI-050's floor. Kyle's second tier says oldest first among charges that cannot ground one, and names only backbills. **Open (Kyle):** is the floor right there too?
- 16 TAC §7.45(4)(E)(ii) bars disconnection for "merchandise or charges for nonutility service" (read 2026-11-22), so the plan's charges never ground one where Texas law binds.
- **Open (Kyle):** GP-06 directs the $100.00 to the July bill, plan included (answer 16 says follow the customer). CI-050 says the floor ranks above the customer's direction, and that the customer is told. Which wins?
- **Open (Kyle):** an agency's payment restricted to an unregulated charge. Restriction wins over the posting order (D7-1 (b)), but the floor ranks above the order. Which wins? The database can record either for an agency's restriction.

---

### SCN-0094 — A payment message received twice posts once

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (CI-055, REP+PROT; v5.4.2-19). Matching one transaction that arrives by two channels is the core's.
*Rule:* one payment per processor transaction and source, and one money-out per processor transaction and source; a confirmation is sent only after the processor accepts the payment. A repeat is compared with the first before it is called a harmless repeat. Sources: CI-055; v5.4.2-19 (AC-35).

**Given** BB-01 pays $65.83 online on Nov 20; the processor's transaction is **T-100** (**invented**).

**When** (a) the processor sends T-100 again, $65.83; (b) it sends T-100 with $56.83; (c) BB-01 presses Pay twice and the processor takes both, T-100 and T-101; (d) in (c), T-101 paid nothing and no credit holds it; $10.00 of it is refunded, then $5.00, the second under the first refund's number; (f) the processor times out or declines; (e) T-100 arrives again in the bank's settlement file.

**Then**
- **(a)** Refused as a second posting, and recognized as a repeat: the same payer and amount. One payment of $65.83.
- **(b)** Refused, and not treated as a repeat: the amounts differ, so it goes to an operator.
- **(c)** The app's own token stops the second press before it reaches the processor. If both were taken, both really arrived: two payments, the second left over (SCN-0082's Open).
- **(d)** The second is refused as the first refund's number again; under its own number it is accepted ($50.83 of T-101 left).
- **(f)** Declined: no payment, and no confirmation. Timed out: none until the processor answers; if it had accepted, the retry with the same token posts once, and the confirmation follows. The app's, not the database's.
- **(e)** The database does not catch it, since the source differs; the core matches the two and posts one.

---

### SCN-0095 — A bank return is handled by its code, and a bank's correction replaces the stored account

*Status:* draft (2026-11-22), not yet sent to Kyle. Recording is built (CI-052 and CI-057; v5.4.2-19); retries, contact and the timer are the core's.
*Rule:* each bank return keeps its own code, and what happens next follows the code: insufficient funds may be presented again as a new payment; an unauthorized debit is never debited again; an unknown code goes to an operator. A notice of change is not a failure: the stored account is replaced by a new record, within the bank network's window, and the old one is kept. Sources: CI-052; CI-057 (6 banking days); Ryan 10-14 and 10-28 (a re-presentment is a new payment).

**Given** BB-01 pays by automatic bank draft, recorded as an ACH payment; the November draft is $65.83, settled Nov 30 and, except in (e), returned on Wed Dec 2 (**invented**).

**When** it comes back (a) R01, insufficient funds; (b) R10, unauthorized; (c) R99, a code not on file; (d) with no code; or (e) instead it clears and the bank sends notice C01, a corrected account number, on Mon Nov 30.

And for BB-09, also on draft, with a C01 notice of its own on Nov 30 and not yet acted on (all **invented**): (f) a $60.00 bill due Fri Dec 4 is drawn from the old account that day and returned R04 on Mon Dec 7; or (g) the same bill is due Thu Dec 10, drawn that day, and returned R04 on Fri Dec 11.

**Then**
- **(a)** The draft is reversed as in SCN-0084 (no fee at Bluebonnet). It may be presented once more: a new payment with its own number, which may name the first.
- **(b)** Reversed, recorded as returned with its code; no new debit; BB-01 is contacted and the draft suspended.
- **(c)** Reversed with its code, and sent to an operator; no new debit meanwhile. The database keeps any code of the right form; it holds no list of codes, so knowing this one is unknown is the core's.
- **(d)** Refused. The database refuses it for an ACH payment recorded as returned; a draft stored as another method, or a return recorded as a reversal, is accepted without a code, so the core records every draft as ACH, every return as a return, and refuses a missing code itself.
- **(e)** The payment stands. The corrected account is a new record naming the old one, the code and the day it came; the old record stays, unchanged and inactive; not drawing on it again is the core's. The last day to act is **Tue Dec 8**, the sixth banking day after Nov 30.
- **(f)** The draft failed inside the window, before there was reasonable opportunity to act: reversed as (a), and no late penalty posts on the $60.00 (CI-057).
- **(g)** **Open (Kyle):** the window ended Dec 8 with the notice not acted on. CI-057 does not say. Is the customer still exempt (this stream's reading: yes, the failure is the utility's), and if so is the penalty never charged, or charged and reversed?
- **Open (Kyle):** where a tariff has a returned-payment fee, is it charged in (b)? And what follows (a) when the second presentment fails too, or the account is closed (R02)?

---

### SCN-0096 — A payment keyed for the wrong amount is reversed and entered again

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23).
*Rule:* a payment's amount, date and customer are never edited. A wrong one is reversed in full, naming it, and the right one entered; the customer's date stays the true one. A payment still pending moved no money, so it is voided instead. Sources: Kyle 10-15 (R-05); CI-013; CI-058.

**Given** BB-01 pays $65.83 in cash on Tue Dec 1, the due date; the clerk keys **$56.83** and posts it. On Dec 2 the drawer is $9.00 over.

**When** the clerk (a) changes the amount; (b) reverses and re-enters it on Dec 2, with Dec 1 as the customer's date; (c) had caught it while the payment was pending.

**Then**
- **(a)** Refused.
- **(b)** Refused while the $56.83 is applied to the bill: the application is undone first, then the payment reversed, then $65.83 recorded (customer's date Dec 1, method lockbox or office receipt) and applied. $65.83 − $56.83 + $56.83 − $65.83 = **$0.00**. The November bill was paid on time: no penalty; had one posted for the $9.00 on Dec 2 (its base is SCN-0033's Open), it is reversed as in SCN-0034. The reversal names the $56.83 payment; both payments stay on record.
- **(c)** The pending payment is voided; nothing was on the ledger to reverse. A posted payment cannot be voided, and a reversed one cannot be reopened.
- Where only part is wrong, a partial reversal is also possible (SCN-0101); full reversal and re-entry is this stream's reading of the usual workflow.

---

### SCN-0097 — A check bounces after its month is closed

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-22, -23).
*Rule:* the return posts in the open month; the closed month still shows the payment. Aging nets the payment and its return, so the bill ages from its own date. Sources: CI-110 and SCN-0005 (a closed period never reopens); SCN-0023 (aging).

**Given** BB-01 pays the November bill by check on Nov 20. November is closed on Dec 10 with BB-01 at $0.00.

**When** the check is returned on Mon Dec 14, and is recorded (a) dated Nov 30; (b) dated Dec 14; or (c) a refund is asked for as well (below).

**Then**
- **(a)** Refused: November is closed. **(b)** Accepted, once the application to the bill is undone; the undo is dated in December too, and one dated in November is refused.
- November's closed figures still show $0.00. On Dec 15 BB-01 owes **$65.83**, aged 29 days, from Nov 16: in 0–30 days.
- **(c)** As above, but BB-01 also has a payment of Nov 24, $20.00, unapplied (**invented**), so November closed at −$20.00. After the Dec 14 return BB-01 owes $45.83. A refund of the $20.00 dated Nov 30 is refused, and the same refund dated Dec 14 accepted: **$65.83**.

---

### SCN-0098 — The same mailed check is on time at one utility and late at another

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (CI-058, REP+PROT; v5.4.2-19): the date and its method are recorded and never change once the payment takes effect. **Not built:** a utility's stated method, or its change from a date.
*Rule:* whether a payment was on time is judged by the customer's date, set by the method the utility's tariff or its law states, and kept with the payment. Sources: CI-058; SCN-0021; SCN-0034.

**Given** two checks, each postmarked Tue Dec 1, the due date, and received Thu Dec 3: BB-01's, at Bluebonnet (postmark, `cast.md` §2), and GP-06's, at Gulf Plains, which counts the day the office received it (**invented**; due date **invented**). Gulf Plains charges a late penalty for this scenario only (**invented**).

**When** both are posted on Dec 3.

**Then**
- BB-01's customer date is **Dec 1**, method postmark: on time. GP-06's is **Dec 3**, method lockbox or office receipt: late.
- A payment cannot be posted without the date and its method; changing either afterwards is refused.
- A utility that changes its method does so from a date; payments already posted keep theirs.
- The methods on file are postmark, lockbox or office receipt, bank settlement, and other. Bluebonnet's "sent date" for electronic payments is recorded as other, with a note.
- 16 TAC §7.45 says nothing on when a mailed payment counts (read 2026-11-22), so Gulf Plains' method is its tariff's. Counsel confirms the current text.

---

### SCN-0099 — A new payment covers what a bounce left owed on no bill

*Status:* draft (2026-11-22), not yet sent to Kyle. Built as a record (v5.4.2-27); which debt a payment covers first is the core's.
*Rule:* a payment may be applied to a bounced payment's shortfall, as a credit may; no charge is invented. The payment then cannot bounce until the application is undone. A deposit payment, or a refund, is neither a source nor a target. Sources: v5.4.2-27; Kyle 10-30; K-05 (a deposit stays out of the pot).

**Given** SCN-0087 after the netting: BB-09 owes $10.00 on the bounced payment.

**When** BB-09 pays $10.00 by check on Dec 14, and (b) that check is returned on Dec 18; and, apart from the shortfall, (c) BB-09 owes a $60.00 bill (**invented**), pays $20.00 of it from a credit another payment left and $40.00 by a check, and that check is returned.

**Then**
- The $10.00 is applied to the shortfall. Balance **$0.00**; nothing is on a bill.
- **(b)** Refused until the application is undone; then the shortfall is $10.00 again, and the balance **$10.00**.
- Applying a deposit payment to the shortfall is refused. A bounced deposit payment is not a shortfall the pot repays: the deposit rules govern it.
- **(c)** What the credit paid stays paid; **$40.00** is owed on the bill, not as a shortfall. (A credit made from the same check goes with it: SCN-0086 c.)
- **Open (Kyle):** BB-09 owes the $10.00 and an open bill, and pays less than both: which first? Does the $10.00 have a due date, take a late penalty, or ground a disconnection? And how old is it: from the refund (Dec 8; the mirrored aging's answer) or the return (Dec 11)? It is also neither regulated nor unregulated by any record (SCN-0093's floor).

---

### SCN-0100 — A repayment is undone after the credit that made it went to the state

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-27).
*Rule:* when a credit's money repaid a shortfall, the credit's rest was later sent to the state, and the refund behind the shortfall then comes back uncashed, the repayment is undone and what it gives back becomes a new credit, in the same transaction. Sources: Ryan 2026-11-05 (-27 r1); Ryan 2026-11-06 (an undo is dated no later than today).

**Given** SCN-0087, except that the credit was **$30.00**: $20.00 of it was netted against a shortfall left at $20.00 (the refund was $20.00, **invented**), and the other $10.00 sent to the state on Nov 1, 2030 (**invented**).

**When** on Mar 3, 2031 the refund turns out never to have been cashed.

**Then**
- The $20.00 repayment is undone, with a reason and a user, and a new credit of **$20.00** names the undo. The old credit stays at nothing, closed. No ledger entry posts for the carry.
- The ledger: −$50.00 (payment) + $20.00 (refund) + $50.00 (return) − $30.00 (the credit's payment) + $10.00 (sent to the state, the core's entry) − $20.00 (refund returned) = **−$20.00**, the new credit.
- Refused: recording the refund's return with no undo; the undo with no new credit; a new credit of any other amount; an undo dated after today.

---

### SCN-0101 — A payment taken back only in part

*Status:* draft (2026-11-22), not yet sent to Kyle. Built (v5.4.2-23, -27 R3).
*Rule:* a reversal may be partial, and the two caps are kept apart: a take-back is at most the payment less earlier take-backs, a refund at most the payment less refunds and take-backs. A payment left short but not ended is not a shortfall the pot repays. Sources: R-02; Kyle 10-21 (the cap math); v5.4.2-27 R3.

**Given** BB-09 pays $50.00 and owes nothing: (a) by check, keyed $50.00 but deposited as $45.00; (b) by card, then $30.00 refunded, then the card company takes back $25.00.

**When** the $5.00 is taken back in (a), and a refund of $45.01, then $45.00, is asked for; in (b) the $25.00 is recorded.

**Then**
- **(a)** A refund of $45.01 is refused, $45.00 accepted. After that refund, a second take-back of $45.01 is refused and one of $45.00 accepted: −$50.00 + $5.00 + $45.00 + $45.00 = **$45.00** owed, as in SCN-0085.
- **(b)** −$50.00 + $30.00 + $25.00 = **$5.00** owed. The payment stays posted, since $25.00 of it stands. A credit applied to its $5.00 as a shortfall is refused; the core still shows one net figure, $5.00.
- **Open (Ryan, with the money stream):** how the $5.00 in (b) is ever marked paid.

---

### SCN-0102 — Money that has not arrived pays nothing, though it is on time

*Status:* draft (2026-11-22), not yet sent to Kyle. The arrival guard is built (v5.4.2-23). **Not built:** the utility's refund hold (Kyle 10-21, K-10 answer 3), off by default and kept out of the schema.
*Rule:* the customer's date decides whether a payment was on time; the day its money arrived decides when it can be drawn on. A utility may hold or warn on a refund while a payment could still be returned; by default it does neither. Sources: CI-058; -23 (r4); K-10, answer 3.

**Given** BB-01's bank draft of $65.83 for the November bill (due Tue Dec 1), sent Mon Nov 30, settled Thu Dec 3 (**invented**), customer's date Nov 30 under Bluebonnet's method (sent date).

**When** it is applied, or $20.00 of it refunded: (a) dated Wed Dec 2; (b) dated Dec 3; (c) as (b), at a utility whose refund hold is on for 10 calendar days from settlement, the settlement day not counted (**invented**); (d) as (c), with the setting "warn".

**Then**
- The November bill was paid on time: judged by Nov 30, before Dec 1, though the money came after it. No penalty posts; one posted on Dec 2 while the draft was pending is reversed as in SCN-0034.
- **(a)** Refused: the money had not arrived. **(b)** An application is accepted; a refund too, if nothing is applied. A payment still pending pays nothing and backs no refund.
- **(c)** The core refuses the refund through Dec 13 and accepts it dated Mon Dec 14. **(d)** It is accepted with a warning. Off by default: (b).

---

### SCN-0103 — Before unclaimed money goes to the state, a debt is netted only where the state allows it

*Status:* draft (2026-11-22), not yet sent to Kyle. The netting and the escheat guards are built (v5.4.2-23, -27); the state's row and the netting decision are the core's and **not built**. Whether any state allows the setoff has not been read (counsel).
*Rule:* netting a credit against another payment's debt, before reporting it as unclaimed, is a per-state rule; where the state does not allow it, or has no row, the credit is reported whole and the debt collected separately. Netting within one payment's own credits always applies. Sources: Ryan 11-02; AC-44.

**Given** PL-02 and BB-09, each on SCN-0087's facts, and neither ever asked for a refund, so no netting was recorded: each owes $30.00 on a bounced payment of December 2026 and holds a credit of $20.00 from another payment, dormant on Nov 1, 2030 (dates **invented**). The state is that of the owner's last known address (**invented** as the test's fact; counsel confirms the rule): PL-02's is in **Fremont**, whose row allows the setoff (`cast.md`); BB-09's in **Texas**, with no row.

**When** the escheat run of Nov 1, 2030 reads each credit. Until then each customer is shown one figure, **$10.00** owed.

**Then**
- **Fremont (PL-02):** the $20.00 is netted, recorded as in SCN-0087; nothing is reported; $10.00 owed.
- **Texas (BB-09):** the $20.00 is reported whole; BB-09 still owes **$30.00**, shown as $30.00 from that day and collected separately. **Open (Kyle):** the figure rises from $10.00 to $30.00 though BB-09 did nothing. Is that right, or should the pot have been used up at the bounce (SCN-0087's Open)?
- This is the opposite of SCN-0087's refund: before a refund the pot nets in every state (Kyle 10-30).
