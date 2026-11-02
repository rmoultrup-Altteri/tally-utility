# Review brief: the first 26 scenarios (2026-11-02)

You are one of three independent reviewers (Opus, Fable, Codex). Read-only: do not edit any repository file.

## What this is

TallyUtility is a gas-utility billing platform. The PostgreSQL schema is in `/Users/ryanscomputer/code/tally-utility-scenarios/sql/` (`tu.sql` plus `v5.4.2-NN-*.sql` patches); a future C# core will evaluate the rules. The scenarios are the cases that core must pass. Each one is meant to be checked by a domain expert (Kyle: the dollar figures), by the product owner (the rule), and turned into a test (Given / When / Then).

**Review these files** (all in `/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/`):
- `README.md` (the shape and conventions), `cast.md` (the utilities and customers), `cast-sources/texas-city-gas-tariffs-2026-11-02.md` (the real tariffs the cast is modelled on)
- `billing-pipeline-and-charge-composition.md` (SCN-0001), `cancel-rebill.md` (0002–0006), `deposits.md` (0007–0012), `backbilling.md` (0013–0019), `periods-and-aging.md` (0020–0026)

**Sources the scenarios claim to follow** (check them against these, not against your own idea of the rules):
- `application/scenarios-source-inventory-2026-11-02/rulings-digest.md`: every ruling since 2026-10-13, with its source
- `application/DECISION-LOG.md` (150 KB; `grep -n "^## "` and read the sections you need)
- `application/deposits-rules-for-the-core.md`, `application/a2-rules-for-the-core.md` (backbilling; 190 KB, grep its headings)
- the patches: `sql/v5.4.2-15*` (deposits), `-18` (backbilling rule terms), `-21`/`-17`/`-19` (voids, reversals, payments' dates), `-22` (periods, close, GL mapping, aging, write-off recovery)
- `application/invariant-parity-measurement-2026-10-13.md` (grep `^| CI-NNN `), and the canonical invariants in `/Users/ryanscomputer/code/gas-billing-memory/application/canonical-invariants.md` (grep `^### CI-NNN`)

**Standing rules the scenarios must respect:** scenarios describe rules and rulings, not tables; Texas-first launch never justifies Texas-only design (a statutory rule is a row for its place); Texas's 16 TAC §7.45 does not bind city-owned gas systems (the first customers), whose policy is their own tariff row or nothing; the utility owns its regulated values; money is add-only; four-decimal working figures, half-up to the cent per line (Kyle 10-15).

## What to look for

1. **Wrong figures.** Recompute every worked bill, ledger and aging table. Report the scenario, the line, what it says and what it should say.
2. **Rules misstated.** A "Then" that the cited source does not support, or that the source contradicts; a source cited that says something else; a ruling that changed and the scenario follows the old one.
3. **Gaps inside each family.** Cases the rules clearly distinguish that no scenario exercises (a boundary, a refusal, a second branch of a rule, an interaction between two rules). Name the case concretely, with the rule that makes it distinct. Prefer cases a real small city gas system would hit.
4. **Gaps across families.** Interactions the scenarios skip (for example a correction that crosses a closed period AND a rate change; a deposit applied to a bill later voided).
5. **Invented facts presented as rules.** Anything not marked "(invented)" that has no source.
6. **Open questions that are already answered** by a ruling in the sources, and **questions that should be open but are not**.
7. **Test-readiness.** A Given that leaves something a test would have to guess; a Then that cannot be asserted.

Don't report style, wording or formatting. Rank your findings: **must fix** (a wrong figure, a wrong rule), **should add** (a gap worth a scenario), **note**.

## How to report

For each finding: scenario ID (or family), severity, what is wrong or missing, the evidence (file and section or line), and the fix or the case to add. Keep each finding short. At most 25 findings; put the most important first.
