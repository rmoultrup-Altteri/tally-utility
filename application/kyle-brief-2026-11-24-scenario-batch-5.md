---
title: Scenario batch 5 (tax by location): questions for Kyle
type: brief
status: SENT 2026-11-26 (Ryan, by Slack: batches 3 to 7 in two messages), awaiting answers
created: 2026-11-24
blocks: the tax scenarios being marked checked
---

# To Kyle: scenario batch 5 (tax by location)

Drafted 2026-11-24 by the scenarios stream, for Ryan to send **after batches 3 (K-14) and 4 (K-16)**. Sources: the "Open (Kyle)" and "To confirm" notes in `scenarios/tax.md` (SCN-0104 – 0116), after review round 5 and a reading of 34 TAC §3.287, §3.295, §3.334 and Tax Code §151.051, §321.3025 (2026-11-24). Questions for the rates stream (schema) are on the board, not here. The invented facts Kyle should know before checking figures are in the figures item. **Triaged 2026-11-25 (Ryan agreed):** of 11 draft questions (the last a figures check), 4 are settled by standing rules (an existing ruling of Kyle's answers it; a refund is never held back; record shapes and report layouts are the stream's) and recorded in the scenarios as "Settled by rule", and half of a fifth (whether tax is reported when billed or when collected is the utility's own reporting basis, stated at onboarding). Two more are merged into one. Five questions and the figures check remain.

Paste from here.

---

Kyle, batch 5: tax by location. 5 questions and a figures check, most important first; each says what we've written, so "yes" is enough where we have it right. The worked bills are in `scenarios/tax.md`. Where one of your answers already covers a point we've applied it (for example, your "taxed like the gas" puts state and county tax on a business's late penalty too, still subject to the tax advisor's check before a gross/net city goes live), so we only ask what sets the amount of tax or turns on tax law. A tax advisor may be the right person for some of these.

1. (SCN-0108, 0109, 0107) Which date inside a billing period decides? A tax starts or changes on a quarter's first day (Apr 1) and a bill's period runs Mar 15 – Apr 14; or an exemption certificate ends Oct 31 inside a period of Oct 15 – Nov 13. Is the whole bill taxed, none of it, or the taxed lines split by days? Neither of the Comptroller's rules we read (34 TAC §3.295, §3.334) says, and the certificate rule (§3.287) has nothing by billing period. We suggest the utility states its method when it enters the change, as you ruled for rate changes, with a tax advisor's check. OK?
2. (SCN-0109) The utility approves a published rate increase late, after bills went out at the old rate. It owes the higher tax anyway (our reading). Does it correct those bills, put the difference on the next bill, or absorb it? And if one of those bills is later voided and rebilled for another reason, we charge the new rate on the rebill. Right?
3. (SCN-0107) A certificate is verified in November, dated back to January. We don't change past bills by ourselves; an operator decides whether to credit the tax, and we record who decided. Our proposal for the default: credit the tax back to the certificate's valid-from date, since a refund is never held back. Is that right, and is there a limit on how far back? (The customer can also claim from the Comptroller, §3.295(h)(1).)
4. (SCN-0114) A part payment reaches a bill's tax lines but can't pay them all. Are they paid in stack order (state first), or in proportion? It decides how much each tax authority is shown as having collected.
5. (SCN-0111) A house rented to visitors by the week: we tax it as non-residential, because the visitors aren't tenants for over 29 days (34 TAC §3.295(a)(8)). Right?

*Figures*
6. Please check the dollar figures in `scenarios/tax.md`. Invented for the tests: Bluebonnet's own 1% city tax, older than Oct 1, 1979 and kept on homes; Bluebonnet County 0.5%; a crime-control district 0.25% (from Jan 2027, taxing homes too); a transit authority at 0.25% on part of the city, until Sep 30, 2027 (every local tax counts toward the 2% limit, transit included); the city's rate published at 1.25% from Oct 2027; Pecan Flat's city tax 1.5%, adopted in 1987 so it can't reach homes, and its county levying none. Real: the state's 6.25%. Two earlier scenarios changed: a large business outside the city now pays state and county tax (SCN-0055 c, $447.32), and a home's March 2027 bill now carries the district's $0.16 (SCN-0054 a, $66.99).
