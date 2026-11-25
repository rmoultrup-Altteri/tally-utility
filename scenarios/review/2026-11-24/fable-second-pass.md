# Second-pass review (Fable), tax scenarios: dc7209c → eaf2b67

Scope: the diff of `scenarios/tax.md`, `scenarios/cast.md`, `scenarios/billing-pipeline-and-charge-composition.md` and `application/kyle-brief-2026-11-24-scenario-batch-5.md`, read against the three first-round reviews, `sql/v5.4.2-30-tax-levies-and-taxability.sql`, AC-47 and `application/places-sources/texas.md`. Nothing in the repo was edited; no Docker, no database. Two statute pages were fetched from texas.public.law (Tax Code §321.102 and §321.3025) and came back as a small model's summary, not verbatim text; findings E1 and G1 lean on them and say so.

Totals: 3 errors, 7 gaps, 7 nits.

## What checked out

- **Arithmetic, every figure recomputed (four decimals, half-up per line).** All correct:
  - SCN-0104: $187.40; $11.71, $0.94, $1.87; $201.92. Penalty $18.74; $1.17, $0.09, $0.19; $20.19. The combined-rate note ($28.28 against $28.29) is right.
  - SCN-0105: $65.83, $65.99, $202.39. SCN-0106: $447.32 ($82.90 + $96.10 + $222.56 + $17.47 = $419.03).
  - SCN-0107: $444.10; $27.76, $2.22, $4.44; $478.52.
  - SCN-0108: $69.83, $66.18, $65.99, $65.18; $0.81; 17 of 31 days.
  - SCN-0109: $0.81, $2.34, $66.15, $202.86; shortfalls $0.16 and $0.47.
  - SCN-0110: $70.53, $1.40. SCN-0111: $488.11 ($28.31 + $6.80), $81.35 ($4.72 + $1.13). SCN-0112: $68.13, $68.04.
  - SCN-0114: Nov billed $37.90 / $3.04 / $1.87; Nov collected $26.19 / $2.10 / $0.00; Dec billed $1.17 / $0.09 / $0.19; Dec collected $12.88 / $1.03 / $2.06; $222.11 − $100.00 = $122.11; the $100.00 is $12.80 + $59.20 + $28.00.
  - **SCN-0115:** BB-13 $187.40 + $11.71 + $0.94 + $1.87 + $0.47 + $0.47 + $0.94 = $203.80; BB-10 $202.39; BB-14 $65.99; the $1.41 difference. Arithmetic right (the rates themselves are finding E1).
  - **SCN-0116:** base $12.80 + $59.20 + $107.00 − $3.00 = $176.00; $11.00, $0.88, $1.76, $0.44; with the $1.00 fee, $191.08. Taxing the fee: base $177.00 gives $11.06, $0.89, $1.77, $0.44, so +$0.06, +$0.01, +$0.01, +$0.00 = $0.08. Right. BB-10 is west of Main in March 2027, so state, county, city and crime-control district are the right four.
- **Dates and weekdays.** Dec 2 (Wed), Dec 3 (Thu), Dec 15 (Tue), Dec 16 (Wed), Nov 25 (Wed) 2026; Feb 15 (Mon), Mar 3 (Wed), Apr 1 (Thu), Oct 1 (Fri), Oct 5 (Tue), Nov 15 (Mon), Nov 20 (Sat) 2027. Received Mar 3 gives Apr 1; a request for more time on Mar 10 is within ten days and gives Jul 1.
- **Cross-file figures that agree.** SCN-0054 (a) $65.99 + $1.00 = $66.99 with SCN-0105 (b) and SCN-0108's $1.00 fee; SCN-0055 (c) $26.19, $2.10, $447.32 with SCN-0106 (b), SCN-0114 and the brief's question 10; cast PF-03/PF-04/PF-05, BB-03, BB-08, BB-11 to BB-15 and the Fremont row with the scenarios; the brief's rates (0.5%, 0.25%, 0.25%, 0.5%, 1.5% adopted 1987, 6.25%) with the cast.
- **First-round findings fixed correctly** (not re-raised): Opus B1, S1–S7, M1–M8; Fable S1–S11, M1–M9; Codex 1–6, 8, 9. The one partly dropped is Codex 7 (finding G7).
- **Database claims that the SQL supports.** A sales-tax row naming an extraterritorial area is refused (`tax_kinds.place_kinds` is state, county, municipality, transit_authority, special_purpose_district; line 197, 324). More than four decimals, a citation with no letter or digit, another utility's row, a place not in force: refused (`tax_levy_insert_check`). A row with no recording user is accepted (`created_by uuid`, nullable, line 295). An exemption with no service is refused (constraint, line 620); a line with no service type is refused (`should_charge_tax`, line 642). A place closed from under a row is refused at commit unless a same-code successor covers it (lines 404–440). The gaps report lists only places with an open tax-axis membership (lines 509–522), so BB-15's missed district is indeed not reported. Nothing checks "reaches residential" or stack order.

---

## Errors

### E1. A transit authority's tax is not outside the 2% local limit: SCN-0115's combined rate (2.5% local, 8.75% in all) cannot exist in Texas
- **Where:** `scenarios/tax.md` line 323 (Rule: "transit authorities are outside the 2% reduction"), line 326 ("the local total east of Main is 2.0% inside the limit, plus the transit authority's 0.5% outside it"); `scenarios/cast.md` line 73 ("outside the 2% limit"). Root: `application/places-sources/texas.md` line 199 ("transit authorities are excluded from that reduction").
- **What is wrong.** §321.102(h) says a transit authority is not a "local governmental entity" for (e) and (f). That means the transit authority's rate is not the one that gets cut when a city's tax pushes the total over 2%; it does not take the transit tax out of the total. The 2% ceiling counts every local sales tax at a location, transit included (the Comptroller's standing statement: cities, counties, special purpose districts and transit authorities together may add up to 2%, for a maximum of 8.25%; Houston and Dallas sit at exactly 1% city + 1% transit). East of Main the scenario has 1% + 0.5% + 0.25% + 0.25% + 0.5% = 2.5%.
- **Confidence.** High on the 8.25% ceiling. The reading of (h) is from a summarized fetch of the statute, so re-read (e)–(h) verbatim before rewriting.
- **Fix.** Keep both places but make the east side total 2.0% including transit. One way that leaves every other scenario untouched: hospital district 0.125% and transit authority 0.125%. Then BB-13: hospital 0.125% × $187.40 = 0.2343 → **$0.23**; transit 0.2343 → **$0.23**; total **$202.85**; a core keying districts to the city overbills BB-10 by **$0.46**. Change the Rule's parenthesis to "(a transit authority's rate is not the one reduced, but it counts toward the 2%)", the cast row, texas.md line 199 and the brief's question 10 (line 37).

### E2. SCN-0109's city rate rise to 1.25% breaks the 2% limit east of Main once SCN-0115's places exist
- **Where:** `scenarios/tax.md` line 171 ("with the county's 0.5% and the district's 0.25%, the local total is 2%"), against line 326 and `cast.md` line 73 (the hospital district and transit authority have no dates, so they are in force in October 2027).
- **What is wrong.** East of Main the total is already 2.0% without transit at a 1% city rate (line 326). At 1.25% it is 2.25% (2.75% with transit as written; 2.25% under E1's fix). The doc's own rule (line 73 of tax.md, §321.102(e)–(h)) says a rate there would be automatically reduced, and (g) bars a city from raising its rate if the total would pass 2% anywhere in the city. So the Comptroller could not publish 1.25% for the whole city, and the hospital district's row would differ east of Main.
- **Fix.** Either give the hospital district and the transit authority an end date before Oct 1, 2027 in the cast (invented) and say so in SCN-0109's Given, or shrink the rates so the east side has 0.25% of headroom (for example crime-control district, hospital district and transit authority at 0.125% each: west 1.625%, east 1.875%, and a city rise of 0.125% to 1.125%; that changes the district figures in SCN-0105, 0108, 0109, 0115, 0116 and SCN-0054). The first is the small change.

### E3. The brief's opening points at the wrong question
- **Where:** `application/kyle-brief-2026-11-24-scenario-batch-5.md` line 17: "Neither of the Comptroller's rules we read (34 TAC §3.295 …, §3.334 …) answers questions 1 or 3".
- **What is wrong.** Question 3 (city tax charged before it was in force) is answered on the law by Tax Code §321.3025, which the question itself cites; tax.md line 158 says so. The two things tax.md says the rules do not answer are question 1 (line 159: neither §3.334 nor §3.295) and question 5 (line 129: the certificate rule, §3.287, has no rule by period).
- **Fix.** "Neither rule answers question 1, and the certificate rule (34 TAC §3.287) says nothing about a billing period for question 5, which is why they come to you. On question 3 the statute gives the legal position; the question is what the utility does."

---

## Gaps

### G1. SCN-0108 (e): §321.3025 covers the city's tax only; the $0.16 district tax is carried along with it
- **Where:** `scenarios/tax.md` line 158 ("so the $0.81 is not owed back by law unless the customer claims it"); brief line 22.
- **What is wrong.** The section as quoted speaks of taxes "imposed by the municipality" (the fetched summary confirms it names no district). Of the $0.81, $0.65 is city tax and $0.16 is the crime-control district's. Nothing read says the district's early tax is treated as the district's revenue.
- **Fix.** "so the $0.65 of city tax is not owed back by law unless the customer claims it; the $0.16 of district tax has no such rule in what we read (to check)". The brief's question 3 says "city tax" only, which is accurate for the statute but hides that the credit proposed is $0.81.

### G2. SCN-0109 (e): the stated consequence is not what the database does in this case
- **Where:** `scenarios/tax.md` line 192: "the answer could settle on both rows, or refuse for that instant for good."
- **What the SQL does.** `tax_levy_as_of` never answers two rows of one tax: more than one raises 21000 (line 472). "A row beside its replacement" in limit L7 (b) and AC-47 is about places (two stacking districts), and both of L7 (b)'s outcomes need two writers, the successor's begun before the predecessor's close. In (e) as given there is one approval (close the 1% row and add the 1.25% row). A run that chose its instant after that approval began and read before it committed sees 1%; every read at the same instant after the commit answers 1.25% (L7 (a): two reads at one instant silently differ).
- **Fix.** "Choosing first and waiting after is not enough: a bill computed before the approval commits charges 1%, and every later read at that same instant answers 1.25%, so the bill cannot be reproduced (it still records the row it used). With two separate writers the read can instead refuse for that instant for good."

### G3. SCN-0114: December's "billed" column assumes no December bills, and the Given does not say so
- **Where:** `scenarios/tax.md` lines 299 and 307–311.
- **What is wrong.** "They are the only taxed bills" is said of the November bills. BB-10 and BB-08 would get December bills on Dec 16, whose tax is billed in December; the report is read on Jan 4. The table's December billed ($1.17, $0.09, $0.19) is the penalty's tax alone.
- **Fix.** Add to the Given: "No December bill is issued to BB-10, BB-08 or BB-03 in this scenario (**invented**)", or add their December tax to the column.

### G4. Where BB-03 sits relative to Main Street, and from when the hospital district and transit authority exist, is not stated
- **Where:** `scenarios/cast.md` line 73 (rows 5 and 6 carry no start date; row 4 does) and line 107 (BB-03 "inside the city"); `scenarios/tax.md` lines 106, 120–122, 314.
- **What is wrong.** SCN-0107 (a) shows three $0.00 lines for the courthouse and SCN-0114 a base "per jurisdiction". If the courthouse is east of Main it has five. A test cannot tell.
- **Fix.** Cast: "BB-03 … inside the city, west of Main Street"; give rows 5 and 6 a start date (and, per E2, perhaps an end date).

### G5. The brief's question 9 drops half of SCN-0114's Open and answers it instead; one "To confirm" is missing
- **Where:** brief line 34 against `scenarios/tax.md` lines 314 and 316.
- **What is wrong.** tax.md asks Kyle and a tax advisor "does the utility report tax when billed or when collected". The brief does not ask it; it says "Which one the utility reports on is its own call", which tax.md nowhere says. And the "to confirm" on line 314 (the liability also shows the exempt base, which is not in Kyle's answer 4) is in no question, though the brief's header says it covers the "To confirm" notes.
- **Fix.** Question 9: "… And does the utility report tax when it bills it or when it collects it? If collected, is that the month the payment posts or the month of the bill it paid? We keep both figures either way." Add: "We also show, per jurisdiction, the exempt sales (the courthouse's $444.10) beside the tax, for the return. OK?"

### G6. SCN-0116 cites Utilities Code §121.211(g) as what keeps the pipeline safety fee out of the tax base; the repo's source limits (g) to investor-owned and cooperative systems
- **Where:** `scenarios/tax.md` line 351. `application/places-sources/texas.md` line 214: "Per (g), for investor-owned and cooperative systems the surcharge is excluded … 'not subject to a sales and use tax'". Bluebonnet is city-owned, and SCN-0054 (line 94 of the billing-pipeline file) rests the same fact on "Bluebonnet doesn't flag the fee taxable (**invented**)". `cast.md` §2 does not mention §121.211.
- **Fix.** "Bluebonnet does not flag the fee taxable (**invented**, SCN-0054); §121.211(g) says so in terms only for investor-owned and cooperative systems (to check for a city system)."

### G7. Codex 7 was applied to SCN-0109 only; SCN-0110 still asserts a read at a past instant with no precondition
- **Where:** `scenarios/tax.md` lines 201–211. SCN-0110 cites AC-47 in its sources and (a) says "Read as known at its own run's instant, the premise is still inside".
- **Fix.** Add to the Given: "The October and November runs each chose their instant when no earlier transaction was open (AC-47)", and in (a): "The bill's own record is what it used; the read at its instant agrees only because of that".

---

## Nits

- **N1. Brief line 22, "a quarter early".** In SCN-0108 (e) the tax was charged from Feb 15 against Apr 1: one bill (March), about six weeks. Say "before the tax was in force there (one bill)".
- **N2. Brief wording a lawyer reading cold would stop at.** Line 33: "A forfeited discount" does not say it is the late penalty; write "The 10% late penalty (a forfeited prompt-payment discount, which you ruled is 'taxed like the gas')". Line 29: "a figure on each bill" does not say a figure of what; write "or a share of business use stated for each bill".
- **N3. Brief question 10 (line 37) lists one changed earlier scenario but there are two.** SCN-0054 (a) went from $66.83 to $66.99 (the district's $0.16). Also unlisted among the invented facts: Bluebonnet's own city tax predating Oct 1, 1979 and kept on residential gas (the reason homes are taxed at all), and Pecan Flat's county levying nothing.
- **N4. SCN-0113 (e), tax.md line 286: "Accepted"** holds only once the platform has loaded the City of Pecan Flat as a place; today it is refused for the same reason as (a) (limit L3). Add "once that city is loaded". The same applies to (b): the place check runs before the decimals check (SQL lines 352–361), so a test needs a loaded city to see the decimals refusal.
- **N5. `cast.md` line 63 (late penalty) still says "so city sales tax applies inside the city".** SCN-0104 (b) now puts state and county tax on a business's penalty, and from Jan 1, 2027 the district's tax would follow too. Write "it carries every tax the gas on that bill carries (`tax.md` SCN-0104 (b); to confirm with Kyle)".
- **N6. Outside the diff, for consistency:** `scenarios/periods-and-aging.md` line 194 has BB-01 owing $65.83 on a bill dated Jan 15, 2027. That bill's period straddles the district's Jan 1 start, which is the brief's question 1; the figure is marked invented, so a note is enough.
- **N7. SCN-0114, tax.md line 313.** The sentence states as fact that the Dec 3 payment pays the bill's first three lines, then says in brackets that bill-before-penalty is the cash family's order. The table is safe either way (both are December), but the sentence should read "taking the bill before the penalty (the cash family's order)".
