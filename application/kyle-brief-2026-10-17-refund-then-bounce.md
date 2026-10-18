---
title: TallyUtility — a refunded payment that then bounces: questions for Kyle
type: brief
status: DRAFT for Ryan's review. Not sent.
created: 2026-10-17
blocks: the refund and bounce rules in v5.4.2-23 (cash), revision r2; R-02 as applied to refunds; CI-017, CI-055, CI-058
---

# A refunded payment that then bounces — what we need from you

2026-10-17 · Ryan Moultrup

Kyle — one question, with two small follow-ons, is holding the cash patch. It is about how your R-02 ruling applies to refunds. A one-line answer to each is enough.

## What we need from you

| # | Question | Answer with |
| --- | --- | --- |
| 1 | Is a refund a *reversal* of the payment it returns, in R-02's sense? Or is it its own movement of money that merely points back to the payment? | **A. Its own movement**, **B. A partial reversal; the refunded amount is billed back if the payment bounces**, or another rule |
| 2 | A payment bounces while a refund of it is still waiting to go out. What happens to that refund? | **Cancel it first; the bounce is refused until it is cancelled**, or **cancel it automatically with the bounce** |
| 3 | Should a refund be allowed out of a payment that could still come back (a check or ACH payment inside its return window)? | **Allow it**, **refuse it**, or **leave it to each utility's policy** |

## The case

A customer pays **$50 by check**. We refund them **$30** (an overpayment, say). Then the check **bounces**, and the bank takes the full $50 back from the utility.

What should be true afterwards: the utility received nothing, paid out $30, and the customer owes the utility **$30**.

## Why it doesn't work today

Your R-02 says every reversal names the entry it reverses, and reversals against an entry total at most the entry. The draft treats a refund as a reversal of the payment, so:

- the $30 refund uses $30 of the payment's $50;
- the bounce can reverse only the $20 that is left;
- a $50 bounce is refused, and there is no lawful way to record what the bank did.

Recording a $20 bounce instead would lose the $30. The customer would owe nothing, while the utility is out the $30 it paid them.

## Question 1 — Is a refund a reversal?

| Option | What is recorded | The customer's account after the bounce |
| --- | --- | --- |
| **A. Its own movement** | The refund is money paid out to the customer. It still points to the payment it came from, and it still can't exceed what is left of the payment. The bounce reverses the full $50. | +$30 owed (−$50 paid, +$30 refunded, +$50 bounced) |
| **B. A partial reversal** | The refund reverses $30 of the payment, as now. The bounce reverses the $20 that is left. A new $30 charge, naming the bounced payment, bills back the refund. | +$30 owed (−$50, +$30, +$20, +$30 charge) |

Both options leave the customer owing $30. They differ in what the records say:

- **A** matches the bank: one $50 return against one $50 payment. The refund is a separate payment out, as it is on the utility's own books.
- **B** keeps "a refund reverses the payment". But the bank's $50 return appears as $20 on our side, and the $30 has to be found again as a charge. Matching the bank statement then means adding the two back together.

**Our preference, as input only: A.** A refund is real money sent out, and it stays sent out whatever later happens to the payment. Treating it as an undo is what breaks the bounce. R-02 is unchanged for everything that really is an undo: bounces, voids, reversed adjustments and write-off recoveries.

## Question 2 — A refund still waiting to go out

Under either option, a refund that hasn't been sent should not be sent once the payment it comes from has bounced. That would return money never received. Our default: **the bounce is refused until the pending refund is cancelled**. The operator has to take that step, and the record shows it. The alternative is to cancel the refund automatically as part of the bounce.

## Question 3 — Refunds inside the return window

Some utilities hold refunds until a check or ACH payment can no longer be returned. A rule like that makes the case above rarer. It doesn't remove it, because late returns happen. So it doesn't replace Question 1. Our default is **leave it to each utility's policy**, recorded in its tariff rows, with nothing enforced by the database.

## Why this matters

The cash patch (v5.4.2-23) is in its second revision, and all three reviewers flagged this case. Everything else in that revision goes ahead. Only the rule for which ledger rows count as reversals, and the bounce-with-a-refund checks, wait on your answer. Nothing is live, so either option costs nothing to build now. Changing it after go-live would mean rewriting every reader of the payment history.
