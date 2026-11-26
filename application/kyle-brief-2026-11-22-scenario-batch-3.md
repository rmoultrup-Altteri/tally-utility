---
title: Scenario batch 3 (disputes, penalties and corrections, backbilling): questions for Kyle
type: brief
status: DRAFT, not sent (Ryan sends first; batches 4 to 7 follow it)
created: 2026-11-22 (as a Slack draft); rebuilt as a file 2026-11-24
blocks: the batch 2 scenarios being marked checked
---

# To Kyle: scenario batch 3 (disputes, penalties and corrections, backbilling)

K-14 in the roadmap. Drafted 2026-11-22 by the scenarios stream as a Slack draft in Kyle's DM. Rebuilt here on 2026-11-24 from that session's transcript, word for word, because the money stream later saved its own draft (K-17) to the same DM, and nobody could confirm the batch 3 draft was still there. The edits the 2026-11-22 handoff asked Ryan to make by hand are made here: item 6 now describes the later-due $13.23, and the figure check names it and adds two figures. If an older batch 3 draft is still in the DM, delete it and paste this one. **Triaged 2026-11-25 (Ryan agreed):** of 9 draft questions, 5 are settled by standing rules (follow the tariff, with the platform default only where it is silent; an existing ruling of Kyle's or Ryan's answers it; a refund is never held back; record shapes are the stream's) and recorded in the scenarios as "Settled by rule", and two more are merged into one. Three questions and the figures check remain. The old item 6 (the hidden $13.23 as one charge with part of it due later, printed on the next bill but not a line of it) is no longer asked: it rests on Ryan's ruling of 2026-11-22 (DECISION-LOG), and the opening note tells Kyle.

Send this first, then batch 4 (`kyle-brief-2026-11-22-scenario-batch-4.md`), batch 5 (`kyle-brief-2026-11-24-scenario-batch-5.md`), batch 6 (`kyle-brief-2026-11-25-scenario-batch-6.md`) and batch 7 (`kyle-brief-2026-11-25-scenario-batch-7.md`), in that order.

Paste from here.

---

Kyle, thanks for the batch 2 answers. They're folded into the scenarios. Here's a short third batch: 3 questions and a figures check, most important first; "yes" is enough where we have it right. Each SCN number points to the full worked case in [tally-utility/scenarios](https://github.com/rmoultrup-Altteri/tally-utility/tree/main/scenarios). Where a tariff is silent we've used your rule (follow the tariff; the platform default only where it's silent), so we only ask what could make a bill wrong or turns on Texas law. One thing to know first, on your answer 2: I decided the extra our error hid ($13.23 in SCN-0033) is charged once, on the corrected bill, with a record that it's due with the next bill. The next bill prints it but doesn't charge it again, so it can't be paid twice. The amount and the due date are as you ruled.

1. (SCN-0033) Disputes. A city's own dispute rule wins, and where Texas law binds, the law's rule governs. A city with no rule gets our default: a dispute raised before the due date protects the disputed amount (the whole bill if no amount is recorded), for every customer class, until it's resolved or the 60 days from issue run out (the issue day is day 1). It blocks the late fee and ordering or carrying out a disconnection. If the 60 days run out unresolved, the disputed amount moves to the next bill's due date, and a penalty posts only if that date passes unpaid; it's reversed if the customer wins. Bluebonnet uses Brenham's own rule, which says a disputed bill "should still be paid" and says nothing of penalties, so there a penalty posts on an unpaid disputed bill. Either way a penalty can reach an amount still in dispute, where two of our invariants (CI-054 and CI-074) bar a late fee on an amount under active dispute until the dispute is resolved. We think both are acceptable: a city's rule governs, and the 60 days stop a forgotten dispute from holding off a penalty for good. Agree?
2. (SCN-0027, 0028, 0033, 0069) You put the extra our error hid on the next regular bill (answer 2), and SCN-0033 does that for a misread rebill. The other upward corrections we've written keep the increase on the correction itself, with a new due date counted from the correction: a rate keyed wrong (SCN-0069, $1.63), a rate misapplied (SCN-0027 a), and a silent city's six-month default (SCN-0028). Is that right, or should those go to the next regular bill too?
3. (SCN-0039) Your answer 12 (pre-go-live refunds paid month by month with the legacy record and a supervisor's approval; nothing for a month with no record) was for silent cities. Where §7.45 binds, as at Gulf Plains, we hold that part of the refund until the old bills are loaded, and never close it as unrecoverable. Is that right, or does answer 12 apply there too, including no refund for a month with no record?

*Figures*
4. Your flag 6: batch 2's figures. New since then: SCN-0069, 0070 and 0078, and SCN-0033's re-based penalties ($6.52 + $0.07 = $6.59) and later-due amount ($13.23, of which $13.10 is penalty base, so $1.31 + $0.01 if the December bill goes unpaid); $85.65 owed on December 4 (of which $13.23 isn't due yet); and $13.23 for SCN-0089 (b).
