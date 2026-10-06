# v5.4.2-16 review round 2: findings and dispositions

**Frozen:** patch `24998853`, battery `ef1c7da0`. Brief: `review-brief-16-r2.md`. Reviews: `review-r2-{opus,fable,codex}.md`.
**Verdicts:** all three "not yet", each on one blocking item. The three converge on the same one. Every round-1 fix held; Opus and Fable attacked each of them, and Codex reviewed each statically.

| # | Finding | Who | Disposition |
|---|---|---|---|
| **N1** | The time-zone lookup reads both axes and takes `ORDER BY specificity LIMIT 1`. Equal-specificity candidates with different zones then give an arbitrary answer. Reproduced: two counties on two axes; an annexation window with one city on each axis. | **all three** | **Integrity.** Refuse when the most specific candidates disagree. Agreeing duplicates are fine. Counties stay per axis: a tax authority and a regulator may record a boundary differently, and the lookup refuses that disagreement. |
| N2 | A city owning service in another state cannot record a premise there as outside the city, with a distance. | Codex | **None** (no source: the distance laws in hand, KS 66-104f and NM 3-25-3, measure from a city of the same state). An outside relation is to a place of the premise's state; residual R16. |
| S-a | A jurisdiction pointer can name a place that is already scheduled to close. | Opus | **Integrity.** An undated pointer needs an open place. |
| S-b | A membership or profile wrong from its first day can never be corrected for that day. | Opus (Codex noted backdating) | **Integrity, settled now** (it changes what readers filter, so it is costly later). A stamped **void**, once, with a reason. Voided rows are ignored by the exclusions, the lookups, the state guard and the close floor. |
| S-c | "Unincorporated" cannot be recorded, though §7.45 applies "in unincorporated areas". | Opus | **Source.** An `unincorporated_area` kind in the municipal-status group, one per state, with Texas seeded. |
| S-d | A profile can name a state with no state place (`QQ`), and the lookup answers. | Codex | **Integrity.** A profile's state is a state place in force over its range. |
| S-e | Numeric facts have no range (sales tax 5, population −3); distance and evidence dates are unbounded. | all three | **Integrity.** Fact kinds declare `value_min` and `value_max`. Distance must be finite. Evidence is dated no later than the day it is recorded. |
| S-f | `Etc/GMT+6` passes the zone check. | Opus | **Integrity.** `Etc/` zones are refused. |
| S-g | `fact_key` is not normalised (`'HB 1'` and `'HB 1 '` coexist). | Fable | **Integrity.** Keys carry no surrounding whitespace. |
| S-h | Changing a premise's state is now pinned to READ COMMITTED even with no memberships. | Opus | **Stated** in the header. Only a change of the normalised state is pinned. |
| S-i | A county's FIPS prefix is not tied to its state. Each place has one code, but loads will come from two publishers. | Opus | **None yet.** Residual R17: loaded by reviewed migrations from Census; alternate publisher codes become a place fact when a loader needs them. |
| S-j | A membership share-lock followed by a state update, in two transactions, can deadlock. | Opus | Residual R18. PostgreSQL detects it and aborts one; the writer retries. |
| T | Test gaps. Opus: 11 of 16 extra mutations survived. Fable: 10 of 18 missed, 6 of them real. Codex: discriminating cases. Also: the jurisdiction lock has no race leg; races rely on sleeps. | all three | Cases and mutations added for each named gap. Races R10–R11 cover the jurisdiction pointer in both orders. Race legs now **assert that the second session was observed waiting** (`pg_stat_activity`), not just its final message. |
| — | `mutations-16.py` hard-codes its database; the battery's role name could collide | Fable | A note: harness runs are serial. |

## Revision for round 3

Every item above is folded or recorded (residuals R16–R18).

**Verified on patch `c49b1ec5`, battery `af1013f9`** (clones with TEMP revoked):
- strict apply ×2;
- battery-16 **68/68** (group N covers round 2);
- races **R1–R12**, each two-session leg with the wait observed;
- mutations **110/110**, each caught at its named check (M81–M111 for round 2);
- regressions 28/58/41/116/3/99/6, and -13's X1.

One test was sharpened while doing this: N4e now re-voids a voided row, the only edit that the frozen-after-void rule alone refuses.
