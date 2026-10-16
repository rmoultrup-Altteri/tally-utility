# Opus review: v5.4.2-22 r5

**Date:** 2026-10-16. **Reviewer:** Opus. **Verdict: ready.**

Each r4 finding is closed, and I found no new path around a rule. The future-time rule refuses only rows that would strand a write-off's tree. It keeps past times, and it changes nothing for rows outside a tree.

One should-fix item remains (S1). The lock-order paragraph still lists fewer deadlocks than the locks can produce. The r5 sentence covers an edges change after a tenant-row lock. But any write that takes the head after holding the tenant row FOR UPDATE deadlocks with a close the same way, and so does one that holds the closing user's row. I executed both. Nothing is lost, because PostgreSQL aborts one side. The fix is a header sentence.

**Hashes verified (executed).**
- The brief's md5 is `9197fc98…`.
- The four frozen files match the brief: patch `7e914bda…`, battery `a5369adf…`, close `59554ed2…`, mutations `8513d1d2…`.

**What I ran (executed).**
- Clone and apply:
  - I cloned `rv22opus5` from `tally` and revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
  - I strict-applied the frozen patch twice. The second run skipped on its marker.
- I ran `VACUUM ANALYZE account_ledger`, then the battery: **157 PASS**, R12f, R12g and R12h included.
- `close-22-frozen-r5.sh rv22opus5`: **CR1–CR15 PASS**, all 24 lines captured, CR15 with 40001.
- A probe file for the future-time rule and the invariant pins, run as the owner and rolled back (F1–F5 below).
- Two two-session deadlock probes (S1).
- I did not run `mutations-22.py`, and I did not re-run my r4 property test of the cap (see "The cap" below).
- I dropped the clone and removed every file I put in the container.

Each claim is marked **[E]** (executed) or **[P]** (predicted or reasoned).

---

## Blocking

None.

---

## Should fix

### S1. The lock-order paragraph is still narrower than the locks. [E]

**What r5 states.** A transaction that holds the tenant row FOR UPDATE and then *changes the edges* can deadlock with a close.

**What the close actually takes after the head:**
- the period row, FOR UPDATE (the withdrawal case is stated);
- the tenant row, FOR KEY SHARE, through `accounting_period_snapshot_lines_tenant_fkey`;
- the closing user's `users` row, FOR KEY SHARE, through `accounting_periods.closed_by` (set by the close's UPDATE) and `accounting_period_snapshots.closed_by`.

Any transaction that holds either row FOR UPDATE and then asks for the head can deadlock with a close. That covers every money write (the freeze trigger), every GL mapping write and every edges change, not just the edges change. `tally_app` has UPDATE on `users`, so an ORM save of a user row that names `email` takes FOR UPDATE.

**Repro A (executed): the closing user's row, then a plain posting.** On the race fixtures in my clone:
1. A, as `tally_app`: `BEGIN; SELECT 1 FROM users WHERE id = SUP FOR UPDATE;` then it sleeps.
2. B, as SUP: `close_accounting_period(August)`. B takes the head, then blocks on the `closed_by` FK check behind A.
3. A: `INSERT INTO account_ledger … DATE '2026-09-10', 'adjustment' …`. The freeze trigger asks for the head FOR SHARE.
4. Result: **A got `40P01 deadlock detected`** (while locking the tuple in `accounting_close_heads`, in `enforce_accounting_freeze`). B committed, and A's row is absent.

**Repro B (executed): the tenant row, then a plain posting (no edges change).**
1. A: `UPDATE tenants SET name = name, slug = slug WHERE id = T;` (FOR UPDATE, because `slug` is a key column in the SET list).
2. B: close September.
3. A: posts an adjustment dated 2026-10-10.
4. Result: **A got `deadlock detected`**, and B closed.

Repro B predates r4. It comes from the snapshot lines' tenant FK, which has been there since r1. My r4 S1 framed it through the edges trigger only, and so did the r5 sentence.

**Fix (header only).** Replace the r5 sentence with something like:

> "After the head, the close takes the tenant row and the closing user's row FOR KEY SHARE (the snapshot's keys and `closed_by`). A transaction that holds either row FOR UPDATE (a key column in its SET, an ORM save, an explicit lock) and then posts money, writes a GL mapping or changes the edges can deadlock with a close; PostgreSQL aborts one and nothing is written by it. Lock the tenant or a user row in a transaction of its own."

The current advice, "change the edges in a statement of their own", does not cover the money-write case.

I found no other cycle [P]:
- The close takes no advisory lock, no customer row, no GL mapping row and no other period row.
- A period insert takes its advisory lock and FOR KEY SHARE rows, but never the head.
- Writers' advisory locks come after their head share, which they hold already.

So with S1's wording, the stated deadlocks are all the ones the locks can produce:
- writers under two write-offs;
- a withdrawal followed by a write;
- the tenant row or the closing user's row held FOR UPDATE, followed by anything that takes the head.

A CR16 race (Repro B) would pin the wording.

### S2. No battery row admits a history row recorded in the past. [P for the mutation, E for the behaviour]

The brief asks that the future-time rule "cannot strand … a legitimate history load (past times are kept)". The behaviour is right [E, F1 below]. But every owner-stamped tree row in the battery is either refused (R12e, R12f, R12g) or a write-off at `now()`.

**Predicted survivor.** A mutation that refuses a write-off recorded in the past, such as `IF NEW.transaction_type = 'write_off' AND (v_future OR NEW.created_at < now())`, would survive the battery:
- no battery write-off has a past `created_at`;
- app write-offs are stamped `now()`, which equals the mutated bound.

R12e does catch the same mutation on the "row under" check, because its recovery is recorded at `now() − 1 minute` and would get 23514, not 40001.

**Fix.** Add one admit row: as the owner, a write-off recorded at 2024-01-01, then a recovery and its reversal at later past instants, one statement each. This is my F1a–F1c below.

---

## Notes

**N1. A history row recorded before its write-off gets 40001 "retry", but no retry can succeed. [E]**
- F1d below: the owner's recovery recorded at 2023, under a write-off recorded at 2024, is refused with 40001.
- The owner's `created_at` is fixed, so a generic retry loop spins until its cap.
- The same holds for a history load into a tree that already has later-recorded live rows.
- R12 says "in recorded order". One more clause would say why: "and not before a row already in the tree; 40001 there is final for a fixed created_at".

**N2. Wording. [read, E]**
- The `-infinity` refusal reads "is recorded in the future (-infinity)" (F2b). The refusal is right; only the message is off.
- `COMMENT ON FUNCTION enforce_write_off_recovery()` still begins "r3 … for a row naming an entry". It names neither the write-off firing nor the future-time rule.

**N3. A backward clock step can refuse an honest writer, with 23514, not 40001. [P]**
- A row stamped `now()` can exceed `clock_timestamp()` after a step back within the transaction.
- A retry after the step succeeds.
- This replaces r4's N2 superuser case, which r5 closes. It is outside the threat model.

**N4. The widened WHEN costs one trivial plpgsql call per write-off row [P].** It returns at once when the row names no entry.

---

## Answers to the brief

**Each r4 finding is closed.**

| r4 item | Status | Evidence |
|---|---|---|
| Codex B1 (a future-recorded tree row strands the tree) | Closed | R12f and R12g [E]. F2a (clock + 1 s) refused [E]; F2b (`-infinity`) refused [E]; F4 (a nested write-off at 2200 under a tree) refused [E] |
| Opus S1 / Fable S1 (the edges–close deadlock) | Stated, but too narrowly | S1 above [E] |
| Fable S2 / Opus N4 (plan settings not pinned) | Closed | F5a: `RESET enable_seqscan` on the recovery walk trips the invariant (0LP01) [E]. F5b: `SET enable_seqscan = on` on the lineage walk trips it [E]. F5c: an extra setting (`work_mem`) trips it, because the match is exact [E] |
| Codex S1 (a mixed-instant history batch) | R12 | stated; N1 |
| Opus N3 (a same-date admit) | R12h | [E] |
| Codex S2 (CR15's SQLSTATE) | CR15 requires 40001 | [E] |
| New WHEN pinned | Yes | F5d: the r4 WHEN, re-created ENABLE ALWAYS, trips the invariant [E] |

**The future-time rule strands no honest writer or legitimate load.** Probes as the owner, rolled back:

| Probe | Result |
|---|---|
| F1a: write-off recorded 2024-01-01 | admitted [E] |
| F1b: recovery recorded 2024-02 | admitted [E] |
| F1c: reversal of the recovery, recorded 2024-03 | admitted [E] |
| F1d: recovery recorded 2023, before its write-off | 40001 (N1) [E] |
| F1e: recovery at the default `now()` | admitted [E] |
| F2c: write-off at `clock_timestamp()` | admitted [E] |

App writers are stamped `now()` by `stamp_log_created_at`, unless the role is a superuser, and `now()` is never after `clock_timestamp()`. So the rule cannot refuse an app writer except in N3's clock case [read, P]. Battery and races pass [E].

**Rows outside a write-off tree are unchanged.**
- A charge recorded at 2200 is admitted (F3a), and so is an adjustment reversing it at 2200 (F3b) [E].
- A write-off recorded now that names the 2200 charge is admitted (F3c), because the charge is above the write-off, not in its tree [E].
- The second future check sits after the walk finds a write-off, so a reversal with no write-off above it never reaches it [read].
- The one new refusal outside an existing tree is a write-off that is itself recorded in the future. It would be a tree root, and that is the intended refusal.

**The cap.**
- r5 adds only the early `RETURN NULL`, for a row naming no entry, which the old WHEN never fired for, and the two future checks.
- The netting, the date rule and the recorded rule are unchanged [read].
- My r4 property test (about 2,200 tree rows, 0 violations) therefore still applies [P]. Battery R10–R12h pass [E].

**2. Other paths around the rules.** None found. Periods, the freeze, close order, the snapshot, the head and GL mappings are unchanged since r4 [read], and the battery and races pass [E].

**3. The seal.** r5 changes no grant. The seal invariant passes in the patch tail [E].

**4. The snapshot.** It is unchanged. CR7, CR13b and CR14b pass [E].

**5. The aging function.** It is unchanged since r4 [read].

**6. The invariants.**
- They now pin the WHEN and both walks' `proconfig` exactly [E, F5].
- The claim in the invariant's comment matches.

**7. The tests.**
- 157 battery checks and CR1–CR15 pass [E].
- M69, M70 and M72 target their labels [read]. M71 is caught at R10f, as stated [read].
- Gaps: S2 (an admit of a past-recorded history load), and a race for S1.

**8. Residuals.**
- R12 is right. N1 suggests one more clause.
- R1–R12: none is blocking.
