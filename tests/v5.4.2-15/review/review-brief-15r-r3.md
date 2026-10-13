# Review round 3: v5.4.2-15 (rewrite)

Same job and rules as rounds 1 and 2 (`review-brief-15r-r1.md`, `review-brief-15r-r2.md`). Round 2: all three of you said **not yet** (reports: `opus-r2.md`, `fable-r2.md`, `codex-r2.md`, Codex's probes in `codex-r2-probes/`). Every round-1 fix was confirmed; the round-2 findings were narrower. Output files: `opus-r3.md` / `fable-r3.md` / `codex-r3.md`.

**Frozen artefacts (round 3)** — check the hashes:
- patch `tests/v5.4.2-15/review/patch-15r-frozen-r3.sql` — md5 `0a13969608d7360dff2ae468a90b86d4`
- battery `tests/v5.4.2-15/review/battery-15r-frozen-r3.sql` — md5 `0f6ae2ce52c38492ec3fc31ce09b0593` (315 checks)
- tests: `migration-15r.py`, `mutations-15r.py` (154 mutations, all caught), `races/due-mutex-15.sh`, `evidence-txn-15.sh`, `fail-first.py` (every block passes alone).

## What changed, by round-2 finding (verify; do not trust this list)
- **Lesser-of cap lifted by naming the larger part** (Opus B1): the cap may not exceed the least figure computable from the one basis recorded (fixed amounts and parts of the named part's kind). `deposit_cap_part_figure` also computes highest_bills (the basis is their total) and seasonal_average (basis × multiple) (Fable S2). R40–R43.
- **A looser usage trigger under another code** (Opus B2): triggers are matched by code AND by what they measure (usage ratio, event count over a unit). N27. The law's other guards (service age, recent move, notice, cure) must be carried identically (Fable S4): N28. A count-event vocabulary is still not added (the comparison no longer depends on the code, so the code carries no meaning to guard).
- **A city's cap held to nothing** (Fable B1, Opus S1): under a delegation, or any document with no cap, `cap_component` must be NULL; a tariff cap may not exceed the tariff's flat amount, or months × the monthly billing recorded (`cap_basis_amount` is then required, and only then). R35–R39, R44.
- **Coverage of the whole range** (Fable S1, Codex B1): the comparator builds the class's own datemultirange from the law rows given and refuses unless it covers the tariff's range. N18, N30, N31.
- **A rate for every category with a class of no law** (Codex B2, Opus S3): every class the rate reaches (all classes for a category-less rate) needs a law row in force; one with none refuses. F19, F20. (Fictional state ZX holds the class with no law; Texas has none.)
- **Instalment completeness after an early flush** (Codex B3): the aggregate check also runs when an instalment is inserted, not only when the deposit is. I6, I7.
- **Tests** (Opus S2, Codex S1/S2): mutations for the guards you named (the close floor's accrual branch, the successor's span equality, fractional counts, the tariff instalment sum, `instalment_received`, a statutory source with no cap, lesser-of); `migration-15r.py` now requires key presence for every retained column (two named columns may vanish only while empty) and P1f checks the refusal's reason.
- **Wording**: the psql-only skip is stated in the header; R7 names what the comparator holds (the law's guards, trigger matching) and what it does not.

## Decisions made without Ryan (challenge them)
1. A deposit's own closed law row stays citable for dates after its close. The first draft's tests, written under Ryan's B1 ruling of 2026-10-02, accept both a later record citing the old row ("grandfathered") and one citing the successor; Fable asked whether Ryan meant the opposite — if you have a reason to think the old tests misread him, say so.
2. A partial return needs no due row (as a voluntary refund needs none).
3. Not done: a count-event vocabulary; the AC-24/25 rewrite (at mirror); a non-superuser owner (refused).

## What to do
Verify each fix; look for what the fixes broke or newly allow; re-check any round-2 finding not on the list; then give a verdict: **ready** or **not yet** with blocking items. Same output rules.
