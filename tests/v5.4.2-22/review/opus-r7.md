# Opus review: v5.4.2-22 r7

**Date:** 2026-10-16. **Reviewer:** Opus. **Verdict: ready.**

r7 folds my round-6 items. S1 (the missing cycle) is now covered by a stated rule, and S2 (R12i's 40001 that no retry fixes) is now stated in R12 and in R12i's label. I found no path around a rule, and nothing blocking.

Two should-fix items remain. Both are wording in the lock-order paragraph. Neither loses data or admits a bad row: in each case PostgreSQL aborts one side, and that side writes nothing.
- **S1.** One UPDATE statement deadlocks with a close by itself: it changes the aging edges and names `slug` in its SET. So the advice "change tenant rows in a transaction of its own" does not avoid that shape.
- **S2.** The rule is stated for two transactions. A three-transaction cycle exists in which neither party matches it. The transaction aborted in it is a plain writer that did nothing the paragraph warns against.

Each claim is marked **[E]** (executed) or **[P]** (predicted, or read in the source).

**Hashes [E].**
- The brief's md5 is `126b6456b744ad3a8fd87003b6fcf227`.
- The frozen files match the brief: patch `5c972f8f…`, battery `45b95d5c…`, close `58886f4c…`, mutations `aac49900…`.

**What I ran [E].**
- I cloned `rv22opus7` from `tally`, then revoked TEMP from PUBLIC, `tally_app` and `tally_core`. Afterwards `has_database_privilege(…, 'TEMP')` was false for both roles.
- I strict-applied the frozen patch twice. The second run skipped, with the NOTICE "already applied (accounting_periods exists)".
- I ran `VACUUM ANALYZE account_ledger`, then the battery: **167 PASS**, rc 0. R5b passed on its sentinel.
- `close-22-frozen-r7.sh rv22opus7`: **30 PASS lines, CR1–CR20**, rc 0. I ran it once.
- I ran probes E3/E4 (the edges change) and T3 (three parties) on tenants of my own.
- I queried column privileges for every `tally_*` role on the four rows the close takes.
- I did not run `mutations-22.py`. I read the two r7 changes, M54 and M71 retargeted to R5b.
- I dropped the clone and removed my files from the container.

---

## Blocking

None.

---

## Should fix

### S1. An edges change that names `slug` deadlocks with a close in one statement. [E]

`tally_app` holds UPDATE on every column of `tenants`, `slug` and `id` among them. Consider an UPDATE that changes `receivables_aging_bucket_days` and also names `slug`. An ORM full-row save does this, even when the slug value is unchanged.
1. The UPDATE locks the tenant row FOR UPDATE first: the BEFORE trigger's lock mode follows the named columns.
2. Then `enforce_aging_edges_close_order` asks for the head FOR SHARE.

That is "a later row, then an earlier one", inside one statement.

**Repro (executed; my tenant, January with one ledger row).**
1. C (owner): `SELECT … FROM users WHERE id = SUP FOR UPDATE`, held for 4 s. This parks the close at its step 3, holding the head and the period.
2. B (`tally_app`, supervisor), at t=1 s: `close_accounting_period(JAN)`.
3. A (`tally_app`), at t=2.5 s: `UPDATE tenants SET slug = slug, receivables_aging_bucket_days = '{30,60,90}' WHERE id = T;`
4. **B got 40P01.** It was blocked "while locking tuple … in relation tenants … FOR KEY SHARE", from the snapshot-lines INSERT. A committed, and the period stayed open.
5. **Control (E4):** the same run with `SET receivables_aging_bucket_days = '{30,60,90}'` only. A waited for the close, and the close committed. There was no deadlock.
6. With the edges value unchanged, the trigger takes no head, so there was no deadlock either (E1/E2).

**Where the paragraph falls short.**
- The rule covers this shape: the transaction holds row 4 and asks for row 1.
- The paragraph's advice does not avoid it. "close, withdraw, and change tenant and user rows each in a transaction of its own": this UPDATE *is* a transaction of its own.
- It is not among the listed shapes.

**Fix (wording).** Add a shape, "an edges change whose SET also names a key column (one statement)". Add the advice "change the edges in an UPDATE that names no other column under a unique index".

### S2. The rule is pairwise; a three-party cycle falls outside its wording. [E]

The rule says a transaction "that holds one of these rows … and then asks for a row the close takes earlier" can deadlock with a close. In a longer chain, the transaction holding the later row and the one asking for the earlier row can be different transactions, joined by an ordinary row wait.

**Repro (executed; my tenant).**
1. A (`tally_app`, operator): `SELECT … FROM accounting_periods WHERE id = JAN FOR SHARE`.
2. D (`tally_app`), at t=0.5 s: `UPDATE customers SET notes = 'D' WHERE id = C`.
3. B, at t=1 s: `close_accounting_period(JAN)`. It takes the head, then waits on A for the period.
4. D, at t=3 s: posts an adjustment dated 2026-02-03. It waits on B for the head.
5. A, at t=4 s: `UPDATE customers SET notes = 'A' WHERE id = C`. It waits on D.
6. Result: **D got 40P01**, a three-process cycle on the head tuple. A and B committed, and January closed.

Neither party matches the rule:
- D asks for the head but holds no row the close takes.
- A holds the period but asks for a customer row.

The victim, D, did an UPDATE of a customer and then a money write. Nothing in the paragraph warns against that. "Writers retry 40P01" covers it, and A is in a listed shape (the period row locked, then more work). So the advice still avoids the cycle; only the rule's wording is narrower than "the rule they follow".

**Fix (wording).** "…and then waits, directly or through other transactions, for a row the close takes earlier".

---

## Notes

**N1. "What takes the rows" is incomplete for `tally_app`'s explicit locks. [E for the grants, P for the shapes]**
- `tally_app` holds UPDATE on `accounting_close_heads(updated_at)`, so it may run `SELECT … FOR UPDATE` or `FOR SHARE` on the head. The paragraph lists "FOR UPDATE: a close" only.
- On the period, `tally_app` may also take FOR UPDATE and FOR NO KEY UPDATE, not only FOR SHARE and FOR KEY SHARE.
- None of these adds a cycle outside the rule: the head is row 1, and the period is row 2.

The other roles [E, from the grants]:
- `tally_core` holds no UPDATE on these four tables, so it cannot lock them.
- `tally_void` holds UPDATE(`updated_at`) on the head. It uses it for its own money writes (head FOR SHARE), which are already listed.
- `tally_close` is the close itself.
- The owner can do anything.
- The only FK to `accounting_periods` is the snapshot's, and only the close writes snapshots.

So, with N1 added, the list is complete for the roles that exist.

**N2. CR17 and CR20 take the tenant row as the owner.** Their labels are about the row, so they are accurate. S1's probe shows that `tally_app` can reach the same lock [E].

**N3. The control shape is confirmed [E].** A plain edges change, against a close parked at step 3, waits and does not deadlock (E4). This matches the paragraph: an UPDATE that names no key column takes NO KEY UPDATE on the tenant row, which does not conflict with the close's KEY SHARE.

---

## Answers to the brief

**1. Inventory and rulings.** r7 changes comments only [read the diff]. Nothing is missed or half done. My earlier answers stand.

**2. Paths around a rule.**
- No code changed, and the battery and races pass [E].
- Every deadlock I found aborts one side, and that side writes nothing [E].
- No money lands in a closed period. In S1, the period stayed open after the close was aborted [E].

**3. The seal.** No grant changed [read the diff]. The patch-tail invariants passed on apply [E].

**4. The snapshot.** It is unchanged, and CR7, CR13b, CR14b and CR16b pass [E].

**5. The aging function.** It is unchanged [read].

**6. The invariants.** They are unchanged, and they passed on apply [E].

**7. The tests.**
- **CR19 [E, read].** A takes the period FOR SHARE as `tally_app` under RLS, and waits until B is blocked on it (`await_blocked`). Only then does A post into January, so A asks for the head that B holds. `deadlock()` requires exactly one 40P01 and one commit. The check tests its label.
- **CR20 [E, read].**
  - The period has a ledger row, so the close writes lines and reaches step 4.
  - A holds the tenant row FOR UPDATE and asks for the closing user's row only after B is blocked. A takes no head.
  - The deadlock shows that the close takes the users row before the tenant row, as the paragraph orders them.
  - The check tests its label.
- **R5b [E, read].**
  - The correct patch admits it: the sentinel fires.
  - A row-by-row net is refused in either order: +150 first goes over 100, and −50 first goes below 0.
  - M71 is therefore caught at R5b whatever order the rows come in.
  - M54 (direct rows only) sees only the +150, because the −50 is one level down. So M54 is caught there for the right reason too.
- **Missing.** A race or note for S1's one-statement shape.

**8. Residuals.** R1–R12: none is blocking. R12's new clause matches my L3/L4 results from r6.
