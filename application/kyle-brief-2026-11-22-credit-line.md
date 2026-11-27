# To Kyle: a bill's credit line (K-17)

K-17 in the roadmap. Drafted 2026-11-22 by the money stream as a Slack draft in Kyle's DM. Recovered here on 2026-11-27 from that session's transcript, word for word, because a DM holds one draft, the scenario batches were later pasted into the same DM, and nothing records this one as sent. Not part of batches 3 to 8. If Kyle's DM has no message containing "Gas cost credit: -$6", paste from below.

Paste from here.

---

Hey Kyle, one question on bills that carry a credit as one of their lines, like a month when the gas cost adjustment is negative.

**The problem.** We apply payments to individual charges. Take this bill (made-up numbers):

- Customer charge: $15
- Gas used: $50
- City tax: $1
- Appliance plan (not regulated): $10
- Gas cost credit: -$6
- **Customer owes: $70**

The four charges add up to $76. Right now nothing says which charge the $6 credit reduces, so after the customer pays the full $70, the system still shows $6 unpaid on this bill. Oldest-first would then put $6 of the next payment here and leave the next bill short. The customer's balance stays right, but the open amount on the bill doesn't.

**The question: which charge or charges should the credit reduce?**

**A. None of them.** Just cap the bill at $70. After full payment one charge (here the appliance plan) would still look $6 unpaid.

**B. The first charge in the utility's own payment order,** as if the credit were a payment made on day one. If the customer charge comes first, $15 becomes $9. Nothing new to set up, but a gas credit comes off the customer charge.

**C. Spread across the gas charges in proportion.** $15 becomes $13.62 and $50 becomes $45.38.

**D. The charge it belongs to.** The gas credit comes off the gas, so $50 becomes $44. Setup has to say which charge each kind of credit belongs to, and we'd need a fallback when the credit is bigger than that charge.

**Where it matters.** Paid in full, B, C and D all read $0. On most partial payments they come out the same too. The clearest difference is a dispute: if the customer disputes the gas charge, it reads $44 under D but $50 under B, so B could protect $6 too much.

In B, C and D we're assuming a regulated credit never reduces an unregulated charge, and that it reduces taxes and state fees only last. Tell us if either is wrong.

Two things would help:
1. Which one, and is it a platform rule or a utility setting?
2. Do you know of a tariff or a billing system convention that says how this works?
