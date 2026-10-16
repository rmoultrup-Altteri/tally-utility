# Opus review: v5.4.2-22 r4

**Date:** 2026-10-16. **Reviewer:** Opus. **Verdict: ready.**

My r3 blocking item (B1, the cap held only at the end of the tree) is closed, and so is my S1 (the upward walk's final join). I found no blocking item.

One should-fix item remains (S1). The new edges lock adds a deadlock with the close that the header does not state, and the header's reason for "no new cycle" is not quite true. Nothing is lost: PostgreSQL aborts one side. A header line is enough, though there is a cheap fix that removes it.

**Hashes verified (executed).** All four frozen files match the brief: patch `5228060d…`, battery `e01f02aa…`, close `8e49101d…`, mutations `4349c1e2…`. The brief's md5 is `a3b50614…`.

**What I ran (executed).**
- Clone and apply:
  - I cloned `rv22opus4` from `tally` and revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
  - I strict-applied the frozen patch twice. The second run skipped on its marker.
- Battery: **154 PASS**, including R10g and R12–R12e.
- `close-22-frozen-r4.sh rv22opus4`: the tail I captured shows CR4–CR15 PASS, CR13–CR15 included.
  - I did not capture the first lines (CR1–CR3).
  - A second run collides with the first run's committed fixtures, as expected.
- A randomized property test of the cap, described under "The cap" below.
- Two-session lock probes (S1) and a load timing (plans).
- I did not run `mutations-22.py`.
- The clone and every file I put in the container are gone.

Each claim is marked **[E]** (executed) or **[P]** (predicted or reasoned).

---

## Blocking

None.

---

## Should fix

### S1. The edges lock deadlocks with a close when the tenant row is locked strongly first. The header says this cannot happen. [E]

**What the header says.** "A change of the aging edges takes its tenant's head FOR SHARE … it holds the tenant row, and the close never locks the tenant row."

**Where the close does lock the tenant row.** It inserts `accounting_period_snapshot_lines`, which has `FOREIGN KEY (tenant_id) REFERENCES tenants(id)`. The RI check takes **FOR KEY SHARE** on the tenant row, after the close already holds the head FOR UPDATE.

FOR KEY SHARE does not conflict with a plain edges UPDATE, which takes NO KEY UPDATE. It does conflict with FOR UPDATE, which a transaction takes on the tenant row in two ordinary ways:
- it locks the row explicitly (`SELECT … FROM tenants … FOR UPDATE`), the usual way to edit a settings row safely;
- its UPDATE names a unique column in its SET list (`slug`), even unchanged. An ORM's "save all fields" does this. The lock mode depends on whether the column is in the target list, not on whether its value changes.

**Repro 1 (executed, two sessions):**
1. A: `BEGIN; SELECT 1 FROM tenants WHERE id = T FOR UPDATE;`
2. B: `close_accounting_period(Jan)`. B takes the head, then blocks on the snapshot lines' FK check behind A.
3. A: `UPDATE tenants SET receivables_aging_bucket_days = '{15,45}'`. The trigger asks for the head FOR SHARE, which B holds.
4. Result: **`deadlock detected`, A aborted.** B then closed.

**Control (executed).** I ran the same steps with `enforce_aging_edges_close_order` disabled on my clone:
- there was no deadlock; the close waited for A and then closed;
- February's snapshot kept the old edges, which is right, because A committed after the close's instant.

So r4 adds this cycle.

**Repro 2 (executed): one statement, an ORM-style save.**
1. A third session held the March period row, so that the close would stop between its head lock and its inserts.
2. B: close March. B takes the head and waits on the period.
3. A: `UPDATE tenants SET name = name, slug = slug, receivables_aging_bucket_days = '{15,45}'`. This locks the tenant row FOR UPDATE, then waits on the head.
4. The third session commits.
5. Result: B reaches its FK insert, and gets **`deadlock detected`, with the close aborted.**

In production the window is the whole close: aging a large tenant takes seconds.

**Integrity is untouched.** One side is aborted and nothing is written by it. This is a liveness issue, and the header claims a cycle-free order that does not hold.

**Fix, either of:**
- **(a) Header.** In the lock-order paragraph: "the close takes the tenant row FOR KEY SHARE (its snapshot lines' foreign key) after the head. A transaction that holds the tenant row FOR UPDATE (an explicit lock, or an UPDATE naming a unique column) and then changes the edges can deadlock with a close; one is aborted."
- **(b) Remove the cycle [P].** Snapshot lines already carry `period_id`. Reference the period by `(period_id, tenant_id)` instead of `tenants(id)`, if a matching unique key exists or can be added on `accounting_periods`. Then the close takes no tenant-row lock after the head.
  - `accounting_periods` and `accounting_close_heads` also reference `tenants`. The close only UPDATEs them, without changing `tenant_id`, so they take no RI lock.
  - A FOR KEY SHARE of the tenant row taken by the close *before* the head would also work, but it needs UPDATE on a tenants column for `tally_close`, which widens the seal. I would not do that.

A race test for this (Repro 1 as CR16) would pin whichever choice is made.

---

## Notes

**N1. The date-order rule can refuse a natural posting, with a workable alternative. [P]**

The case: an agency remits on Mar 20, but the write-off was dated Mar 31 at period end. A recovery dated Mar 20 is refused.

The correct entries exist:
- a payment dated Mar 20;
- a recovery dated on or after Mar 31 to undo the over-write-off.

Every legitimate shape I tried is admitted:
- a bounced recovery, then a replacement;
- a correction of a correction dated on or after what it corrects;
- same-date reversals;
- nested write-offs dated in order.

The refusal message names the rule. The core's documentation should say "post the write-off no later than the earliest money it recovers".

**N2. The 40001 rule: liveness. [P]**

An honest writer is refused only when another row under the same write-off commits between its transaction's start and its own post. The retry starts later and passes.
- Repeated refusal needs a write rate *under one write-off* that keeps up with the writer's transaction length. That is not a realistic load.
- A transaction holding the write-off's advisory lock from its first post keeps others out until it commits, so it is never refused twice within itself.

Two ways the rule can block for longer, both outside the threat model:
- **A superuser-loaded row with a future `created_at`** in a tree refuses every app writer under that write-off until the clock passes it. The same row would also hold off a close of its period (the r2 check). Only a superuser can do this, since `stamp_log_created_at` keeps the value only when `current_user` is a superuser.
- **A backward clock step** does the same until the clock catches up.

**The owner's kept `created_at` is not a hole [P].** A superuser row must still be recorded at or after every row in its tree, including the write-off itself (`l.id = v_wo.id`). Every recorded instant at or after it sees a state the cap checked, and every instant before it does not see the row.

I would add one line to R8 or R11: "a superuser's created_at in the future blocks writers under that write-off until then".

**N3. Test gaps. [P]**
- **No battery row admits a same-date tree whose rows, in some order, would cross the cap**, for example a recovery of +100, a reversal of −100 and a new recovery of +100, all on one date. The cap is right with the default RANGE frame (peers share a net). A mutation to `ROWS UNBOUNDED PRECEDING` would refuse such a statement depending on row order, and I expect it to survive the battery today.
- **R12e simulates the recorded order with the owner's `created_at`.** CR15 is the real two-session test, so the pair is complete. R12e's label could say "owner-stamped".

**N4. The planner settings are behaviour, not pinned. [E for timings, P otherwise]**
- **No invariant pins them.** `assert_periods_guard_invariants()` pins trigger definitions, not the functions' `proconfig`. An `ALTER FUNCTION … RESET enable_seqscan` passes the invariant. Only R10g's timing after a VACUUM catches it (M68).
  - This is consistent with how function bodies are treated elsewhere, and R11 states it.
  - Pinning `proconfig` for the two walk functions would be cheap: the invariant already reads `proconfig` for the seal.
- **Measured** after a VACUUM, in one transaction:

| Load | Time |
|---|---|
| 200,000 charges | 4.0 s |
| 5,000 reversals of them | **1.5 s** (was 51 s at r3) |
| 1,500 recoveries under one write-off, one row per statement (worst for the per-row window and the `created_at` scan, quadratic in tree size) | **1.9 s** |

- **The settings slow nothing else [P].** They apply only to the trigger function's own statements:
  - every one is an id, primary-key `ANY` or `idx_account_ledger_reverses` lookup;
  - `enable_*=off` still allows a scan where no index exists, so dropping `idx_account_ledger_reverses` would reintroduce scans, and that index is not pinned.
  - On PG 16.14 the setting adds a cost penalty rather than forbidding the plan.

---

## Answers to the brief

**Each r3 finding of mine is closed.**

| r3 item | Status | How I know |
|---|---|---|
| B1 (later-dated reversal makes room) | Closed | R12 refuses my repro on Feb 20 with net 200 [E]; property test below [E] |
| B1 related (recovery before its write-off) | Closed | R12b [E] |
| S1 (final join scanned the ledger) | Closed | the walk carries type and customer; 5,000 reversals in 1.5 s after VACUUM [E] |
| N1 (deadlock across write-offs) | Stated in the header | read |
| N2 (edges read without a lock) | Enforced; adds S1 above | CR13/CR14 [E]; S1 repros [E] |
| N4 (no upward-step mutation) | M56 re-anchored to `WHERE u.mine AND u.depth < c_max` | read |

**The cap at every (date, recorded instant).**

*Randomized property test [E].* I ran it four times, with seeds 0.11, 0.42, 0.77 and 0.93, 3,000 attempted inserts each, as `tally_app`.
- **What was inserted:** three customers, with random write-offs (30% nested under a tree row), recoveries, and adjustments, NSFs and payments naming random tree rows (10% of another customer). Dates were random over 60 days, and amounts ±20.
- **Outcomes per run:** about 1,550 admitted, 1,100 refused by the date rule, about 250 refused by the cap, and the rest refused as "only a recovery names a write-off".
- **Independent check:** a recursive query of my own, not the trigger's code. For every write-off and every date of its same-customer tree, the net of the rows dated on or before it is in [0, −amount], and every tree row is dated on or after its parent.
- **Result: 0 cap violations and 0 date violations in all four runs.** That covers about 2,200 tree rows and 1,270 write-offs.

*Recorded axis [P, reasoned; CR15 E].*
- Per write-off, rows are checked one at a time under its advisory lock, and each checker sees every committed tree row.
- The new rule makes `created_at` non-decreasing in check order. Ties are rows of one transaction, or of transactions that began in the same microsecond, and are seen together.
- So `{created_at ≤ t}` restricted to a tree is always a prefix of check order. That prefix is a state the last row in it checked at every date.
- The date rule and the recorded rule each make the visible part of a tree down-closed: a visible row's parent is visible. So aging never sees an orphaned reversal of the tree.
- This holds for a tree across statements or within one, and for nested write-offs, where a row under W2 walks to both and checks both.
- Rows of another customer are neither walked nor counted, by the cap or by aging. Both use the same rule: the parent must be the same customer.

**The date rule refuses nothing legitimate.** See N1.

**40001: provoked indefinitely, or bypassed?** No. See N2.

**The edges lock adds no unstated deadlock?** It adds one. See S1.

**The plan settings are safe?** Yes. See N4.

**2. Other paths around the rules.**
- The cap: none found [E: property test, R12–R12e].
- Periods, freeze, close order, snapshot, head and GL mappings: these are unchanged since r3 apart from the edges trigger. The battery and races cover them, and they pass [E]. I found nothing new [P].

**3. The seal.**
- r4 changes no grant of `tally_close`, and my r3 reading stands: the list is the least the close needs.
- The new trigger is invoker-rights and uses `tally_app`'s existing lock column on the head.
- The seal invariant passes in the patch tail [E].

**4. The snapshot.**
- The figures are unchanged since r3.
- The edges are those in force at the instant:
  - CR13b and CR14b [E];
  - my control run, in which the close kept the old edges because the change committed after its instant [E].

**5. The aging function.** It is unchanged since r3: correct, RLS-safe, with every coordinate required. The cap now matches what it nets at every coordinate (above).

**6. The invariants.** The new trigger is pinned [read]. The planner settings are not (N4).

**7. The tests.**
- 154 battery checks and CR4–CR15 pass [E].
- Gaps: a same-date admit (N3); a race for S1.
- M64–M67 target what their labels say [read].
- M68 depends on R10g's timing under a VACUUM, which the runner now performs.

**8. Residuals.**
- R8, as reworded, is now true.
- R10 and R11 are acceptable. I suggest one line in R11 for N2's superuser and clock case.
- None of R1–R11 is blocking.
