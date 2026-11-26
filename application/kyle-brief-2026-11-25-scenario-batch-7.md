---
title: Scenario batch 7 (gas cost, zones and factors, meter reads): questions for Kyle
type: brief
status: DRAFT, not sent (Ryan sends, after batches 3 to 6)
created: 2026-11-25
blocks: the gas cost, zone and read scenarios being marked checked; the rates stream's patches for them
---

# To Kyle: scenario batch 7 (gas cost, zones and factors, meter reads)

Drafted 2026-11-25 by the scenarios stream, for Ryan to send **after batches 3 (K-14), 4 (K-16), 5 (K-18) and 6 (K-19)**. Sources: the "Open (Kyle)" notes in `scenarios/gas-cost-zones-and-reads.md` (SCN-0130 – 0154) after review round 7, and a reading of 16 TAC §7.45 and §7.5519 (Cornell LII, 2026-11-25). **Triaged 2026-11-25 (Ryan agreed):** of 25 draft questions, 17 are settled by standing rules (follow the tariff, with the platform default only where it is silent; the go-live rule; a refund is never held back; built behaviour) and recorded in the scenarios as "Settled by rule". Seven questions and the figures check remain. The scenarios are written ahead of the rates stream's patches (Ryan, 2026-11-25), so these answers shape them. Schema points are on the board for the rates stream, not here. One question is Ryan's (a meter recorded at the wrong address), not asked here.

Paste from here.

---

Kyle, batch 7: the gas cost figure, meter factors and meter reads. 7 questions and a figures check, most important first; "yes" is enough where we have it right. The worked cases are in `scenarios/gas-cost-zones-and-reads.md`. Where a tariff is silent we've used your rule (follow the tariff; the platform default only where it's silent) and made the point a setting each utility states at onboarding, so we only ask what could make a bill wrong or turns on Texas law. Background: we hold the billing side of gas cost only, as you ruled; and 16 TAC §7.5519 doesn't say when a factor takes effect, so each utility's tariff does.

1. (SCN-0132) A clerk keys a month's gas cost figure as $5.80 instead of $0.58, and it's approved and locked before anyone notices; bills go out at $5.80. We have a supervisor record a correction, and every bill issued at $5.80 is rebilled at $0.58. Is that right, or should a wrong locked figure stand, with the difference carried into next month's figure through the city's reconciliation?
2. (SCN-0138) A meter that reads in units of 10 Mcf was set up as 1×, so three bills at a city charged a tenth of the gas. We void and rebill the three bills, each at its own month's rates, with the hidden $798.41 due with the next bill. Is that right, or does it go on the next bill as one prior-period line? Do cities usually offer to spread a charge like that?
3. (SCN-0141) After an estimate, the next actual reading comes in below the estimated reading, so the next bill credits 2.0 Mcf. Is that credit right, and should it be priced at the estimated month's rates rather than this month's? (We catch up on the next read by default; a utility can choose to rebill the estimated bill instead.)
4. (SCN-0130) Each utility says what its "billing month" is at onboarding. Our default is the month the bill is issued. That means a bill held a few days past month end takes the next month's gas cost figure ($66.80 instead of $65.83 in our example). Is the issue month the right default, or should it be the month the billing period ends?

*Gulf Plains (16 TAC §7.45 binds)*
5. (SCN-0142) Is an aggressive dog "beyond the utility's control" for the bar on cutting off for an unpaid estimated bill (§7.45(4)(E)(vii))? Our sorting of skip reasons is an engineering proposal: a locked gate, dog, unsafe conditions, no permission and weather count as beyond; an offline meter, a malfunction and a new install count as within.
6. (SCN-0142) The customer returns the self-read card. Does that reading end the run of estimates, and does it count as the actual reading Texas requires every six months? (Your July answer said no customer-initiated reads in v1; this one the utility asked for.)
7. (SCN-0148) Six months with no actual reading (a gate the customer keeps locked; cards sent, none back). Your ruling says to surface the breach, not quietly block it, and §7.45 says bills go out monthly. So we issue the next estimate with the breach recorded, a supervisor's sign-off and a field order to get a reading. Right?

*Figures*
8. Please check the dollar figures in `scenarios/gas-cost-zones-and-reads.md`. Invented for the tests: every gas cost figure, the pressure zones and their factors, Gulf Plains' rates, factor timing and carry-forward term, the estimate methods and caps, and the meters' dials.
