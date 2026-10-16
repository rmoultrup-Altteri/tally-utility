# v5.4.2-22 review round 2 — findings and dispositions (2026-10-15)

Verdicts: **Opus not yet, Fable ready, Codex not yet.** Opus and Fable executed against their own clones. Codex reviewed the source; the author ran its eleven probes on a clone of the frozen r2 patch, and each blocking prediction reproduced (outputs appended to `codex-r2.md`). Codex's n7 probe reported "COPY accepted" although the COPY was refused: a defect in the probe's error capture, not the patch. The fixes go into r3.

| # | Finding | Who | Disposition in r3 |
|---|---|---|---|
| 1 | A row naming a write-off, listed **before** that write-off in the same statement (VALUES, writable CTE, owner COPY), is accepted: the BEFORE trigger cannot see a later row. A recovery on top then reinstates past the cap (150 of 50; 600 of 100) | Codex B1, Opus B1a (two reviewers converging) | The whole rule moves to an AFTER INSERT row trigger, `enforce_write_off_recovery`, which sees every row of the statement. The recovery's own checks (names a write_off of its own customer, opposite sign) move with it. Battery R9 (VALUES) and R9b (CTE); R9c admits a recovery listed before its write-off. |
| 2 | A row naming the **recovery** (not the write-off) is uncapped and nets into the write-off's tree (+700 against 100) | Opus B1b | The cap is on the **net of the write-off's whole same-customer tree**, at any depth and of any type, between 0 and the amount written off. It is checked for every write-off above the new row, behind each write-off's advisory lock, in id order, at READ COMMITTED. Battery R10, R10b; race CR11. |
| 3 | The cap counts recoveries gross: a recovery reversed in error still consumes it, and the real recovery is refused | Fable S1 | Closed by #2: the net counts the reversal. Battery R10c–R10e (reverse a 40 recovery, then recover the whole 100, not a cent more). |
| 4 | The loop walk stops at depth 10,000 without refusing: a 10,001-row ring is accepted, and afterwards aging and the close raise for that tenant | Codex B2 | The walk fails closed. A chain that has not reached an original within 1,000 entries is refused: it is too long, or it enters a loop. The bound is lowered from 10,000 to 1,000 so a test can cross it cheaply; real reversal chains are a few entries. Battery R11 (a 1,001 ring); Codex's 10,001 ring is now refused at insert. |
| 5 | An operator chooses the edges the close uses, through a `manual` history row; the snapshot then disagrees with the tenant's setting | Opus S1 | The close reads `tenants.receivables_aging_bucket_days`, the tenant's setting at its own instant, not the app-written history (memory "app-written logs are not guards"). `tally_close` loses SELECT on the history and EXECUTE on `receivables_aging_bucket_days_as_of`, and gains SELECT on `tenants(id, receivables_aging_bucket_days)`; the seal list follows. Battery C16b. The 3-argument aging still reads the history: residual R10. |
| 6 | Any operator can withdraw a period; `withdrawn_by` can be NULL | Opus S2 (Fable N7: consistent) | **A withdrawal names its user** (raises without `app.user_id`). **It stays an operator's act.** Under "guard the act": creating a period is an operator's act, and a withdrawal of the latest open period is undone by creating the same period again. The close is gated because it is irreversible; a withdrawal is not. Battery P9f. |
| 7 | The snapshot table's comment and battery C12 still use the 3-argument aging | Codex S1 | The comment names the 4-argument form with the stored edges; C12 reproduces with `s.aging_bucket_days`. |
| 8 | The invariant does not pin the history's known-key CHECK, the not-self CHECK or the reversal FK; its comment says "every -22 constraint" | Codex S2, Fable N3, Opus N4 | All three are pinned by exact definition. The comment now says "the constraints named here" and states that the snapshot tables' keys are not pinned. M61 drops the known-key CHECK and is caught at apply. |
| 9 | Missing tests: statement order, the depth bound, writable-CTE and COPY loops, races | Codex S3 | R9–R11 above, plus CR11 (cap race through a recovery) and CR12 (close waits on a withdrawal, then is refused as withdrawn). The writable-CTE loop was already R8's shape (Fable, Codex n6 executed); owner COPY of a loop is refused (Codex n7 executed). |
| 10 | The mutation runner's label match `[a-z]?` accepts a suffixed check for an unsuffixed label | Codex S3 | Exact label match now. |
| 11 | Withdrawal then money in one transaction, against a close of that period, deadlocks (detected, one side aborted) | Opus N1 | Stated in the header's lock order, with the advice to withdraw in a transaction of its own. |
| 12 | Closing a withdrawn period says "already closed" | Opus N2, Fable N1 | It says "is withdrawn". Battery C13b. |
| 13 | The seal invariant's comment says only `tally_close` writes a period's status; a `closed_by` grant to `tally_app` would pass | Opus N3, Fable N7 | The comment names the close's columns and the application's withdrawal; the invariant also refuses `tally_app` UPDATE on `closed_by`. |

Not taken:
- **Opus S2's supervisor gate for withdrawal** (see #6). A two-reviewer disagreement, settled by the standing rule.
- **Opus S1's alternative of refusing `manual` history rows for this key.** The history's manual source is the base design for every key. The close no longer reads it, and the snapshot stores its edges. Stated as residual R10.
- **Fable N4 (M48 caught by a CHECK before the trigger clause).** The label holds. The CHECK is a second guard on the same act.
- **Fable N5 (a lexical check that the instant follows the lock).** CR1 shows the behaviour: a close waits for a posting in flight and counts it.
- **Codex's n7 probe defect.** It was in the probe, not the patch.

## r3 results (author)

- Strict apply twice: the first applies, the second is skipped on its marker.
- `battery-22.sql`: **147 checks**, all PASS (135 r2 checks unchanged except C12's reproduction, plus R9–R11, P9f, C13b, C16b).
- `races/close-22.sh`: CR1–CR12, all PASS.
- Codex's r2 probes against r3: b1 refused ("only a write_off_recovery names a write-off"); b2's 10,001 ring refused at insert ("does not reach an original within 1000 entries"); n6 loops refused; s2's dropped CHECK caught (0LP01).
- `mutations-22.py`: see the r3 brief.
