Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-10-29 (written from the money stream's folder; this stream has not run yet)
**Branch**: `main`. `git pull --ff-only` first.
**Status**: Not started. Waiting for Ryan to open the first session here.

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Ryan relaxed the gate on 2026-10-29: scenarios run beside the schema instead of after it, and the core build plan (step 3) waits for both (DECISION-LOG 2026-10-29). Estimate 3 / 5 / 8 weeks. Kyle has room to check worked bills over the next six weeks (Ryan, 2026-10-29).

This stream writes no schema. It touches no `sql/` file and no patch tests, and doesn't need Docker unless it checks a scenario against the live schema (then follow the board's shared-resource rules).

## What exists (GBM, `../gas-billing-memory/application/`)

- `invariant-scenarios/`: 29 docs, the "cases to cover" for each invariant family (28 family docs and an index);
- `bi-temporal-scenarios.md`: 26 date-tracking scenarios;
- `configurable-rules/decision-tables/` (60) and `configurable-rules/workflows/` (80);
- `configurable-rules-scenario-strategy.md`;
- `test-fixtures/` (14 fixture catalogs).

Much of this predates the -19 to -23 rulings. Read it against the current rules, not as settled.

## Not Yet Done (in order)

1. [ ] **Source inventory first** (standing practice): what each existing doc covers, what has changed under it since it was written (Kyle's 10-14, 10-15 and 10-21 rulings; Ryan's R-01 to R-11, W2-Q1, W3-Q1; 10-21 "refunded and donated are derived"), and which invariants have no scenario. Then ask Ryan, one decision at a time:
   - where scenarios live: GBM (beside the existing docs; every GBM change is logged in `wiki-ingestion-pending.md`) or this repo;
   - the shape of one scenario (prose, given/when/then, a worked bill), shown on one real example before writing many.
2. [ ] **Scenario prose for families already at parity**: bi-temporality and immutability, cancel-rebill, deposits (-15), backbilling (-18), periods, close snapshot, GL mapping and aging (-22), the billing pipeline and charge composition, WNA, tenant isolation (except the cross-tenant link fix).
3. [ ] **Worked bills with dollar figures**, sent to Kyle in batches; record his answers in GBM.
4. [ ] **State machines, exception paths, the persona matrix.**
5. [ ] **Families still changing, after their patches mirror** (the board's mirror queue): cash, disputes and collections after -23, -25 and -26 (money stream); tax, gas cost, zones and reads after the rates stream's patches.
6. [ ] **The coverage audit** against all 135 invariants, last, once the schema is at parity.
7. [ ] **The testing strategy** (roadmap decision R-15: what testing approach once the scenarios exist).

## Warnings

- **Scenarios describe rules and rulings, not tables.** Where a family's schema is still being built, write against the ruling and mark what the patch may still change.
- **Don't edit the money or rates streams' handoffs.** Leave notes on the board.
- **A change to GBM's `main` is logged in GBM `application/wiki-ingestion-pending.md` in the same edit.**
