# Review brief: scenarios round 2 (2026-11-04)

You are one of three independent reviewers (Opus, Fable, Codex). Read-only: do not edit any repository file.

## What this is

TallyUtility is a gas-utility billing platform. The PostgreSQL schema is in `/Users/ryanscomputer/code/tally-utility-scenarios/sql/` (`tu.sql` plus `v5.4.2-NN-*.sql` patches); a future C# core will evaluate the rules. The scenarios are the cases that core must pass. Each is checked by a domain expert (Kyle: the dollar figures), by the product owner (the rule), and turned into a test (Given / When / Then). Round 1 (2026-11-02, `scenarios/review/2026-11-02/`) reviewed SCN-0001 – 0032; its findings were applied.

**Review in this round** (all in `/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/`; read `README.md` and `cast.md` first):
1. **New scenarios SCN-0033 – 0052**, written 2026-11-04 to fill round 1's gaps: `cancel-rebill.md` (0033), `periods-and-aging.md` (0034, 0049–0052), `backbilling.md` (0035–0041), `deposits.md` (0042–0047), `billing-pipeline-and-charge-composition.md` (0048).
2. **Scenarios reworked to Kyle's answers of 2026-11-03**: SCN-0001, 0004, 0006, 0007, 0008, 0010, 0011, 0016, 0019, 0024, 0027, 0028, 0029, 0030, 0031, and the cast. Check that each follows his answer, and that nothing reads more into it than he said.

**Sources the scenarios claim to follow** (check against these, not your own idea of the rules):
- Kyle's answers: `/Users/ryanscomputer/code/gas-billing-memory/application/kyle-decisions-2026-11-03-scenario-batch-1.md`, and his earlier `kyle-decisions-*.md` files in that folder
- `application/scenarios-source-inventory-2026-11-02/rulings-digest.md` (rulings since 2026-10-13)
- `application/DECISION-LOG.md` (150 KB; `grep -n "^## "`; the 2026-11-04 entries are this stream's)
- `application/deposits-rules-for-the-core.md`; `application/a2-rules-for-the-core.md` (backbilling; grep its headings)
- the patches: `-15` (deposits), `-18` (backbilling rule rows; also mirrored in `sql/tu.sql`), `-21`/`-17`/`-19` (voids, reversals, payment dates), `-22` (periods, close, aging, write-off)
- SCN-0048 cites Texas Utilities Code §§182.001–182.005 (read from a FindLaw copy); check the reading if you can

**Standing rules:** scenarios describe rules and rulings, not tables; Texas-first launch never justifies Texas-only design; 16 TAC §7.45 does not bind city-owned systems (the first customers), whose policy is their tariff or, where silent, a platform default Kyle has ruled; always follow the tariff (Kyle 11-03); the utility owns its regulated values; money is add-only; four-decimal working figures, half-up to the cent per line (Kyle 10-15). Facts not from a source are marked "(invented)". Questions are marked "Open (Kyle, next batch)" or "Open (Kyle)".

## What to look for

1. **Wrong figures.** Recompute every worked bill, ledger, interest figure, date and day count, and aging table.
2. **Rules misstated.** A "Then" the cited source does not support or contradicts; a ruling applied beyond what it says; a scenario contradicting another scenario.
3. **Gaps** the rules clearly distinguish that no scenario exercises, inside a family or across families. Name the case and the rule.
4. **Invented facts presented as rules.**
5. **Open questions already answered** by a source, and **questions that should be open but are not** (especially engineering readings presented as settled).
6. **Test-readiness.** A Given that leaves something a test would guess; a Then that cannot be asserted.

Don't report style or wording. Rank: **must fix** (a wrong figure or rule), **should add** (a gap), **note**. For each finding: scenario ID, severity, what is wrong, the evidence (file and section), and the fix. At most 25 findings, most important first.
