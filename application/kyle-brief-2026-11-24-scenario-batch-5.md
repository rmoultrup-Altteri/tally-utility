---
title: Scenario batch 5 (tax by location): questions for Kyle
type: brief
status: DRAFT, not sent (Ryan sends, after batches 3 and 4)
created: 2026-11-24
blocks: the tax scenarios being marked checked
---

# To Kyle: scenario batch 5 (tax by location)

Drafted 2026-11-24 by the scenarios stream, for Ryan to send **after batches 3 (K-14) and 4 (K-16)**. Sources: the "Open (Kyle)" and "To confirm" notes in `scenarios/tax.md` (SCN-0104 – 0116), after review round 5 and a reading of 34 TAC §3.287, §3.295, §3.334 and Tax Code §151.051, §321.3025 (2026-11-24). Questions for the rates stream (schema) are on the board, not here. The invented facts Kyle should know before checking figures are in question 11.

Paste from here.

---

Kyle, batch 5: tax by location. 11 questions; each says what we've written, so "yes" is enough where we have it right. The worked bills are in `scenarios/tax.md`. Neither of the Comptroller's rules we read (34 TAC §3.295 on gas and electricity, §3.334 on local taxes) answers question 1, and the certificate rule (§3.287) says nothing about a billing period for question 5, which is why they come to you. On question 3 the statute gives the legal position; the question is what the utility does.

*When a tax starts or changes*
1. (SCN-0108, 0109) A tax starts or changes on a quarter's first day (Apr 1), and a bill's period runs Mar 15 – Apr 14. Is the whole bill taxed, none of it (the first bill wholly after Apr 1 carries it), or the taxed lines split by days? We suggest the utility states its method when it enters the change, as you ruled for rate changes. OK?
2. (SCN-0109) The utility approves a published rate increase late, after bills went out at the old rate. It owes the higher tax anyway (our reading). Does it correct those bills, put the difference on the next bill, or absorb it? And if one of those bills is later voided and rebilled for another reason, we charge the new rate on the rebill. Right?
3. (SCN-0108) A home in newly annexed land was charged city and crime-control district tax on one bill before the tax was in force there, by a clerk's mistake ($0.65 city, $0.16 district). By law (Tax Code §321.3025) the city's part counts as the city's revenue, and the customer may claim a refund; we found no such rule for the district's part. We credit the whole $0.81 to the customer when found. OK, or leave it to them to claim?

*Exemptions*
4. (SCN-0107) A certificate is verified in November, dated back to January. We don't change past bills by ourselves; an operator decides whether to credit the tax, and we record who decided. Is there a default, and how far back may the credit go? (The customer can also claim from the Comptroller, §3.295(h)(1).)
5. (SCN-0107) A certificate ends Oct 31, inside a period of Oct 15 – Nov 13. Is that bill exempt, taxed, or split?

*Residential or not*
6. (SCN-0111) One meter serves a home and a hair salon. The law taxes it all or nothing by predominant use each billing period. Who decides the use each period: the use the utility has on record for the premise (changed when the customer tells us), or a share of business use stated for each bill?
7. (SCN-0111) A house rented to visitors by the week: we tax it as non-residential (the visitors aren't tenants for over 29 days). Right?

*Penalties and payments*
8. (SCN-0104) The 10% late penalty (a forfeited prompt-payment discount, which you ruled is "taxed like the gas"). On a business's bill that means state and county tax too, not only city. Right?
9. (SCN-0114) A part payment reaches a bill's tax lines but can't pay them all. Paid in stack order (state first), or in proportion? And does the utility report tax when it bills it or when it collects it? If collected, is that the month the payment posts or the month of the bill it paid? We keep both figures either way.
10. (SCN-0114) Beside each jurisdiction's tax we also show the exempt sales (the courthouse's $444.10), for the return. OK?

*Figures*
11. Please check the dollar figures in `scenarios/tax.md`. Invented for the tests: Bluebonnet's own 1% city tax, older than Oct 1, 1979 and kept on homes; Bluebonnet County 0.5%; a crime-control district 0.25% (from Jan 2027, taxing homes too); a transit authority at 0.25% on part of the city, until Sep 30, 2027 (every local tax counts toward the 2% limit, transit included); the city's rate published at 1.25% from Oct 2027; Pecan Flat's city tax 1.5%, adopted in 1987 so it can't reach homes, and its county levying none. Real: the state's 6.25%. Two earlier scenarios changed: a large business outside the city now pays state and county tax (SCN-0055 c, $447.32), and a home's March 2027 bill now carries the district's $0.16 (SCN-0054 a, $66.99).
