# Review round 5: v5.4.2-15 (rewrite) — a small delta on round 4

Same job and rules as before (`review-brief-15r-r1.md` … `r4.md`). Round 4: Opus **READY**, Fable **READY**; Codex could not run (usage limit) and has not seen anything after round 3 (its round-3 findings were fixed in round 4: combined/renamed triggers, coverage per profile segment, a city's cap and source, the tariff holding whatever the source). Output files: `opus-r5.md` / `fable-r5.md` / `codex-r5.md`. **Codex: review the whole patch, not only the delta**, since you have not seen rounds 4 and 5; start from `codex-r3.md` and check each of your round-3 findings first.

**Frozen artefacts (round 5)** — check the hashes:
- patch `tests/v5.4.2-15/review/patch-15r-frozen-r5.sql` — md5 `fb44ecc041cb2f6004171dd3723962bb` (diff from `patch-15r-frozen-r4.sql`: `diff patch-15r-frozen-r4.sql patch-15r-frozen-r5.sql`)
- battery `tests/v5.4.2-15/review/battery-15r-frozen-r5.sql` — md5 `1c93db1658445380739edd198b0e3543` (334 checks)
- tests: `migration-15r.py`, `mutations-15r.py` (166 mutations, all caught), `races/due-mutex-15.sh`, `evidence-txn-15.sh`, `fail-first.py`.

## The delta from round 4
- **Opus r4 S1**: a deposit with a category must cite the tariff row in force for that category on its posting date (leaving it out skipped the utility's own policy). R53; mutation M167. R10 and R13 now use categories with no tariff (`nt`, `notariff`) so each is refused by its own guard alone.
- **Wording** (Fable r4 notes, Opus r4 notes): R7 and a comment say that under a law cap in highest bills or a seasonal average a months tariff is neither compared nor held, and that a stricter combined condition or a longer notice is refused (fail toward refusal).

## Decisions made without Ryan (unchanged)
1. A deposit's own closed law row stays citable after its close. 2. A partial return needs no due row. 3. Not done: a count-event vocabulary; the AC-24/25 rewrite (at mirror); a non-superuser owner (refused).

## What to do
Opus and Fable: verify the delta and say whether it changed your verdict. Codex: the whole patch as above. Verdict: **ready** or **not yet**. Same output rules.
