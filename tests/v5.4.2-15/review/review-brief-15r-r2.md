# Review round 2: v5.4.2-15 (rewrite)

Same job and rules as round 1 (`review-brief-15r-r1.md`: read it again; probing rules, output rules and the "several short messages" rule are unchanged). Round 1: all three of you said **not yet**. Your reports are in this directory (`opus-r1.md`, `fable-r1.md`, `codex-r1.md`, with Codex's probes in `codex-r1-probes/`).

**Frozen artefacts (round 2)** — check the hashes:
- patch `tests/v5.4.2-15/review/patch-15r-frozen-r2.sql` — md5 `edb410da0fffe721ac499e5607cc8a61`
- battery `tests/v5.4.2-15/review/battery-15r-frozen-r2.sql` — md5 `4512683f6e9c9847353481883a09d1b3` (292 checks)
- tests: `migration-15r.py`, `mutations-15r.py` (137 mutations, all caught), `races/due-mutex-15.sh`, `evidence-txn-15.sh`, `fail-first.py`. Output file for this round: `opus-r2.md` / `fable-r2.md` / `codex-r2.md`.

## What changed, by finding (verify each; do not trust this list)
- **Rate floor ordering** (Opus S3, Fable B1): a rate for every category now clears **every class** of the state and service (`deposit_rate_floor`), not only the classes its categories map to today. A rate for a named category whose class has no law row at all is refused (Codex B1, rate side). Tests F17–F19.
- **Comparator** (Opus B2/B3, Fable B2, Codex B1–B3, S1): `deposit_tariff_compare` rewritten. No law row for the category's class ⇒ refused. Months of the **highest** bill, or a **minimum amount**, where a cap in average months exists ⇒ refused (cannot be shown to fit). An amount against a cap the law left `unruled` ⇒ refused. A count trigger: lower count, **longer window**, no `consecutive`, counting **disputed** bills ⇒ looser; a trigger of the same code whose condition cannot be compared (other measure, other unit, combined condition that is not the law's) ⇒ refused. One guard per kind in both insert checks. Tests N16–N26 (the count/unruled ones in a new block r30).
- **The cap on a deposit** (Opus B1, Fable S1): where the cited document caps the deposit, the statutory cap is **always recorded** (the governing part's id, the figure it was computed from), whichever source set the cap that applied, and the cap that applied may not exceed the part's figure (fraction of annual billing, months, fixed). A tariff cap must cite the tariff row. `deposits_cap_source_check` relaxed accordingly. Tests R27–R34 (block r28).
- **Instalments** (Codex B4, Opus S5): a deposit's schedule is the law's; where the law gives none, the cited tariff's. Tests I1–I5 (block r29).
- **Insert check** (Fable S3): a return of `excess_over_cap` needs a cap (`X16`); two guards of one kind refused (`X15`).
- **Precondition and re-run** (Opus S1, S2; Fable S4): a second application is skipped whole by psql `\if` (nothing re-installed); the role must see every tenant; interest accruals on carried deposits are counted and named. Migration tests P2b, P5b.
- **Wording**: R4 (a deposit's own closed law row stays citable for dates after its close — Ryan's B1, 2026-10-02, "grandfathered"; a successor only for the dates it is in force), R7 (comparator limits), R11 (a partial return needs no due row, as a voluntary refund needs none), R12 (AC-24/25 are rewritten when the patch is mirrored).
- **Tests** (Opus S6, Fable S6, Codex S2/S3): 27 new mutations over the guards you named; new battery cases for instalments, born held, legacy interest, combined cap, refund = remainder, cash released, uncredited interest, tariff-trigger source; weak checks tightened so each guard is refused by itself (N5, R3, R13, V4, Q1, V9, R5, F13).

## Decisions made without Ryan (challenge them)
1. Own closed law row stays citable after its close (per his 2026-10-02 B1 ruling) — Fable asked; I read the ruling as "grandfathered".
2. `principal_returned` needs no due row (voluntary partial return), as a voluntary refund needs none.
3. Not done: a vocabulary for count-condition event names (Opus S8); the AC-24/25 rewrite (at mirror); testing a non-superuser owner (the patch now refuses one).

## What to do
Verify each fix above is real and complete; look for what the fixes broke or newly allow; re-check anything from your round-1 report not on the list; then give a verdict: **ready** or **not yet** with blocking items. Same output rules.
