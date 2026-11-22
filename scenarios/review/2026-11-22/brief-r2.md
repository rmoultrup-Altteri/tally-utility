# Re-review brief: scenarios round 4, second pass (2026-11-22), narrow

Two reviewers (Opus, Fable), independent: don't read the other's report for this pass. Read-only on the repository. Read `brief.md` beside this file first: the sources, the standing rules, the read-only live database, and what to look for all apply. Read `scenarios/README.md` and `scenarios/cast.md` too.

**Scope: only what changed since the first pass.** See it with `git diff 1e25a99 e6dda13 -- scenarios/cash.md scenarios/cancel-rebill.md scenarios/periods-and-aging.md scenarios/billing-pipeline-and-charge-composition.md scenarios/README.md`.

1. The corrections to SCN-0081 – 0098 in `cash.md`.
2. The five new scenarios, SCN-0099 – 0103, never reviewed.
3. SCN-0033 (b), SCN-0089 (b), and SCN-0024's last bullet, rewritten to Ryan's latest ruling (DECISION-LOG, 2026-11-22: the hidden amount is one charge, part of it due later; it replaces the matched pair of lines).
4. SCN-0053 as corrected.

First-pass findings and what was done: `codex.md` and `opus-fable-summary.md` here.

Answer four questions:

- **Is each first-pass finding really closed?** Name any that isn't, or whose fix made a new fault. Check the neighbours: other scenarios that cite or share the changed facts (grep the family files for the customer, the ID and the figure).
- **Are the five new scenarios right?** Recompute every figure and date (with the weekday); check every built / refused / accepted claim against the mirrored schema (which guard, database or core); check each rule against its source, and each reading is marked with an Open.
- **Does the one-charge ruling hold together?** Walk SCN-0033 (b) from Dec 2 to past Dec 31: balances, penalty base, what a payment of each plausible amount pays, aging, the December bill, an account closing, a void of the correction. Look for anything it contradicts, in the scenarios or the rulings, and for text anywhere still saying the matched pair.
- **What can't a test author write down** from the text as it stands?

Not wanted: style; a first-pass finding already marked Open (Kyle) or sent to the board, unless it is now stated wrongly.

Rank **must fix**, **should add**, **note**; at most 15, most important first; each with scenario ID, what is wrong, evidence (file and line, or the query and its result), and the fix. End with a verdict: ready for Kyle, or not and why. If you find little, say so; don't pad.
