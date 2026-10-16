# v5.4.2-22 review round 7: findings and dispositions (2026-10-16)

**Verdicts: Opus ready, Fable ready. Codex not run** (usage limit, reset 4:01 PM). Ryan waived it for the rounds after r5: "let's not wait for codex on this". Codex said ready on r5.

- **Opus and Fable** executed their checks against their own clones: battery 167 PASS on a vacuumed ledger, CR1–CR20 (30 PASS), plus their own probes. Both checked the rule's four rows and their order against the close's statements, and found them exact.

Every finding is wording in the lock-order paragraph. None admits a row or loses data: one side is aborted with 40P01 and writes nothing.

| # | Finding | Who | Disposition in r8 (comments only) |
|---|---|---|---|
| 1 | The rule describes two-transaction cycles; a cycle can run through a third. In Opus's case (period row FOR SHARE; a customer row; a close), the aborted side was a plain writer that did nothing the paragraph warns against. | Opus S2 (executed), Fable N1 (executed) | The rule says "waits — directly, or through other transactions it waits on". It says the aborted side may be a third transaction, that **no list of shapes is promised complete**, and that every writer retries 40P01. Four rounds in a row added a shape; this ends the promise rather than adding a fifth. |
| 2 | One statement can deadlock with a close: an UPDATE of tenants that changes the edges and names `slug` (an ORM full-row save, slug unchanged) locks the tenant row FOR UPDATE, then the head. A transaction of its own does not avoid it. | Opus S1 (executed; without slug it waits, no deadlock) | Stated as a shape, with the advice: change the edges in an UPDATE that names no unique column. |
| 3 | "What takes the rows" leaves out a bare `SELECT … FOR UPDATE` / `FOR NO KEY UPDATE` on the head (tally_app, tally_void: a column UPDATE grant is enough) and on the period (tally_app) | Fable S1 (executed), Opus N | Added. No new cycle outside the rule (both reviewers). |
| 4 | The predicted reverse-order shape (a write, then a key change: no deadlock) | Fable (executed) | Marked executed. |

r8 changes no code and no test: the diff from r7 is comment lines only.

## r8 results (author)

- Strict apply: applies.
- `mutations-22.py`: 79/79 caught, one full run.
- `tests/ci.sh`: all pass, 35 steps.
