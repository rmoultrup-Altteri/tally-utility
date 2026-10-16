# v5.4.2-22 review round 3: findings and dispositions (2026-10-16)

**Verdicts: Opus not yet, Fable ready, Codex not yet.**

- **Opus and Fable** executed their checks against their own clones.
- **Codex** reviewed the source. The author ran its twelve probes on fresh clones of frozen r3 and appended the outputs to `codex-r3.md`. Each printed what Codex predicted, with one exception: n7's own error capture failed, because psql leaves `LAST_ERROR_SQLSTATE` at `00000` after a failed COPY. Run directly, the COPY cycle is refused.

The fixes go into r4.

| # | Finding | Who | Disposition in r4 |
|---|---|---|---|
| 1 | The cap checks only the tree's final net, but aging and the close net it at a date. A later-dated reversal makes room for an earlier-dated recovery: February's snapshot froze 200 recovered against a 100 write-off. A recovery dated before its write-off is also accepted. | Opus B1 (executed) | **The cap holds at every date of the tree.** For each date in the tree, the net of the rows dated on or before it stays in [0, written off]. **A row under a write-off is dated on or after the entry it names**, so by induction every path down from the write-off is in date order. Battery R12 (Opus's repro, refused on Feb 20), R12b (recovery before its write-off), R12c (reversal before its recovery), R12d (the same story dated in order is admitted). Mutations M64 and M65. |
| 1b | *Author, while checking Opus's [P] "no shape on the recorded-time axis":* `created_at` is the transaction's **start**. A writer that began earlier and posts after a younger one has committed is recorded before it. Aging at an instant between the two starts sees the older writer's recovery without the younger writer's reversal, which is over the cap again. | Author | **A row recorded before a row already in its tree is refused** with 40001 ("retry it"). Recorded order then follows the order in which the cap checked the rows, so every recorded instant sees a state the cap checked. Battery R12e (owner-stamped created_at). Race CR15 with two real sessions: the older writer is refused, and its retry is admitted. Mutation M66. |
| 2 | The close takes its instant, then reads the edges in a separate statement, without a lock. An edges change committed in between is stored as if it held at the instant. | Codex B1 (simulated); Opus N2 (cosmetic) | **Enforced, not reworded.** A new trigger, `enforce_aging_edges_close_order` (BEFORE UPDATE OF the edges on `tenants`), takes the tenant's close head FOR SHARE, as a money write does. `tally_app` already holds the lock column; the close never locks the tenant row, so no lock cycle is added. Pinned in the periods invariant. Races CR13 (the close waits for an edges change in flight and stores the new edges) and CR14 (an edges change waits for a close in flight; the snapshot keeps the old edges). Mutation M67. Residual R10 notes that the waiting change's history row is dated at its own transaction's start. |
| 3 | The upward walk's final join (the write-off lookup) scanned the tenant's ledger for every reversal row: 5,000 reversals after 200,000 rows loaded in one transaction took 51 s. | Opus S1 (executed) | The walk carries each entry's type and customer, and the write-offs are chosen from the walk itself. **Author, at r4:** the battery then failed R10g (30 s) intermittently. On a ledger the planner believes empty (fresh, or just vacuumed), the downward step hash-joined a sequential scan of the whole ledger, and with sequential scans off it merge-joined a full index scan. Both walk functions now run with `enable_seqscan`, `enable_hashjoin` and `enable_mergejoin` off. Measured: five battery runs with a VACUUM between each, all about 1.7 s; Opus's 5,000 reversals take 0.8 s. Mutation M68 drops the settings. Residual R11 states the measured sizes. |
| 4 | Two transactions posting under the same two write-offs in opposite orders deadlock. The cap's id order holds within one row only. | Fable S1 (executed, two sessions), Codex S1, Opus N1 (executed) | Stated in the lock-order paragraph. Writers retry 40P01 and 40001. |
| 5 | "No step can scan a ledger" is stronger than the evidence. | Codex S1 | The walks now have pinned plans. The claim in the header is the measured one (R11). |
| 6 | Missing tests: nested write-offs, A→B→A, a chain exactly at the bound; R9b's label overstates its order | Codex S2 | Executed by the author through Codex's probes n9 and n10 (both as predicted), recorded in `codex-r3.md`. The battery adds the date and recorded-order shapes above. R9b's label is left: the brief no longer relies on CTE order. |
| 7 | No mutation targets the upward walk's step | Opus N4 | M56 now targets the new step (`WHERE u.mine AND u.depth < c_max`), and M68 the plan settings. |

Not taken:
- **Codex S2's COPY test in the battery.** psql does not report a failed COPY's SQLSTATE, so the battery cannot capture it. COPY is refused by the same AFTER row trigger (executed directly).
- **Opus N3 (M53 is caught at APPLY).** The invariant pins the trigger exactly; R9, R9b and R9c are the behavioural tests.

## r4 results (author)

- Strict apply: the first run applies; the second is skipped on its marker.
- `battery-22.sql`: 154 PASS, including five runs with a VACUUM between each.
- `races/close-22.sh`: CR1–CR15 PASS, on two fresh clones.
- `mutations-22.py`: 68/68 caught (the runner VACUUMs the ledger before each battery).
- `tests/ci.sh`: all pass, 35 steps.
