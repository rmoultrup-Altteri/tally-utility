# Review of 7ed33ad: transit authority at 0.25%, hospital district removed

Files: scenarios/tax.md (common section, SCN-0109, SCN-0115), scenarios/cast.md (Tax rows), application/kyle-brief-2026-11-24-scenario-batch-5.md (item 11). No repo files edited.

Verdict: correct and complete. No blocking findings. Two should-consider notes (the transit-authority-on-part-of-a-city framing, item 4; and the future automatic-reduction scenario now needing its own actor, item 5).

## 1. Arithmetic: all correct

BB-13, store east of Main, base $187.40 (tariff-priced lines; matches SCN-0104's $12.80 + $59.20 + $107.00 + $8.40):

| Row | Working figure | Half-up |
|---|---|---|
| State 6.25% | 11.7125 | $11.71 |
| County 0.5% | 0.9370 | $0.94 |
| City 1% | 1.8740 | $1.87 |
| Crime-control district 0.25% | 0.4685 | $0.47 |
| Transit 0.25% | 0.4685 | $0.47 |
| Total | 187.40 + 15.46 | **$202.86** (correct) |

- BB-10, bakery west of Main: 187.40 + 11.71 + 0.94 + 1.87 + 0.47 = **$202.39** (unchanged, correct).
- Overbilling a city-keyed core would cause BB-10: the transit line, **$0.47** (correct; was 0.23 + 0.23 = $0.46).
- BB-14, home east of Main: 0.6518 → $0.65, 0.16295 → $0.16, total **$65.99** (unchanged, correct).
- Side note, not an error: SCN-0109 (b)'s BB-10 total is also $202.86 (city at 1.25% rather than 1%). The two scenarios now share a total for different reasons. That doesn't hurt anything; if anything it backs up SCN-0109's existing line "a missed district and a raised city rate can give the same total".

## 2. The 2% local limit (Tax Code §321.101(f)): holds everywhere

The local taxes are county 0.5, city 1 (1.25 from Oct 1, 2027), crime-control 0.25 (from Jan 1, 2027) and transit 0.25 (east of Main only, ends Sep 30, 2027).

| Location and period | Local total |
|---|---|
| East of Main, before Jan 1, 2027 (transit's start date isn't stated) | 1.75% |
| East of Main, Jan 1 – Sep 30, 2027 | **2.00%** (at the limit) |
| East of Main, from Oct 1, 2027 (transit ended, city 1.25) | **2.00%** |
| West of Main, before Jan 1, 2027 | 1.5% |
| West of Main, Jan 1 – Sep 30, 2027 | 1.75% |
| West of Main, from Oct 1, 2027 | **2.00%** |
| Bluebonnet County outside the city | 0.5% |
| Pecan Flat (city 1.5%, no county tax) | 1.5% |

- Under the old figures, east of Main was also 2.0% (0.125 + 0.125). The new figures keep it there.
- The crime-control district adopting from Jan 1, 2027 fits: east of Main already had 1.75%, which left exactly 0.25%.
- SCN-0109's sentence "had the transit authority still overlapped, the city could not have raised its rate" still holds: east would be 2.25%.

## 3. Leftover references: none that matter

I searched scenarios/ (excluding scenarios/review/), application/kyle-brief-*.md, application/places-sources/ and application/roadmap/ for: hospital, 0.125, 202.85, $0.46, 0.2343, "row 6", "6 the transit", "both end", "two districts", 1.875.

- "hospital" in scenarios/tax.md:323 (SCN-0115 status) and scenarios/cast.md:74: these are the intended change notes saying it was removed. Fine.
- "hospital" in application/places-sources/texas.md:40, 163, 220: these are general Texas law notes (school and hospital districts under Utilities Code §104.203; the hospital district as one kind of special purpose district sales tax). They have nothing to do with Bluebonnet. Fine.
- "0.125" in scenarios/cast.md is gone. The only remaining "0.125" hit is scenarios/cancel-rebill.md:295 ("40.1250"), which is unrelated.
- No stale $202.85, $0.46, 0.2343, row 6 or "both end" anywhere. The roadmap data has no hits.
- The common section (tax.md:10) now lists 5 rows and says "until the transit authority ends". This is consistent with cast.md.

## 4. Can a transit authority cover only part of a city? Plausible, but I'm not sure. Worth a sentence or a check

As I understand it, Texas transit authorities are built from whole units of territory, not from parts of a city. A metropolitan rapid transit authority (Transportation Code ch. 451) is built from a principal city plus other cities, or a county's unincorporated area, that confirm by election. A regional transportation authority (ch. 452) is built the same way. A coordinated county transportation authority (ch. 460) is built from a county plus the cities that join. Cities also withdraw as whole units. So an authority *created* to cover only the eastern half of a city does not seem plausible. The way a city ends up partly inside and partly outside an authority is usually its boundaries changing after the authority's area was fixed. One example: a city annexes land that was in the authority as unincorporated county territory. Another: a city grows past the authority's area. The Comptroller publishes rates by address because a city's locations can carry different combinations of special-purpose and transit taxes. I have not checked whether chapters 451 and 452 add annexed land to the authority automatically or take it out. That rule decides which of the two examples is realistic, so I'm not sure enough to name one. Suggestion: keep the transit authority, mark *why* it covers only east of Main as invented, and give the likely reason in one clause. For example: "east of Main Street, land the city annexed that was already in the authority (**invented**; how annexation moves a transit authority's boundary is a citation check)". Another option is to put this under the existing "Open (a citation check)" pattern used for the crime-control district's annexation (SCN-0108). Leaving the text as it is would not be wrong for invented test data. It is just the one place where Kyle, who knows Texas, may stop and ask "how?"

## 5. Did removing the hospital district lose a case? Nothing a scenario relied on

- **Automatic rate reduction (§321.102(e)–(h)).** No written scenario exercised it, before or after this change. The old SCN-0109 already ended both the hospital district and transit on Sep 30, 2027, before the city's rise. It mentioned the reduction only as a hypothetical ("a district without such debt would instead have been reduced automatically"). It still does, and the case stays under "Not yet written" (tax.md:379). One cost for later: whoever writes that scenario no longer has a ready-made district. With transit at 0.25% east of Main the total there is already 2.0%, so a new district can't be added there without passing the limit. That scenario will need its own district, for example one west of Main, or in a period after Sep 30, 2027 that overlaps the 1.25% rise. That is easy to do but worth knowing.
- **One premise in two places that each cover part of the city, with two rows above the citywide ones.** This is gone. BB-13 is now in one such place. The rule SCN-0115 tests (membership is decided premise by premise, not keyed to the city) is still tested. A second overlapping place added coverage but not a different rule.
- **Rounding each line on its own vs rounding a combined rate.** The old two lines of 0.2343 each rounded to $0.23 ($0.46 in all), where one combined 0.25% would round to $0.47. That was a quiet test of rounding each line separately, and it is now lost here. It is still covered explicitly in SCN-0104 and SCN-0106 (b) ($28.28 vs $28.29). No loss.
- **New, minor point.** On BB-13 the crime-control district's line and the transit line are now both $0.47. A core that puts one tax's amount under the other's row would produce the same figures. SCN-0104's rule says each tax line names its row and place, so a test that checks the line's row catches this. A test that checks amounts alone would not. Optional: a sentence in SCN-0115 saying the test asserts each line's row, not only its amount.
- **Hospital-district specifics** (in reality ch. 324-type rates in eighths of a percent, and a reduction that is sometimes automatic). No scenario used these.
