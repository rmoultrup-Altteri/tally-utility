---
title: Scenario batch 8 (gas reads, the second set of added cases): question for Kyle
type: brief
status: DRAFT, not sent (Ryan sends)
created: 2026-11-26
blocks: SCN-0155 being marked checked; the figures of SCN-0155 – 0162
---

# To Kyle: scenario batch 8 (an estimated final reading)

Drafted 2026-11-26 by the scenarios stream. Sources: the "Open (Kyle)" notes in `scenarios/gas-cost-zones-and-reads.md` SCN-0155 – 0162 after review round 9 (`scenarios/review/2026-11-26-gas-3/`). Triaged by standing rules before drafting: the other points are settled in the scenarios ("Settled by rule"): the customer charge in a month with no reading (CI-102); which months an average reads and which history "same month last year" reads (utility settings, with this stream's proposed defaults); a back-dated actual (built behaviour); a corrected final bill's due date and penalty (SCN-0033's settled rule). One question and a figures check remain.

Paste from here.

---

Kyle, batch 8: a short one, the last of the gas read cases. 1 question and a figures check; "yes" is enough where we have it right. The worked cases are in `scenarios/gas-cost-zones-and-reads.md` (SCN-0155 – 0162).

1. (SCN-0155) A customer moves out and the final reading can't be taken (locked yard), so the final bill is estimated: 3.0 Mcf for the last 10 days. The new owner's first actual reading, 21 days later, shows 8.0 Mcf used since the last actual before the move. We share the 8.0 by days (2.6 to the old customer, 5.4 to the new one), correct the final bill (a $3.59 refund here; if the estimate was low, the old customer owes more) and bill the new owner from the corrected reading. The alternative is to bill the new owner from the estimated reading and let the final bill stand, so the estimate's error stays with whichever customer it favoured. Is sharing by days right? We'd make it a utility setting with that as the default.

*Figures*
2. Please check the dollar figures in SCN-0155 – 0162. Invented for the tests: every customer, reading and usage history; Bluebonnet's estimate averaging only months billed on actual readings; Gulf Plains estimating a new customer from the address's history; the refund and due dates.
