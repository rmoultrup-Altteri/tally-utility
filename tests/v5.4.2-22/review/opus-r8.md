# Opus review: v5.4.2-22 r8

**Date:** 2026-10-16. **Reviewer:** Opus. **Verdict: ready.**

r8 changes comments only. It folds both of my round-7 should-fix items:
- S1, the one-statement edges + `slug` shape, is now stated as a shape, with advice that avoids it.
- S2, the three-party cycle, is covered: the rule now says "directly, or through other transactions it waits on", and it promises no complete list.

My r7 note N1, the bare locks on the head and the period, is added too. I checked every row, mode, grant and order the new paragraph names. None is false. Two wording imprecisions remain (N1, N2). Neither misleads anyone into a shape that deadlocks without warning.

Each claim is marked **[E]** (executed) or **[P]** (predicted, or read in the source).

**Hashes [E].**
- The brief's md5 is `7134333d4d0672eb25755088952ab4d7`.
- The frozen files match the brief: patch `ad2c6af3…`, battery `45b95d5c…`, close `58886f4c…`, mutations `aac49900…`.

**What I ran [E].**
- I cloned `rv22opus8` from `tally`, then revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
- I strict-applied the frozen patch twice. The second run skipped with "already applied (accounting_periods exists)".
- I ran `VACUUM ANALYZE account_ledger`, then the battery: **167 PASS**, rc 0.
- I ran `close-22-frozen-r8.sh rv22opus8` once: **30 PASS lines, CR1–CR20**, rc 0.
- I ran lock probes on a tenant of my own (below), and queried the grants, triggers, unique indexes and FKs.
- I did not run `mutations-22.py`.
- I dropped the clone and removed my files from the container.

---

## Blocking

None.

## Should fix

None.

---

## The paragraph, claim by claim

**The rule (waits "directly, or through other transactions"; the aborted side "may be a third transaction"; "no list of shapes is promised complete"; "every writer retries 40P01").**
- This matches the cycle I executed in r7 (S2), in which D was aborted [E, r7].
- It no longer reads as a complete list [read].

**"the head: FOR SHARE by every money write, GL mapping write and edges change"** [read]. All three take it at patch lines 590/602, 1501 and 910.

**"FOR UPDATE by a close, and by a bare SELECT … FOR UPDATE or FOR NO KEY UPDATE from tally_app or tally_void (a column UPDATE grant is enough)".**
- Grants [E]: `tally_app` and `tally_void` each hold UPDATE(`updated_at`) on `accounting_close_heads` and SELECT on its three columns. `tally_core` holds no UPDATE there.
- Probe [E]: `tally_app`, under RLS as an operator, held the head FOR NO KEY UPDATE. An owner FOR SHARE timed out on it, and so did an owner FOR UPDATE. When `tally_app` held the head FOR UPDATE, an owner FOR KEY SHARE timed out.
- See N1 and N2 for the wording.

**"the period: FOR UPDATE by a withdrawal; any SELECT … FOR mode from tally_app (it has UPDATE on status)".**
- Grants [E]: `tally_app` holds UPDATE(`status`, `withdrawn_at`, `withdrawn_by`) and SELECT on every column.
- Probe [E]: `tally_app` held a period FOR UPDATE, and an owner FOR SHARE timed out on it.
- The only FK to `accounting_periods` is the snapshot's [E], so no money write takes the period.

**"a users or tenant row FOR UPDATE: … an UPDATE whose SET names a column under a unique index, changed or not (users: id, tenant_id, cognito_sub; tenants: id, slug)".**
- Unique indexes [E]: users `(id)`, `(id, tenant_id)` and `(cognito_sub)`; tenants `(id)` and `(slug)`. The column lists are exact.
- "Changed or not" holds because both tables have BEFORE ROW UPDATE triggers [E]. With such a trigger, the row lock's mode follows the columns named in SET, not the values changed. Without one, an unchanged key would take NO KEY UPDATE.
- Probes [E], each holding the row FOR KEY SHARE:
  - `UPDATE users SET cognito_sub = cognito_sub` timed out;
  - `UPDATE users SET tenant_id = tenant_id` timed out;
  - `UPDATE tenants SET id = id` timed out;
  - controls `SET display_name = display_name` and `SET name = name` did not wait.
- `slug` was executed in r7 (E3).

**"One statement can deadlock by itself: an UPDATE of tenants that changes the edges and names a unique column … holds the tenant row FOR UPDATE, then takes the head."**
- This is my r7 S1 repro [E, r7]. The order is right: the row lock comes from the BEFORE trigger's tuple fetch, before `enforce_aging_edges_close_order` runs.
- The advice "change the edges in an UPDATE that names no unique column" avoids it. That shape waited in r7 (E4) [E, r7].

**"a write, then a key change: both executed".**
- I did not re-run it. It holds by construction [P]: against a close past step 1, the write blocks on the head, so it never reaches the key change while the close runs.

**The r8 header entry** cites the right findings, and says correctly that this is a comments-only change.

---

## Notes

**N1. "FOR UPDATE by … a bare SELECT … FOR NO KEY UPDATE" names the wrong mode [E].**
- FOR NO KEY UPDATE is its own mode, not FOR UPDATE.
- It conflicts with everything that matters here: the close's FOR UPDATE and the writers' FOR SHARE. So no conclusion changes.
- Suggested wording: "FOR UPDATE by a close; FOR UPDATE or FOR NO KEY UPDATE by a bare SELECT … from tally_app …".

**N2. Two small gaps in the head's line [E for the grants, P for the shapes].**
- **`tally_void` cannot run a bare SELECT.** It is NOLOGIN and has no members. Its one function, `void_invoice`, locks the invoice FOR UPDATE and the head only FOR SHARE, through the money-write trigger. So "from tally_void" states a privilege, not a path that exists. It is harmless.
- **Bare FOR SHARE and FOR KEY SHARE on the head by `tally_app` are not listed.**
  - Holding the head FOR KEY SHARE and then closing is an upgrade deadlock of the same kind as the listed "holds the head FOR SHARE and then closes". The rule's second clause names FOR SHARE only.
  - The new "no list is promised complete" disclaimer covers this, and so does 40P01 retry.

**N3. A DELETE as a way to take FOR UPDATE [read].** `tally_app` lacks DELETE on users and tenants, and `no_hard_delete` refuses the owner. So this path is the owner's only, and it aborts. It is listed correctly and has no practical reach.

---

## Answers to the brief

1. **Inventory and rulings.** No code changed [read the diff]. My earlier answers stand: nothing is missed or half done.
2. **Paths around a rule.**
   - No code changed, and the battery (167) and the races (CR1–CR20) pass [E].
   - Every deadlock in the paragraph aborts one side, and that side writes nothing [E, r7 and the races].
3. **The seal.** No grant changed. The patch-tail invariants passed on apply [E].
4. **The snapshot.** It is unchanged; CR7, CR13b, CR14b and CR16b pass [E].
5. **The aging function.** It is unchanged [read].
6. **The invariants.** They are unchanged and passed on apply [E].
7. **The tests.**
   - They are unchanged, and they pass [E].
   - The one-statement shape (r7 S1) still has no race. That is acceptable, because it is now stated and my r7 repro executed it.
8. **Residuals R1–R12.** None is blocking.
