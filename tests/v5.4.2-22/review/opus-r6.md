# Opus review: v5.4.2-22 r6

**Date:** 2026-10-16. **Reviewer:** Opus. **Verdict: ready.**

r6 closes my r5 items: S1 (the lock-order paragraph), S2 (an admit of a history load recorded in the past), N1 (the 40001 that no retry fixes) and N2 (wording). I found no path around a rule, and no blocking item.

Two should-fix items remain. Both are wording or labels, and neither loses data or admits a bad row.
- **S1.** The lock-order paragraph says it lists every cycle, but it misses one I executed: a transaction locks the period row in any mode, then writes, while a close of that period runs.
- **S2.** R12i's shape gets a 40001 that no retry can fix. R12's new sentence ("its retry is stamped later") does not hold for that shape.

Each claim is marked **[E]** (executed) or **[P]** (predicted or read).

**Hashes (executed).**
- The brief's md5 is `11459967833917fa87fcc14c511ab08e`.
- The four frozen files match the brief: patch `b3a3c982…`, battery `70b1003c…`, close `512cf9c9…`, mutations `06f6f920…`.

**What I ran (executed).**
- I cloned `rv22opus6` from `tally` and revoked TEMP from PUBLIC, `tally_app` and `tally_core`. Afterwards `has_database_privilege(…, 'TEMP')` was false for both roles.
- I strict-applied the frozen patch twice. The second run skipped on its marker, with the NOTICE "already applied (accounting_periods exists)".
- I ran `VACUUM ANALYZE account_ledger`, then the battery: **166 PASS**, rc 0.
- `close-22-frozen-r6.sh rv22opus6`: **28 PASS lines, CR1–CR18**, rc 0. I ran it once.
- I ran probes L1–L4 (below) on my own tenant in the clone.
- I did not run `mutations-22.py`. I read M73–M79.
- I dropped the clone and removed my files from the container.

---

## Blocking

None.

---

## Should fix

### S1. One more cycle: the period row locked in any mode, then a write. [E]

The paragraph now ends: "These are the cycles -22's locks can make: writers under two write-offs; a withdrawal then a write; the tenant or a users row held FOR UPDATE then the head; and a write then a close." It also says the close takes no "other period row". That is true, but the close does take *its own* period row FOR UPDATE, after the head. Any lock on that row conflicts with FOR UPDATE, FOR KEY SHARE included.

`tally_app` holds UPDATE on `accounting_periods(status, withdrawn_at, withdrawn_by)`, so it may run `SELECT … FOR SHARE` and `FOR KEY SHARE` on a period. "Lock the period to check that it is open, then post" is a natural application pattern.

**Repro (executed; my tenant in the clone, periods Feb and Mar).**
1. A, as `tally_app` (operator): `BEGIN; SELECT id FROM accounting_periods WHERE id = FEB FOR SHARE;` then `pg_sleep(2)`.
2. B, as `tally_app` (supervisor), one second later: `close_accounting_period(FEB)`. B takes the head FOR UPDATE, then waits on A for the period row.
3. A posts an adjustment dated 2026-03-10. The freeze trigger asks for the head FOR SHARE.
4. Result: **B got `40P01 deadlock detected`**, and A posted and committed.
5. The same shape with `FOR KEY SHARE` on March, posting on 2026-04-10: **B got 40P01** again.

**Fix.** This is wording only. Change "a withdrawal then a write" to something like: "the period row locked (a withdrawal, or SELECT … FOR SHARE / FOR KEY SHARE / FOR UPDATE) then a write; lock or withdraw a period in a transaction of its own". A race like CR17, with the period row FOR SHARE, would pin it.

I checked the other rows the close touches after the head [P, read]:
- the head itself;
- its period row (FOR UPDATE, and KEY SHARE from the snapshot's FK);
- the tenant row (KEY SHARE, from the snapshot lines' FK);
- the closing user's row (KEY SHARE, from `closed_by` on the period and on the snapshot);
- the new snapshot rows.

The close's UPDATE of the head does not change `tenant_id`, so it runs no FK check. No app table has an FK to `accounting_periods`. A period insert reads the chain but locks no period row. So with S1, the list is complete.

### S2. R12i's 40001 can never succeed on a retry. R12's new sentence is narrower than it claims. [E]

**What R12i does.** As the owner, in one transaction, it posts a write-off with `created_at = clock_timestamp()`, then a recovery with the default stamp (`now()`). Its label says this is "a writer that began earlier: it retries". The comment above it says the same.

**What actually happens.** The "later" row is the transaction's *own* write-off. A retry re-runs the same pair, picks `clock_timestamp()` again, and stays after the new `now()`.
- **L3 [E]:** I ran R12i's shape twice, as two transactions. Both got **40001 "retry it"**.
- **L4 [E]:** I committed the same write-off first, in a transaction of its own, then posted the recovery as `tally_app` in a later transaction. It was **admitted**.

So the 40001 is final whenever the row recorded after it was written by the same transaction. R12 now says "Only a row stamped at its transaction's start gets 40001, and its retry is stamped later". That is true, but the retry does not succeed in this shape.

Only the owner can reach it, because app writers' `created_at` is always `now()` (R12m [E]). An honest app writer can never be refused for good (see Q2). So this is not blocking, but it is exactly the "retry forever" the brief asks about.

**Fix (pick one).**
- **(a) Wording only.** Relabel R12i as "a stamped row before a chosen-time row of its own transaction: 40001, which no retry fixes; post the chosen-time row in a transaction of its own". Add the same clause to R12.
- **(b) Code.** Also raise 23514 when the later row is the transaction's own, for example when its `xmin` is in progress and visible (only the current transaction's rows are). Keep 40001 for a later row committed by another transaction. This needs a battery row for each side, and a mutation.

I recommend (a). The case is owner-only, and (b) adds machinery to a hot trigger.

---

## Notes

**N1. "An UPDATE that changes a column under a unique index" understates the trigger for FOR UPDATE. [E]**
- I held each UPDATE open in session A and asked for `FOR KEY SHARE NOWAIT` on the tenant row from session B.
- `SET name = name` let B's lock through. `SET name = name, slug = slug` (value unchanged) refused it, so A held FOR UPDATE.
- So an UPDATE that **names** a unique column can take FOR UPDATE, even when the value does not change. An ORM full-row save is the common case.
- The list should also include `users.tenant_id` (under `users_id_tenant_id_key`).
- The advice ("change tenant and user rows in a transaction of their own") covers all of this, so only the parenthesis needs changing.

**N2. The recovery walk's `u.depth < c_max` has no mutation of its own [P].** M78 mutates the lineage function's `c_max`, which is the binding bound. The recovery walk's bound cannot bind while the lineage bound holds. This is low value; I list it only for completeness.

---

## Answers to the brief

**1. Inventory and rulings.** Nothing in r6 changes a requirement. I found nothing missed or half done [read]. My r5 answer stands.

**2. Paths around a rule.**
- **The 23514/40001 split.**
  - App writers are stamped `now()`, so `created_at <> now()` is never true for them. An honest app writer can only get 40001, and it succeeds on a retry once the other transaction has committed (CR15/CR15b [E], L4 [E]).
  - A chosen-time row gets 23514, unless the chosen value equals the transaction's start exactly. That is the same as a stamp, and on a retry the literal no longer equals `now()`, so it gets 23514 then.
  - The one retry-forever shape is S2.
- Nothing else in r6 touches money, periods, the head, snapshots or GL mappings [read the diff]. The battery and races pass [E].

**3. The seal.** r6 changes no grant [read the diff]. The patch-tail invariants passed on apply [E].

**4. The snapshot.** It is unchanged. CR7, CR13b, CR14b and CR16b pass [E].

**5. The aging function.** It is unchanged [read].

**6. The invariants.** They are unchanged, and they passed on apply [E].

**7. The tests.**
- **New checks [read, E].**
  - R11b and R11c are caught by M78 at R11b.
  - R12e (23514), R12j (`-infinity`), R12k (history admitted, times kept, a live row follows), R12l, R12m, R12n (inner and outer caps, each asserting the write-off its message names) and R12o each target their labels.
  - R12i's label overstates what it shows (S2).
- **Races [read, E].**
  - CR15 is now ordered by barriers.
  - CR16 makes both sessions post before either closes.
  - CR17 and CR18 have A wait until B is blocked on A (`await_blocked`) before A takes the head.
  - `deadlock()` requires exactly one side to fail with 40P01 and the other to commit.
  - Each pins the shape its label names.
- **Mutations [read].** Each is caught for the right reason:
  - M73 makes `-infinity` pass, so R12j is admitted.
  - M74 refuses R12k's 2024 write-off.
  - M75 turns R12e into a 40001.
  - M76 turns R12i into a 23514.
  - M77 caps only the outermost write-off, so the inner overflow is admitted and R12n raises its own message, not the sentinel.
  - M78 refuses the chain of exactly 1,000.
  - M79 lets the walk go through C1, so the +500 under it joins C5's tree and R12o is refused.
- **Missing.** A race for S1. A check whose label matches R12i's actual shape.

**8. Residuals.** R1–R12: none is blocking. R12 needs S2's clause.
