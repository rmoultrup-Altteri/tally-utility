---
title: Scenario batch 7 (gas cost, zones and factors, meter reads): questions for Kyle
type: brief
status: DRAFT, not sent (Ryan sends, after batches 3 to 6)
created: 2026-11-25
blocks: the gas cost, zone and read scenarios being marked checked; the rates stream's patches for them
---

# To Kyle: scenario batch 7 (gas cost, zones and factors, meter reads)

Drafted 2026-11-25 by the scenarios stream, for Ryan to send **after batches 3 (K-14), 4 (K-16), 5 (K-18) and 6 (K-19)**. Sources: the "Open (Kyle)" notes in `scenarios/gas-cost-zones-and-reads.md` (SCN-0130 – 0145) after review round 7, and a reading of 16 TAC §7.45 and §7.5519 (Cornell LII, 2026-11-25). The scenarios are written ahead of the rates stream's patches (Ryan, 2026-11-25), so these answers shape them. Schema points are on the board for the rates stream, not here. One question is Ryan's (a meter recorded at the wrong address), not asked here.

Paste from here.

---

Kyle, batch 7: the gas cost figure on a bill, pressure factors, and meter reads. 17 questions; each says what we've written, so "yes" is enough where we have it right. The worked cases are in `scenarios/gas-cost-zones-and-reads.md`. Three things first. (1) We hold the billing side only, as you ruled: each month's gas cost figure, what was billed under it, and the volumes; purchases and the balance stay with the utility. (2) None of our three test utilities bills in therms or has weather normalization, so those wait. (3) 16 TAC §7.5519 doesn't say when a gas cost factor takes effect (it leaves that to the Commission case by case), so we take the timing from each utility's tariff.

*The gas cost figure*
1. (SCN-0130) We take "billing month" as the month a bill is issued, so a November-usage bill issued Dec 2 gets December's figure. A bill held by a read exception from Nov 16 to Dec 1 then also gets December's figure, only because it went out late. Is the issue month what a city means? Should each utility state it at onboarding (issue month, or the month the period ends), with no default?
2. (SCN-0131) A small city sets its figure mid-month from the supplier's invoice, not at month end. Is that fine for that month's bills? Is the figure locked when a supervisor approves it?
3. (SCN-0131) If the invoice is late and bills go out on the 22nd instead of the 20th, do they keep the usual due date (the 1st), or get the usual time to pay?
4. (SCN-0132) A clerk keys $5.80 for $0.58, and it's approved and locked. We have a supervisor record a correction, and every bill issued at $5.80 is rebilled. Is that right, or should a wrong locked figure stand, with the difference carried into next month's figure?
5. (SCN-0134) For the city's reconciliation, does a correction of an earlier bill count in the month of the figure it used, or the month it posted? We keep both.
6. (SCN-0135) Pecan Flat's tariff: $20 minimum, $9.00 per Mcf plus the gas cost. We count the gas cost toward the $20. Does any city floor only the rate, with the gas cost on top?

*Factors*
7. (SCN-0137) A pressure zone's factor changes on Mar 1, partway through a Feb 15 – Mar 14 period. We treat it like a rate change: the utility says at entry whether it's split by days, taken at the read date, or by cycle. Right? Or is a factor always split by days, or always the factor at the read date?
8. (SCN-0138) A 10× meter set up as 1×, found after three bills at a city. We void and rebill the three bills, each at its own month's rates, with the hidden $798.41 due on the next bill. Is that right, or does it go on the next bill as one prior-period line? Do cities usually offer to spread a charge like that?

*Reads*
9. (SCN-0140) Pecan Flat re-reads free once a year, $5 after, free if the city's read was wrong. Does a request that finds the city wrong use up the free one?
10. (SCN-0140) A read keyed too high and billed: we always rebill (a refund isn't held back to the next read). Is catch-up on the next read ever acceptable for an overcharge?
11. (SCN-0141) At a city, when the next actual read follows an estimate, is catch-up (next bill = actual minus estimated reading) the usual method, or is the estimated bill voided and rebilled?
12. (SCN-0141) The actual comes in below the estimate, so the next bill credits 2.0 Mcf. Is that credit allowed, and should it be priced at the estimated month's rates rather than the current month's?

*Gulf Plains (Texas rules bind)*
13. (SCN-0142) Is an aggressive dog "beyond the utility's control" for §7.45(4)(E)(vii)? Our sorting of skip reasons (gate, dog, unsafe, no permission, weather: beyond; meter offline, malfunction, new install: within) was an engineering proposal, not your ruling.
14. (SCN-0142) The customer returns the self-read card. Does that reading end the run of estimates, and does it count as the actual reading Texas requires every six months? (Your July answer said no customer-initiated reads in v1; this one the utility asked for.)
15. (SCN-0142) An actual reading dated earlier than estimates already entered: should it raise its own review? (Open since August.)
16. (SCN-0142) With a cap of 3, the third estimate in a row needs a supervisor's override or a field order. Is that how you meant the cap (the third needs a decision), or should three go through and the fourth stop?

*Figures*
17. Please check the dollar figures in `scenarios/gas-cost-zones-and-reads.md`. Invented for the tests: every gas cost figure, the pressure zones and their factors, Gulf Plains' rates and factor timing, the estimate methods and caps, and the meters' dials.
