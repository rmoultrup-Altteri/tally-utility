# Second-pass review: tax scenarios after round 5 (dc7209c..eaf2b67) — Opus

Scope: the diff to `scenarios/tax.md`, `scenarios/cast.md`, `scenarios/billing-pipeline-and-charge-composition.md` and the new `application/kyle-brief-2026-11-24-scenario-batch-5.md`, checked against the three first-round reviews, `sql/v5.4.2-30-tax-levies-and-taxability.sql`, `application/places-sources/texas.md`, and the statute and rule texts read for this review (Tax Code §321.101, §321.102 at texas.public.law; 34 TAC §3.295 at Cornell LII). Line numbers are `tax.md` unless named otherwise.

Totals: 2 errors, 3 gaps, 6 nits.

## First-round findings: status

Applied correctly and completely:
- **Opus:** B1, S1–S7, M1–M6, M8 and M9.
- **Fable:** S1–S11 and M1–M9, plus missing cases 1–10 (written, or listed under "Not yet written").
- **Codex:** 1–6, 8 and 9.

I re-checked every changed figure and found none wrong. SCN-0054 (a) is $66.99. SCN-0055 (c) is $447.32, now in its table. SCN-0108's figures are $66.18, $65.99, $65.18 for (f), and $0.81. SCN-0110's $1.40 now comes from a Sep 15 start. SCN-0111 is $488.11 and $81.35. SCN-0114's two months of figures are right, and the $222.11 payments are right. All weekdays are right: Wed Nov 25, Wed Dec 2, Thu Dec 3, Tue Dec 15, Wed Dec 16, and Wed Mar 3 → Thu Apr 1. The extra time the Comptroller asked for on Mar 10 falls within 10 days of receipt. Under §321.102(d) that moves the tax to Jul 1, which is right.

Partly applied (no new error):
- **Opus M7** (whether SC-U changed on Oct 1) is moot now. No tax scenario uses a bill that straddles Oct 1 for SC-U. Not raised.
- **Codex 7** asked the scenario to tell apart the error a run can retry from the one that refuses a fixed instant for good (40001 against 21000). SCN-0109 (e) states the behaviour ("refuse for that instant for good") but names no error. That is adequate for a scenario. Not raised.
- **Codex 2** asked that the scenario say Pecan Flat's premises belong to no transit authority or district. That was not done. See N4.

Dropped: none.

## Findings

### E1 (error). SCN-0115, cast §2 row 6: the transit authority's tax is wrongly placed outside the 2% local limit

- **Where:** `tax.md` line 326 ("the local total east of Main is 2.0% inside the limit, plus the transit authority's 0.5% outside it"); line 323 (the Rule's source note); `cast.md` line 73 (row 6, "outside the 2% limit").
- **What is wrong:** §321.102(h) says only that "a transit authority is not a local governmental entity for the purposes of Subsections (e) and (f)". So a transit authority's tax is never the one *automatically reduced*, and the Comptroller withholds nothing on its account. It still counts toward the limit:
  - §321.101(f): a city may not adopt or raise its tax if "the combined rate of all sales and use taxes imposed by the municipality and other political subdivisions of this state having territory in the municipality would exceed two percent at any location in the municipality". A transit authority is such a subdivision.
  - §321.102(g) says the same.
  - `texas.md` line 327 says so too ("all applicable levels stack, subject to the 2% local cap").
- **The consequence:** BB-13's local total is 2.5%, and its combined rate is 8.75%. Texas's ceiling is 6.25% + 2% = 8.25%. A cap check built from this scenario would accept a stack the law forbids.
- **Fix:** keep the local stack at 2% or less east of Main. One way: drop the hospital district and set the transit authority at 0.25%. Then:
  - BB-13's transit line is 0.25% × $187.40 = 0.4685 → $0.47, and the total is **$202.86**.
  - Line 344 becomes "$0.47 too much".
  - Rewrite cast row 6 and line 326 as "inside the 2% limit; a transit authority's rate is never the one reduced (§321.102(h))".
  - Update the Kyle brief's question 10 to match.
  - If both overlapping places are wanted, give two of the rates lower values so the sum stays at 2%.

### E2 (error). SCN-0109: a city rate of 1.25% breaks the 2% limit east of Main Street

- **Where:** line 171 ("with the county's 0.5% and the district's 0.25%, the local total is 2%").
- **What is wrong:** that sum ignores the hospital district (0.25%) and the transit authority (0.5%). Both are now in the cast east of Main, with no end date, so both are in force in October 2027. There the local total would be 2.25%, or 2.75% with transit. Under §321.101(f) the city could not raise its rate at all, because the combined rate "would exceed two percent at any location in the municipality". The published 1.25% is therefore unlawful.
- **Fix:** either:
  - give the hospital district and transit authority dates that end before Oct 1, 2027; or
  - make the published change one that fits. For example, the crime-control district's rate is reduced. Or the city goes to 1.25% only after the east-of-Main places are gone.

  Whatever E1's fix leaves east of Main, the line must state the local total at both locations.

### G1 (gap). SCN-0114: the December billed column leaves out December's own bills

- **Where:** lines 299–311. The Given makes the November bills "the only taxed bills" in the scenario. December's billed column holds only BB-10's penalty tax ($1.17 / $0.09 / $0.19).
- **What is wrong:** BB-10's and BB-08's December 2026 bills (issued Wed Dec 16) would carry tax and belong in December's billed figures. A test built from the table would assert a December liability that leaves out a month's bills.
- **Fix:** extend the invented assumption: "December's own bills are left out of the liability for this scenario (**invented**)". Or add them. If BB-10's December bill matches its November figures, December billed becomes state $12.88, county $1.03, city $2.06.

### G2 (gap). SCN-0116: the cited source for leaving the fee outside the tax base is not in any source, and the law that does say it is not cited

- **Where:** line 351, "16 TAC §8.201 and Utilities Code §121.211(g) (the pipeline safety fee is outside the tax bases; `cast.md` §2)".
- **What is wrong:**
  - §121.211(g) appears nowhere in the repo's sources.
  - `cast.md` §2 does not say the fee is outside the tax base.
  - SCN-0054 has it only as "Bluebonnet doesn't flag the fee taxable (**invented**)".
  - The rule that settles it is 34 TAC §3.295(j): "Sales or use tax is not due on any surcharge for pipeline safety fees". That is the rule this stream read on 2026-11-24.
- **Fix:** cite 34 TAC §3.295(j). In SCN-0054 replace "(**invented**)" with that citation. Optionally add an Open for the rates stream: today the fee stays out of the base only because the utility does not flag it taxable. The schema's existing setting that keeps a fee out of every tax base (`excluded_from_tax_bases`, -07) could be required for it.

### G3 (gap). The undated hospital district and transit authority reach bills not written with them in mind

- **Where:** `cast.md` rows 5–6 give no start date, so both are in force on every Bluebonnet bill, including the 2026 ones.
- **SCN-0107 (lines 106 and 120–123):** BB-03, the courthouse, is "inside the city", but which side of Main Street is not stated. If it is east, the exempt bill needs two more $0.00 lines (hospital district and transit authority), each with base $444.10. Then (b), (c) and (e) total $478.52 + $1.11 + $2.22 = **$481.85**.
- **SCN-0114:** BB-03's exempt base "per jurisdiction" depends on the same fact.
- **Fix:** give both places a start date (for example Jan 1, 2027). Or record BB-03 as west of Main in the cast and in SCN-0107's Given.

### N1 (nit). SCN-0108 (f): the district's membership date is not moved with the city's

Line 141 records BB-11 in the crime-control district "from Apr 1". Case (f) moves only the city's tax date to Jul 1, but its table row shows no district tax. That row is right only if the district's membership also moves to Jul 1. Add this to (f): "the district membership is recorded from Jul 1 too".

### N2 (nit). Kyle brief, question 9: settles in passing what `tax.md` asks as an open question

The brief adds "(Which one the utility reports on is its own call; we keep both.)". SCN-0114's last Open (line 316) asks Kyle and a tax advisor whether the utility reports tax when billed or when collected. Either:
- reword the brief: "Does the utility report on billed or collected tax, or is that its own choice? We keep both"; or
- change `tax.md` to say it is the utility's choice.

### N3 (nit). Kyle brief: one item to confirm left out, and question 10 is incomplete

- SCN-0114 line 314 marks "the liability shows the exempt base too … to confirm". No brief question covers it. Add it to question 9, or say it goes to the tax advisor.
- Question 10's list of invented figures leaves out two:
  - the City of Bluebonnet's 1% tax on homes, which predates Oct 1, 1979 and was kept (invented);
  - the published 1.25% (SCN-0109).

### N4 (nit). SCN-0111: the Pecan Flat premises' tax places are never stated

The common facts (line 9) say a premise is in a place only by its own recorded membership. SCN-0104 and 0115 state each premise's places; SCN-0111 does not. So nothing puts PF-03 or PF-04 in the City of Pecan Flat, yet both bills carry city tax. Add: "each premise is recorded on the tax axis in the State of Texas and the City of Pecan Flat, and in no district or transit authority". That also finishes Codex 2.

### N5 (nit). `periods-and-aging.md` line 194: BB-01's Jan 15, 2027 bill now straddles the district's start

The cast now starts the crime-control district on Jan 1, 2027. So BB-01's "$65.83 on a bill dated Jan 15, 2027" covers a period that straddles a tax start. That is SCN-0108's open question about the April bill: the whole bill taxed, none of it, or split by days. If the bill were taxed whole it would be $65.99. Since the figure is invented for aging, either:
- add "(**invented**; district tax left out)"; or
- move the date to Dec 15, 2026.

### N6 (nit). The cast's BB-10 row lists only three taxes

`cast.md` line 108 says BB-10 is "taxed by the state, city and county". From Jan 1, 2027 it is also in the crime-control district (SCN-0105, 0115, 0116). Add "and from Jan 1, 2027 the crime-control district; west of Main Street".

## Database claims spot-checked against v5.4.2-30 (all supported)

- **SCN-0113:**
  - (a), not in force over the row's dates: `v_cover @> v_range`.
  - (b), more than four decimals: `round(v_rate, 4)`.
  - (c), a citation needs a letter or a digit: the citation pattern `[A-Za-z0-9]`.
  - (d), another utility's row: "a utility writes its own levies only".
  - (e) is accepted: nothing ties a row's place to the utility's premises.
  - (f), the extraterritorial area: `tax_kinds.place_kinds` for sales tax lists state, county, municipality, transit_authority and special_purpose_district only.
  - (g) is accepted: nothing checks `reaches_residential`.
  - (h): `z_check_place_levy_coverage`.
- **SCN-0112** (c) and (d): `computed_on` may not name its own kind, nor an unknown kind.
- **SCN-0109:**
  - (b): `created_by` can be empty (nullable), so a row with no user is not refused.
  - (d): a row is never edited.
  - (e): `premise_places_as_of` refuses an instant with more than one answer (21000).
  - The gaps report has both halves: a rate that differs, and a published place with no row.
- **SCN-0105 (d):** the gaps report reads only a premise's recorded tax-axis memberships, or its state, so a missed district is not reported.
- **SCN-0107 (d):** the `service_types` check refuses an exemption that names no service, and `should_charge_tax` raises on a line with no service type.

## SCN-0115 and SCN-0116 arithmetic

Every figure in both is right as written:
- **SCN-0115:** BB-13 $203.80, BB-10 $202.39, BB-14 $65.99, and the $1.41 difference.
- **SCN-0116:** base $176.00; taxes $11.00, $0.88, $1.76 and $0.44; total $191.08. Taxing the fee would add $0.08 ($11.0625 → $11.06, $0.885 → $0.89, $1.77, $0.4425 → $0.44).

Each tax reaches the right premise under the doc's residential rules. Only SCN-0115's 2% limit is wrong (E1).
