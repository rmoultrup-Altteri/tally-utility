# v5.4.2-22 review round 4: findings and dispositions (2026-10-16)

**Verdicts: Opus ready, Fable ready, Codex not yet.**

- **Opus and Fable** executed their checks against their own clones. Opus also ran a randomized test of the cap: 4 runs × 3,000 inserts, checked independently, with no violation.
- **Codex** reviewed the source. The author ran its fifteen probes on fresh clones of frozen r4. Each printed what Codex predicted, B1 and S1 included (outputs appended to `codex-r4.md`).

The fixes go into r5.

| # | Finding | Who | Disposition in r5 |
|---|---|---|---|
| 1 | The owner's `created_at` is kept for history loads. A row in a write-off's tree recorded at `infinity` (or far in the future) makes every later row of the tree "recorded before" it, so every later posting gets 40001 and the retry can never succeed. | Codex B1 (reproduced by the author: infinity, 2200, 9000, and an ordinary writer) | **A row in a write-off's tree is recorded at a finite time already reached.** The write-off itself is covered too: the trigger now also fires for `transaction_type = 'write_off'`, and the invariant pins the new trigger definition. Battery R12f (a write-off at infinity) and R12g (a recovery at 2200). Mutations M69, M70 and M72. |
| 2 | The new edges lock can deadlock with a close. The close's snapshot rows take the tenant row FOR KEY SHARE (their tenant FK) after the head, while an edges change holds the tenant row and waits for the head. A transaction that holds the tenant row FOR UPDATE (a key column in its SET, an ORM save) and then changes the edges hits it. The header said "the close never locks the tenant row". | Opus S1 (executed twice), Fable S1 (executed, three sessions) | **Stated** in the lock-order paragraph, as the withdrawal deadlock is: one side is aborted and nothing is written; change the edges in a statement of their own. Both reviewers offered this or rerouting the FK. *Not taken:* rerouting the snapshot tables' tenant FK to the period. That changes the snapshot tables' keys, and the close's own `closed_by` FK to users would still take a row lock. |
| 3 | The walks' plan settings are not pinned by the invariant; only R10g's timing catches their loss | Fable S2, Opus N | `assert_periods_guard_invariants()` checks both functions' `proconfig` exactly. M68 is now caught at apply. |
| 4 | A valid history batch with mixed recorded times in one statement is refused (40001); the same rows load as one statement per instant | Codex S1 (reproduced) | Stated as residual **R12**: a history load under a write-off posts one statement per recorded instant, in recorded order. |
| 5 | No test nets same-date rows that would cross the cap if taken one by one | Opus N | Battery R12h admits a recovery, its reversal and a new recovery, all on one date. Mutation M71 (a ROWS frame) is caught one check earlier, at R10f, whose same-date rows also cross. |
| 6 | CR15 matches the message, not the SQLSTATE | Codex S2 | CR15 now requires `40001` and "retry it". |

Not taken:
- **Codex S2: move the nested-tree, A→B→A and 1,000-bound probes into the battery.** They were executed twice, in r3 and r4, through Codex's probes n9 and n10.
- **Codex S2: CR15's start ordering uses sleeps, not a barrier.** CR15 has passed on every run so far.
- **R9b's label.** It is left as is.

## r5 results (author)

- Strict apply: the first run applies; the second is skipped on its marker.
- `battery-22.sql`: 157 PASS on a vacuumed ledger.
- `races/close-22.sh`: CR1–CR15 PASS.
- `mutations-22.py`: 72/72 caught.
- `tests/ci.sh`: all pass, 35 steps.
