# v5.4.2-22 review round 6: findings and dispositions (2026-10-16)

**Verdicts: Opus ready, Fable ready. Codex not run:** it hit its usage limit (reset 4:01 PM) before writing anything.

- **Opus and Fable** executed their checks against their own clones: battery 166 PASS on a vacuumed ledger, CR1–CR18 (28 PASS), plus their own probes (Opus L1–L4; Fable P1′–P3d).

| # | Finding | Who | Disposition in r7 |
|---|---|---|---|
| 1 | The lock-order paragraph's "these are the cycles" list is incomplete. The close takes, in order, the head, the period, the closing user's row (KEY SHARE) and, when it writes lines, the tenant row (KEY SHARE). Missing cycles: the period row locked (tally_app may take FOR SHARE or FOR KEY SHARE) then a money write; the tenant row then the closing user's row; either of those rows then a withdrawal. | Opus S1 (executed, both lock modes), Fable S1 (executed, three shapes and a reverse-order control) | **The paragraph states the rule, not a list**: the close's four rows in order; a transaction that holds a later one in a conflicting mode and asks for an earlier one (or holds the head FOR SHARE and then closes) can deadlock with it. It names what takes each row, and lists the shapes executed as examples. The author added the advisory-lock cycles the old sentence left out: a period insert or withdrawal and a posting under a write-off, in opposite orders. Races **CR19** (the period row FOR SHARE as tally_app, then a money write) and **CR20** (the tenant row, then the closing user's row; no head on that side). |
| 2 | R12i's 40001 can never succeed on retry: the later row is the transaction's own write-off, recorded at `clock_timestamp()`. Only the owner can reach this. | Opus S2 (executed twice, and the committed-first control) | **Stated in R12** (a row its own transaction recorded at a chosen time; the owner only). R12i relabeled: it shows the retry signal, and CR15 shows a retry succeed. *Not taken:* refusing this case for good in code (23514 when the later row is the transaction's own). It is reachable only by the owner, and telling "its own" apart needs subtransaction-aware xmin tests. |
| 3 | An UPDATE that names a unique column locks the row FOR UPDATE even when the value is unchanged; `users.tenant_id` is under a unique index | Opus N1 (executed) | The paragraph says "an UPDATE whose SET names a column under a unique index, changed or not", and lists users: id, tenant_id, cognito_sub; tenants: id, slug. The list was checked against `pg_index`. |
| 4 | Mutation M71 (rows of one date netted one by one) was caught at R10f in r6's run and at R12h in r7's: those checks fail under a row-by-row net only for some orders of their same-date rows, and the order is not fixed | Author (r7 mutation run, 78/79) | **R5b**, placed before every order-dependent check: a +150 recovery and its −50 reversal on one date, against 100 written off, net 100 together, but every order has a partial sum outside 0 to 100. M71 is named R5b; caught three runs out of three. M54 (the cap counts direct rows only) is now caught first at R5b too, whose −50 row is one level down: renamed to R5b. |
| 5 | A close of a period with no ledger rows writes no line and never takes the tenant row | Fable N1 | The rule says "when it writes snapshot lines"; CR20's period has a ledger row. |

Not taken:
- **Opus N2, a mutation for the recovery walk's own depth bound.** Low value: the lineage bound (M78) is the one that binds first.

## r7 results (author)

- Strict apply: the first run applies; the second is skipped on its marker.
- `battery-22.sql`: 167 PASS on a vacuumed ledger.
- `races/close-22.sh`: 30 PASS (CR1–CR20), three runs on fresh clones.
- `mutations-22.py`: 79/79 caught (78 in the full run; M54, then caught first by the new R5b, renamed to it and re-run caught).
- `tests/ci.sh`: all pass, 35 steps.
