---
title: Scenario batch 6 (unmatched cash and agency pledges): questions for Kyle
type: brief
status: DRAFT, not sent (Ryan sends, after batches 3, 4 and 5)
created: 2026-11-25
blocks: the unmatched-cash and pledge scenarios being marked checked
---

# To Kyle: scenario batch 6 (unmatched cash and agency pledges)

Drafted 2026-11-25 by the scenarios stream, for Ryan to send **after batches 3 (K-14), 4 (K-16) and 5 (K-18)**. Sources: the "Open (Kyle)" notes in `scenarios/unmatched-cash-and-pledges.md` (SCN-0117 – 0129), after review round 6, and a reading of 16 TAC §7.460(b)(2) and Texas Property Code §72.101, §76.001 and §76.301 (2026-11-25). Ryan settled two points the same day, so they are not asked: a utility cannot go live until it states its settings for held money and its pledge rule; a pledge carries the day the utility received it. Schema points are on the board for the money stream, not here.

Paste from here.

---

Kyle, batch 6: money we can't match to a customer yet, and pledges from assistance agencies. 16 questions; each says what we've written, so "yes" is enough where we have it right. The worked cases are in `scenarios/unmatched-cash-and-pledges.md`. Two things you should know first. (1) Money nobody can match is held apart from every customer until an operator identifies it; it's never posted on a guess, even when the amount matches someone's bill exactly. (2) Gulf Plains (investor-owned) is bound by 16 TAC §7.460(b)(2): no disconnection of a delinquent residential customer "for a billing period in which the provider receives a written pledge … that it is forwarding sufficient payment to continue service". The city systems aren't bound by it, so for them each city states its own pledge rule before go-live.

*Money we can't match yet*
1. (SCN-0117) A check with no account number arrives the day after the due date, postmarked before it. The late penalty posts that night because the bill looks unpaid; two days later we identify the customer, and the penalty is reversed because the postmark was on time. Should the core instead hold penalties on any customer the held money might belong to until it's identified, or is post-then-reverse right?
2. (SCN-0120) Held money past the utility's handling limit (10 days in our example) stops a cut-off of any customer it might belong to. Within the first 10 days nothing stops it. Should a possible owner be protected from the day the money came?
3. (SCN-0120) Pecan Flat adds a $20 service charge when a bill is unpaid at 1:00 p.m. on the 10th, and cuts service off. If the cut-off is held because of unidentified money, is the $20 still added?
4. (SCN-0129) An agency's check covers three customers, and one name on its list matches nobody. Should intake list as possible owners every customer with an open pledge from that agency, so they're protected from a cut-off meanwhile?
5. (SCN-0118, 0122) A landlord's check pays two tenants' bills. If it overpaid, does the refund go to the tenant (the account holder) or the landlord who wrote it? If it bounces, do the returned-check fees fall on the tenant whose bill it was posted to, and on the other tenant for the part never posted?

*Money nobody claims*
6. (SCN-0119) We give each utility a retention period (180 days in our example) after which held money is returned to whoever sent it if they can be found. Texas presumes money abandoned only after three years (Property Code §72.101), and a city holding $100 or less sends it to its own treasurer, not the state (§76.001, §76.301). Is 180 days a sensible suggestion at onboarding, and do cities actually return checks to senders they can find?
7. (SCN-0119) A check came with the sender's address; we mailed it back and it came back undeliverable seven months later. Do the three years run from the day the money came, or from the day the address proved wrong?

*Pledges*
8. (SCN-0124) A CEAP pledge reaches Gulf Plains on Sep 11. The rule protects "for a billing period", here Sep 1 – 30, but the agency has 45 days, to Oct 25. If the agency hasn't paid by Oct 1, may Gulf Plains disconnect, or does the vendor agreement's "not delinquent if paid within 45 days" hold the pledged amount to Oct 25? And which period is "the billing period": the month of service the pledge arrives in, or the period of the last bill issued?
9. (SCN-0124) "Sufficient payment to continue service": the customer is $47.80 delinquent and the agency pledges $30.00. Does that protect?
10. (SCN-0124) A pledge by phone isn't "written", so we don't treat it as protecting until the letter arrives. Does a pledge entered in the agency's web portal count as written?
11. (SCN-0124) The pledge's pay-by date falls on a Sunday. Does the agency have until Monday?
12. (SCN-0124) The vendor agreement keeps service on for up to five business days while the agency checks eligibility, before any pledge exists. How do utilities learn an agency is checking a customer, and what holds the cut-off in those days?
13. (SCN-0124) City systems: when their tariff says nothing about pledges, what do they do in practice: follow the CEAP agreement's 45 days, or something else? (This is what we'll suggest at onboarding.)
14. (SCN-0125) An agency's payment posts, the pledge reads paid, then the check bounces after the pay-by date. Does the customer get a fresh disconnection notice before a cut-off resumes?
15. (SCN-0127) An agency overpays its pledge and the extra is left over. A leftover becomes a credit for later bills only with approval: the customer's approval or the agency's? (A refund of it always goes to the agency, by 10 TAC §6.312(f).)
16. (SCN-0129) An agency pays for a customer with no pledge on file. Should the utility ask the agency for the pledge, or is the payment enough?

*Figures*
Please check the dollar figures in `scenarios/unmatched-cash-and-pledges.md`. Invented for the tests: every agency and its agreement (CEAP's 45 days and five business days are the real vendor agreement's terms); each utility's 10-day handling limit and 180-day retention; Gulf Plains billing on the 5th, due 20 days later; Pecan Flat counting a payment on the day received.
