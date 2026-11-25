# Review of `scenarios/tax.md` (SCN-0104 to 0114), commit dc7209c — Fable

Scope: `scenarios/tax.md`, the cast edits, the SCN-0055 (c) note. Checked against `scenarios/README.md`, `application/places-sources/texas.md` §3 and §5, `tax-inventory.md`, `tax-design.md`, `tax-triage.md`, Kyle's rulings of 10-14, 10-15 (K-05), 11-03 and 11-05 in GBM, `sql/v5.4.2-30-tax-levies-and-taxability.sql`, the live `tally` database (read-only: catalog queries and function bodies; nothing written, so no refusal was executed, each was read from the trigger or check that makes it), AC-47, and the other scenario files.

No blockers. Eleven should-fix, nine minor, then missing cases.

## What checked out

- **Arithmetic.** Every figure recomputed with decimal half-up: all tax lines, all totals, the penalty and its three taxes ($18.74; $1.17, $0.19, $0.09; $20.19), SCN-0106 ($26.19, $2.10, $447.32), SCN-0107 ($444.10; $27.76, $4.44, $2.22; $478.52), SCN-0109 ($0.81, $2.34, $66.15, $202.86, the $0.16 and $0.47 shortfalls), SCN-0110 ($0.70, $70.53, $1.40), SCN-0111 ($75.50, $481.31, $4.72, $80.22), SCN-0112 ($1.89, $3.24, $68.13, $68.04), SCN-0114's billed sums ($37.90, $3.04). No arithmetic error.
- **Weekdays and dates.** All sixteen stated weekdays are right (Oct 15 and Oct 30, 2026; Nov 16, 2026; Dec 3, 2026; Nov 3, 2026; Feb 15, Mar 3, Apr 1, Oct 1, Oct 5, Nov 15, Nov 20, 2027). The annexation quarter (received Mar 3, tax from Apr 1) matches §321.102(c). 17 of 31 days in SCN-0108's Open is right.
- **Law.** §151.317(a), (c), (e); §321.105; §321.201(a); §321.203(f); §321.1055(c), (d); §321.102(c); 34 TAC §3.334(k)(8), (l)(1)(A); Local Gov't Code §43.130(c), §42.902 are each used as `texas.md` quotes them. §321.3025 is correctly flagged as not in our sources.
- **Rulings.** Nothing contradicts Kyle 10-14 (answers 1, 2, 4, 5), 11-03 answer 4, or 11-05 answers 3a, 3b, 16, 20.
- **Schema claims that hold** (read from -30 and the live triggers): a tax row is never edited, a change is a close and a new row (SCN-0109 d); a backdated close and a backdated new row are accepted (no close floor on this table), so (b) and (c) are possible; a bill reading at its run's instant on Nov 15 sees the 1% row open and not the row recorded Nov 20; the gaps report has both halves (rate differs; a place a premise is in publishes a rate and the utility has no row); an exemption with no service is refused; a line with no service type is refused; an unverified certificate does not count; SCN-0112 (c) and (d); SCN-0113 (a), (b), (c), (e), (f); a membership voided after an instant still counts at that instant (SCN-0110 a); nothing compares the two axes (SCN-0110's last bullet); nothing checks stack order against tax-on-tax (SCN-0112 Open); nothing checks "reaches residential" against the kind of place or the place's published fact (SCN-0113 Open).

## Should-fix

### S1. SCN-0114: the October liability leaves out the tax on BB-10's penalty, and counts a November payment as October's collection
- BB-10 pays on Tue Nov 3, after the Oct 30 due date, so SCN-0104 (b)'s penalty posted (the day after the due date, Oct 31, as the Dec 1 / Dec 2 pattern in `cancel-rebill.md`), with its own tax of $1.17 state, $0.19 city, $0.09 county. That is tax billed in October. The table shows only the bill's tax.
- The $100.00 arrives Nov 3. Whatever share of it is tax is collected in November, yet the October row shows "BB-10's share".
- Fix: either move BB-10's payment inside October and before Oct 30 (no penalty), or keep it and (i) add the penalty's tax to tax billed (state $39.07, city $2.06, county $3.13), (ii) say whether "collected" is counted in the period the money arrived or the period of the bill it paid, and show October's collected from BB-10 as $0.00 if it is by arrival. That last choice is a real question (Kyle, with the money stream).

### S2. SCN-0114: the Open on which lines a part payment pays is already ruled
- Kyle 10-15, K-05: "Within-bill allocation order is jurisdiction rule data … The tenant confirms the within-bill order from their own tariff at setup." `cash.md` line 12 already uses it: fixed charge, then usage, then riders, then taxes, then fees (invented).
- Under that order BB-10's $100.00 pays the $12.80 customer charge, the $59.20 distribution and $28.00 of commodity: no tax is collected from it. The table can state a figure.
- Fix: give Bluebonnet's within-bill order in the Given (the same invented order as `cash.md`), put the figures in, and narrow the Open to what K-05 leaves: when a payment reaches the tax lines and cannot pay them all, are they paid in stack order or in proportion?

### S3. SCN-0108 (b) and (e): the March 2027 bill omits the $1.00 pipeline safety fee
- The cast bills the fee on the March bill; SCN-0054 (a) shows BB-01's March 2027 bill as $65.83 + $1.00. SCN-0108 (b) is BB-11's March 2027 bill and totals $65.18.
- Fix: $66.18 for (b) (fee outside the tax base, so (e)'s wrongly charged tax stays $0.65 and $0.16), or say in the Given that the fee is left out. Keeping it is better: it is the family's only bill where the tax base is smaller than the bill (see missing case 3).

### S4. SCN-0110: the premise was wrongly placed from Jan 1, 2026, but only October and November are corrected
- BB-12 was set up on Jan 1, 2026 with the wrong city membership. Every bill since carried the 1% city tax, not two. "$1.40 in all" is wrong unless service began in the autumn.
- Fix: say BB-12 moved in for the Sep 15 period (so only two bills exist), or correct every bill from the first and restate the total.

### S5. SCN-0105, 0108, 0109: the premise's membership in the crime-control district is never stated, and the schema does not derive it from "citywide"
- A district is its own place; a premise is in it only by its own tax-axis membership (districts stack; nothing links a district's members to its city's). SCN-0104 lists BB-10 as in the state, the county and the city. Read literally, SCN-0105 (b), (c) and SCN-0109 bill no district tax.
- Fix: add to the Given that BB-01's and BB-10's premises are recorded in the district on the tax axis from Jan 1, 2027, with the district's boundary notice as evidence. In SCN-0108 (e) say whether the clerk also recorded the district from Feb 15 (the $0.16 depends on it).
- This also sharpens SCN-0108's second Open: today a citywide district "grows with the city" only if someone records each premise. A premise missed pays no district tax and nothing reports it (the gaps report lists only places a premise is in). That is worth its own case, for the rates stream.

### S6. SCN-0111 and cast §1: "Pecan Flat levies no local sales tax" is not in the cast
- The cast row says local sales tax **on residential gas** is not adopted. That is the city's §321.105 choice; it says nothing about the city's ordinary sales tax, which a café's gas would carry. The new cast row ("County sales tax: none … so a non-residential bill carries the state's 6.25% only") assumes it. SCN-0111's source line quotes the cast as "no local sales tax adopted", which it does not say.
- Fix: add a cast row, "City sales tax: none (invented)", or give Pecan Flat a city rate and put a city line on PF-03's and PF-04's bills. The second is the more realistic small Texas town and tests "city tax on business gas where the city does not tax homes", which no scenario covers.

### S7. SCN-0111: "the premise's use is recorded with its dates" is not built, and what decides "residential" is not settled in the schema
- The premise has one current use field with no history. `tax-inventory.md` point 16 lists three candidates (the customer's type, the schedule's customer type, the premise's use) and triage 16 says only "rate class and premise use". There is no value for "rented by the week".
- (a)–(c) cannot be asserted until a test knows what is recorded for PF-01, PF-03 and PF-04. The file's opening "Not built" list omits this.
- Fix: add it to "Not built" (rates stream: a dated premise use, and which field wins when the schedule and the use disagree); state in the Given what is recorded for each premise; move the last bullet's claim to an Open (rates).

### S8. SCN-0113 (d): ambiguous, and one reading is accepted, not refused
- "A row for Pecan Flat's city, signed in as Bluebonnet." If it means a row belonging to the utility Pecan Flat, it is refused, as stated. If it means Bluebonnet's own row naming the City of Pecan Flat as the place, it is accepted: nothing checks that the utility has a premise there (it never bills, and the gaps report does not list it).
- Fix: word (d) as "a row in Pecan Flat's name"; add the accepted variant with its consequence.

### S9. SCN-0107: the Open is partly answered by the exemption invariant, and the Rule's "only over its dates" has no case
- CI-046 already says a backdated certificate is surfaced for the operator to decide (credit the past bills, or accept the gap), never applied silently to past bills. So the answer is not one platform rule; it is an operator decision that is recorded. Note also that a later rebill of one of those bills for any other reason reads the exemption as known then and comes out untaxed.
- Fix: state the CI-046 behaviour in Then (surfaced; the choice and who made it recorded) and narrow the Open to what remains for Kyle: is there a default, and how far back may the credit reach.
- Add case (e): the certificate expired Sep 30, 2026; the October bill is taxed in full with no manual switch. And the question it raises: a bill period Sep 15 – Oct 14 straddling the expiry (CI-046 says "valid for the period"; which date decides, or is the base split?).

### S10. SCN-0108 (e) and SCN-0110: "Kyle 11-04" does not exist
- There is no Kyle ruling of 2026-11-04 in GBM. The refund rule is Kyle 11-03, answer 8 ("Refunds go back as far as the records show … A missing rule never holds back a refund"), with 11-05 answer 12 for months before go-live.
- Fix: cite 11-03 answer 8 in both places. "Unlimited" should read "as far as the records show".

### S11. SCN-0109 (b): "recorded with the approving operator" is not required by the database
- The approver is taken from the session's user setting; the column is nullable and no check refuses a row with none. A row written with no user set bills with no approver, against Kyle 10-14 answer 1 ("no rate change goes live without operator approval").
- Fix: add an Open (rates): refuse a tax row with no recording user. Until then (b)'s "with the approving operator" is the application's promise, and should say so.

## Minor

- **M1. SCN-0104, the note on one combined rate.** It says the combined figure "would differ … ($14.52 here, but not in general)": the two are equal here, so the sentence contradicts itself and the example cannot tell the two methods apart. The only bill in the family where they differ is SCN-0106 (b): 6.75% × $419.03 = $28.28 against $26.19 + $2.10 = $28.29. Point to it, or change BB-10's usage. Also: the tables list the taxes in three different orders and no scenario states Bluebonnet's stack order, though CI-045's "in its order" is under test; give each row its position in the cast.
- **M2. SCN-0110 (c): December issue date.** "Issued Dec 15"; `cancel-rebill.md`, `cash.md` and `date-tracking-and-immutability.md` all issue Bluebonnet's December 2026 bills on Wed Dec 16. Use Dec 16.
- **M3. SCN-0108: usage not stated.** $69.83 and $65.18 assume 6.0 Mcf each month; say so.
- **M4. Cast customers.** BB-03's row does not say it is inside the city or holds a verified gas exemption from Jan 1, 2026 (the cast rule: add the fact there first). PF-04 and PF-05 are not in the table while PF-03 is.
- **M5. SCN-0055 (c).** The table still ends in a bold total of $419.03 with the correction beneath it; a test built from the table asserts the wrong bill. Put the two tax lines and $447.32 in the table, and add "changed by `tax.md` SCN-0106" to its Status line.
- **M6. Statements given more authority than their sources.** (i) SCN-0105: "the limit is applied by the Comptroller in the rate it publishes": `texas.md` says only that a local rate "is automatically reduced". (ii) §151.051's 6.25% is listed in `texas.md` under "Could not verify". (iii) "No line, not a $0.00 line" for a tax that does not reach residential gas is this stream's reading; neither Kyle 11-03 answer 4 nor R-13 says it. (iv) SCN-0114's "exempt base beside them" is not in Kyle 10-14 answer 4 (billed, collected, filing reference). Mark each as a reading or a check.
- **M7. SCN-0112: "a row may not name itself".** The check is by kind of tax: a row may not name its own kind. So a sales tax charged on another place's sales tax cannot be recorded at all. Say "its own kind", and note the limit for the rates stream.
- **M8. SCN-0110 (b), SCN-0108 (e).** "Citing the map": the evidence kinds are the utility's record, an ordinance, the tax authority's notice, a commission order, a census designation and an address lookup; say which. "Refunded" assumes the bills were paid; say so, or say "credited".
- **M9. Smaller.** The opening invariant list omits CI-047 (a premise's tax places from ground truth, dated, overrides audited), which SCN-0108 (e) and SCN-0110 test. In SCN-0109 the totals cannot tell "city 1.25%, district missed" from "city 1%, district 0.25%" (both $65.99 and $202.39); a test must assert lines. SCN-0113's rule names "a kind of place that levies that tax" but no case enters a wrong kind.

## Opens: named for the right person?

- Right as written: SCN-0104 (Kyle), 0105 (rates), 0109 (Kyle), 0111 d (Kyle), 0112 (rates), 0113 (rates), 0114's billed-or-collected question (Kyle and a tax advisor).
- SCN-0108, the bill straddling Apr 1: this is what the tax law requires, not a utility's choice, so the recommendation "the utility states its method" should wait on a citation check. The Comptroller's rule on natural gas and electricity, 34 TAC §3.295, is not in our sources and was not read for this review; it is the first place to look, and also for SCN-0111 (c) and (d).
- SCN-0107: narrowed by CI-046 (S9). SCN-0114's first Open: ruled by K-05 (S2).

## Missing cases

1. **A premise with no city status recorded on the tax axis.** "In no city" is recorded positively (the extraterritorial or unincorporated area). A premise with neither that nor a city, or with no county: is the bill refused, or taxed by the state alone? Nothing covers it; an Open for Ryan or the rates stream.
2. **A district premise missed** (S5).
3. **A line outside the tax base on a taxed bill** (Kyle 10-14 answer 5: a taxable customer never makes a non-taxable line taxable). The March pipeline safety fee on BB-10's bill would do it.
4. **Exemption expiry and the straddling period** (S9).
5. **A rebill for another reason after a tax change.** After SCN-0109 (c), BB-10's Nov 15 bill is voided for a misread and rebilled in December: read as known now, the rebill charges 1.25%; read at the original instant, 1%. Which? It decides part of SCN-0109's Open.
6. **Disannexation** (tax stops the quarter after the Comptroller's receipt, rates change on the ordinance date): mentioned in SCN-0110, never worked.
7. **A transit authority** (a kind of place on the tax axis only; outside the 2% reduction): no scenario.
8. **Schedule and use disagree** (a weekly rental on Bluebonnet's R-U): which decides "residential" (S7).
9. **A gas cost credit on a taxed bill** (a negative line in the base).
10. **City tax on business gas in a city that does not tax homes** (S6).

## Not part of the review

Two `crystaldba/postgres-mcp` containers were running when the database was queried (the leak the project notes warn about). Left alone.
