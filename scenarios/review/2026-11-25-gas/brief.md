# Review brief: scenario family "gas cost, zones and factors, meter reads" (SCN-0130 – 0145), round 7

Repo: ~/code/tally-utility-scenarios (TU). Kyle's knowledge repo: ~/code/gas-billing-memory (GBM). Read-only review: do not edit any repo file.

What to review: `scenarios/gas-cost-zones-and-reads.md` (new) and `scenarios/cast.md` §6 plus the four new customer rows (BB-17, BB-18, BB-19, GP-08). Conventions: `scenarios/README.md`. Sources inventory (built by the author's helper, may itself be wrong): /private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility-scenarios/1c5b1e89-a0f2-4c86-8d74-e61c0c08fda3/scratchpad/gas-zones-reads-inventory.md.

This family is written ahead of its patches (Ryan's go-ahead 2026-11-25): most of it is not built. Check:

1. **Arithmetic.** Recompute every dollar figure and volume: four-decimal working math, half-up to the cent per line; a tax line's base is the sum of the rounded lines it names. Rates are in `cast.md` §1–3 and §6. Bluebonnet taxes: residential inside the city 1% city only (2026); non-residential: state 6.25%, county 0.5%, plus city 1% inside the city; outside the city no city tax. Check day counts and weekdays of dates.
2. **Rulings cited.** For each "Sources:" item, open the GBM/TU ruling and check it says what the scenario claims (GBM `application/kyle-decisions-*.md`, `wu5-wu6-kyle-decisions-2026-07-10.md`; TU `application/DECISION-LOG.md` — grep headings, never read whole). Flag any rule stated as settled that is only the author's reading, and any Open that a ruling already answers.
3. **Built / not built.** Each Status line says what exists in the schema. Verify against `sql/tu.sql` (42k+ lines: grep, never read whole) and `application/invariant-parity-measurement-2026-10-13.md` (grep `^| CI-NNN `). Every "refused" claim: is there a guard, or is it the core's, and does the scenario say which?
4. **Consistency** with other scenarios (SCN-0001, 0002, 0006, 0015, 0019, 0027, 0037, 0055, 0078; `cash.md` SCN-0082) and the cast (customer facts, billing days, figures). A cast customer reused on conflicting facts?
5. **Law.** 16 TAC §7.45 quotes: (6)(C) six-month actual read, postcard at the second consecutive month without access; (6)(B)(viii) estimated-bill marking; (4)(E)(vii) estimated-bill disconnection bar; scope: residential and small commercial, unincorporated areas, regulated gas utilities. §7.5519 sets no effective-date rule. Flag any misstatement.
6. **Gaps.** Important cases this family should cover but doesn't (gas cost, zones/factors, reads), within the cast; and anything a C# test could not be built from (ambiguous Given/When/Then).
7. **Plain language:** no table or column names in scenario text.

Report: numbered findings, each with severity (blocking: wrong figure or wrong claim; should-fix; nit), the SCN and line, the evidence (file:line), and the fix. Write the full report to the path given in your task (explicitly requested), then reply with a one-paragraph summary under 150 words.
