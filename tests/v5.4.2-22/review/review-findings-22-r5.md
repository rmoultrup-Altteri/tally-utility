# v5.4.2-22 review round 5: findings and dispositions (2026-10-16)

**Verdicts: Opus ready, Fable ready, Codex ready.** No blocking item.

- **Opus and Fable** executed their checks against their own clones: battery 157 PASS on a vacuumed ledger, CR1–CR15 PASS, plus their own probes (Opus F1–F5 and two deadlock repros; Fable A1–A6 and D1–D4).
- **Codex** reviewed the source. The author ran its eighteen probes on fresh clones of frozen r5. Each printed what Codex predicted. s1-head-upgrade needed a tenant the base lacks; re-run with one, in two sessions, it deadlocked as predicted (outputs appended to `codex-r5.md`).

Ryan's call (2026-10-16): fix the should-fix items now, as r6, and run one more round before the mirror. The default offered was to mirror r5 as reviewed and carry the fixes as follow-ups.

| # | Finding | Who | Disposition in r6 |
|---|---|---|---|
| 1 | The lock-order paragraph lists fewer deadlocks than the locks make. After the head and the period, the close takes FOR KEY SHARE on the tenant row (snapshot keys) **and on the closing user's users row** (`closed_by`). Any transaction holding either row FOR UPDATE that then takes the head (a money write, a GL mapping write, an edges change) deadlocks with a close, not only an edges change. | Opus S1 (executed: users row + posting; tenant row + posting), Fable S1 (executed: three shapes and a control) | **Stated in full** in the lock-order paragraph and the close's comment, with the advice "change tenant and user rows in a transaction of their own". The paragraph now ends with the complete list of cycles. Races **CR17** (tenant row, then a posting) and **CR18** (the closing user's row, then a GL mapping write) pin it. |
| 2 | Two transactions that each post and then close deadlock: each holds the head FOR SHARE and asks for it FOR UPDATE. "Writers never wait for each other" overstated the advisory locks. | Codex S1 (reproduced by the author in two sessions) | **Stated**, with "close in a transaction of its own". "Writers do not wait for each other at the head". Race **CR16**. |
| 3 | "Change the edges in a statement of their own" should say transaction | Fable S2 | Replaced by the transaction advice in 1. |
| 4 | A history row with a chosen recorded time before a row already in its tree gets 40001 "retry it", but no retry can change its time | Opus N1 | **Refused for good, 23514**, when `created_at` is not the transaction's start (`<> now()`). A row stamped at its transaction's start still gets 40001, and its retry is stamped later. R12 updated. Battery R12e (now 23514) and **R12i** (the 40001 case, a write-off at `clock_timestamp()` then a default-stamped recovery). Mutations **M75** and **M76**. |
| 5 | No battery check admits a history load recorded in the past | Opus S2 | **R12k**: a write-off, recovery and reversal at 2024 instants, one statement each, then a live recovery; the stored time is kept. Mutation **M74** (refuse a past-recorded write-off). |
| 6 | The `isfinite` leg has no catching test (infinity is also after the clock) | Fable N1 | **R12j** (a write-off at `-infinity`). Mutation **M73** (drop the leg). |
| 7 | The message says "in the future" for `-infinity`; the function's comment predates r5 | Opus N2, Codex S2 | Messages read "recorded at a non-finite or future time". The comment names the write-off firing, the time rule and the r6 refusal. |
| 8 | Nested write-offs, A→B→A and the 1,000 bound are probes, not maintained checks; a deeper future row and an app writer's supplied infinity are untested | Codex S2 (r4 and r5) | **R11b/R11c** (exactly 1,000 admitted; the 1,001st refused), **R12n** (inner and outer caps), **R12o** (a walk that leaves the customer and returns), **R12l** (a deeper row at 2200), **R12m** (tally_app's infinity stamped `now()`). Mutations **M77** (only the outermost write-off capped), **M78** (the bound one short), **M79** (the tree walks past another customer's row). |
| 9 | CR15 orders its sessions by sleeps; the race header says every leg is seen blocked | Codex S2 (r4 and r5) | CR15 uses barriers (`application_name` signals, polled in `pg_stat_activity` with its snapshot cleared each poll). The header names which legs are seen blocked and which use barriers. |
| 10 | R9b's label says "the adjustment first", which a writable CTE's text order does not promise | Codex S2 (r4 and r5) | Relabeled. |

Not taken:
- **Rerouting the close's FKs** (snapshot tenant key, `closed_by`). Neither Opus nor Fable proposed it; it changes the snapshot tables' keys.
- **Opus N3, a backward clock step can refuse an honest writer (23514).** Outside the threat model; a retry after the step succeeds.
- **Codex N1, rows already in the base before -22.** Probe n16 found none at a non-finite or future time; DEPLOY-VERIFICATION will repeat the check on the real database.

## r6 results (author)

- Strict apply: the first run applies; the second is skipped on its marker.
- `battery-22.sql`: 166 PASS on a vacuumed ledger.
- `races/close-22.sh`: 28 PASS (CR1–CR18), three runs on fresh clones.
- `mutations-22.py`: 79/79 caught (M73–M79 each at its named check).
- `tests/ci.sh`: all pass, 35 steps.
