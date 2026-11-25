---
title: Scenario batch 3 (disputes, penalties and corrections, backbilling): questions for Kyle
type: brief
status: DRAFT, not sent (Ryan sends first; batches 4 and 5 follow it)
created: 2026-11-22 (as a Slack draft); rebuilt as a file 2026-11-24
blocks: the batch 2 scenarios being marked checked
---

# To Kyle: scenario batch 3 (disputes, penalties and corrections, backbilling)

K-14 in the roadmap. Drafted 2026-11-22 by the scenarios stream as a Slack draft in Kyle's DM. Rebuilt here on 2026-11-24 from that session's transcript, word for word, because the money stream later saved its own draft (K-17) to the same DM, and nobody could confirm the batch 3 draft was still there. The edits the 2026-11-22 handoff asked Ryan to make by hand are made here: item 6 now describes the later-due $13.23, and the figure check names it and adds two figures. If an older batch 3 draft is still in the DM, delete it and paste this one.

Send this first, then batch 4 (`kyle-brief-2026-11-22-scenario-batch-4.md`, whose questions 18–22 assume Kyle accepts item 6 here), then batch 5 (`kyle-brief-2026-11-24-scenario-batch-5.md`).

Paste from here.

---

Kyle, thanks for the batch 2 answers. They're folded into the scenarios. Here's a short third batch: 9 questions and a figure check. Each SCN number points to the full worked case in [tally-utility/scenarios](https://github.com/rmoultrup-Altteri/tally-utility/tree/main/scenarios). A one-line answer to each is plenty.

**Disputes (your batch 2 answer 1, and flag 1)**
I settled the start and end, and it came out narrower than "no late penalty at all":
- A city's own dispute rule wins. Where Texas law binds, the law's rule governs.
- Only a city with no rule gets our default: a dispute raised before the due date protects the disputed amount (the whole bill if no amount is recorded), for every customer class, until it's resolved or the 60 days run out, counting the issue day as day 1. It blocks the late fee and ordering or carrying out a disconnection.
- If the 60 days run out unresolved, the disputed amount moves to the next bill's due date, and a penalty posts only if that date passes unpaid. It's reversed if the customer wins.

1. (SCN-0033) CI-054 and CI-074 bar a late fee on a disputed amount while the dispute is active, with no time limit. The 60-day end departs from that. Do you accept it?
2. (SCN-0033) Brenham says the disputed bill "should still be paid" and doesn't mention penalties. We read that as: the penalty still posts on an unpaid disputed bill. That also departs from CI-054. Agree?
3. CI-074 also bars dunning notices on the disputed amount. Our default doesn't block notices, collections referral or credit reporting. Is that OK?

**Penalties and corrections**
4. (SCN-0053) Pecan Flat's "10% of the amount due" on the full-amount base means the same unpaid $95 is penalized again every month ($9.50 in February, $9.50 again in March). I've made "once or every month" a setting each city on that base must answer, with Pecan Flat set to every month. Did you mean it to repeat, and should tariff counsel check it?
5. (SCN-0027, 0028, 0033, 0069) You put the extra our error hid on the next regular bill. Is that for every upward correction (for example a rate misapplication), or only a misread rebill? The scenarios outside SCN-0033 still keep the increase on the correction itself.
6. (SCN-0033) The corrected bill is charged at the full true figure ($79.06), shown with "of which $13.23 is due with your next bill", so $65.83 is due now. The next bill shows the $13.23 without charging it again. This needs a record that part of a bill is due later, so your "no schema change" no longer holds. Any objection? The next bill prints the $13.23 but holds no line for it; money for it pays the November charges, so it can't be paid twice. Your answer said a line.

**Backbilling and deposits**
7. (SCN-0039) Your answer 12 (pre-go-live refunds paid month by month with the legacy record and a supervisor's approval; nothing for a month with no record) was for silent cities. Does it also apply where §7.45 binds?
8. (SCN-0045) Your flag 2: is a check returned through the bank's own error left out of the returned-check count?
9. (SCN-0011) Your flag 2: when a senior proves age later, is it the same identity check as at sign-up, and is there a time limit on the $60 correction?

**Figures to check**
- Your flag 6: batch 2's figures.
- New since then: SCN-0069, 0070 and 0078, and SCN-0033's re-based penalties ($6.52 + $0.07 = $6.59) and later-due amount ($13.23, of which $13.10 is penalty base, so $1.31 + $0.01 if the December bill goes unpaid); $85.65 owed on December 4 (of which $13.23 isn't due yet); and $13.23 for SCN-0089 (b).
