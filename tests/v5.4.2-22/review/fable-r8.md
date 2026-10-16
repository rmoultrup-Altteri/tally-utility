# Fable review: v5.4.2-22 r8

**Date:** 2026-10-16. **Reviewer:** Fable (claude-fable-5-1). **Round:** 8 (short round: comment lines only in the patch; no code, no test changed since r7).
**Frozen files:** all four md5s match the brief (executed): patch `ad2c6af3…`, battery `45b95d5c…`, close-22 `58886f4c…`, mutations `aac49900…`; brief `7134333d…`. The battery, race script and mutations hashes are the r7 hashes, so those three files are unchanged (executed by hash). `diff-22-r7-r8.diff` read in full: every changed line is a `--` comment line (executed).
**Clone:** `rv22fable8` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core — `has_database_privilege` f/f/f, executed). Strict apply (`search_path=''`, `check_function_bodies=on`) twice: the first silent, the second skipped on the `accounting_periods` marker (executed). Dropped at the end (executed; `pg_database` count 0).
**Read:** my r7 report, `review-findings-22-r7.md`, the diff, the r8 lock-order paragraph in full (patch lines 200–267), the r8 revision note (lines 94–100), `enforce_aging_edges_close_order` (lines 904–924), the race script's barriers and `newtenant`. Not read: any other reviewer's file.

## Verdict: ready

No blocking item. Every row, order, mode, role and grant the r8 paragraph names is right, and I executed the two new factual claims (the one-statement deadlock and the bare-SELECT lock modes). No sentence still reads as a complete list: the rule is stated as a rule, the shapes as "shapes, each executed", and the paragraph says outright that no list is promised complete. One note on wording (N1), nothing to fix.

## The diff, claim by claim

**Revision note (lines 94–100).** Names r7's findings and their authors as the findings file does; "comments only" is true (executed: the diff).

**"waits — directly, or through other transactions it waits on"** — true; this is my r7 N1 shape (three parties, A and the close aborted) and the findings' Opus S2. **"PostgreSQL aborts one side, which may be a third transaction that did nothing named here"** — true in Opus's shape per the findings; in mine the aborted sides were named parties, so "may be" is the right modal.

**"no list of shapes is promised complete; every writer retries 40P01"** — the first sentence ends the promise the previous rounds kept breaking; the second is the standing rule from the write-off paragraph above it ("Writers retry a deadlock (40P01)"). Consistent.

**"the head: FOR SHARE by every money write, GL mapping write and edges change"** — unchanged from r7, verified there against the triggers. **"FOR UPDATE by a close, and by a bare SELECT … FOR UPDATE or FOR NO KEY UPDATE from tally_app or tally_void (a column UPDATE grant is enough)"** — **P1 (executed):** on the clone, `information_schema.column_privileges` gives tally_app and tally_void UPDATE on `accounting_close_heads(updated_at)` only; as `tally_void` (SET ROLE, `app.user_id` set) `SELECT … FOR UPDATE` and `… FOR NO KEY UPDATE` on the tenant's head row both return 1; as `tally_app` `FOR UPDATE` on the head returns 1. tally_core (SELECT only) is refused "permission denied" on `FOR SHARE`, so the single-column UPDATE grant is exactly what makes the difference. True.

**"the period: FOR UPDATE by a withdrawal; any SELECT … FOR mode from tally_app (it has UPDATE on status)"** — **P1 (executed):** tally_app `FOR UPDATE` and `FOR KEY SHARE` on the period return 1; tally_void (no grant on the table) is refused. tally_app's UPDATE grant is `status, withdrawn_at, withdrawn_by`; "it has UPDATE on status" is true. Nobody else but tally_close (inside the close) can lock the period, so naming tally_app alone is right.

**"a users or tenant row FOR UPDATE: … an UPDATE whose SET names a column under a unique index, changed or not (users: id, tenant_id, cognito_sub; tenants: id, slug)"** — unchanged from r7; verified there against `pg_index` (P3, r7).

**"(the users row, then the tenant row; a write, then a key change: both executed)"** — true: the first I executed in r6, the second as r7 P2.

**"One statement can deadlock by itself: an UPDATE of tenants that changes the edges and names a unique column (an ORM full-row save, slug unchanged) holds the tenant row FOR UPDATE, then takes the head (Opus S1, r8)."** — **P2 (executed):** fresh tenant with one January row and an open January. C (tally_app) holds the period FOR SHARE; B's close takes the head FOR UPDATE and blocks on the period; A, as tally_app, runs one statement `UPDATE tenants SET receivables_aging_bucket_days = '{10,20}', slug = slug WHERE id = …` and blocks; C commits; B reaches the lines and asks the tenant row FOR KEY SHARE. Result: A aborted with **40P01**, `CONTEXT: while locking tuple … in relation "accounting_close_heads" … enforce_aging_edges_close_order() line 4` — the trigger's head FOR SHARE is the wait on A's side, after the row lock the UPDATE took, exactly as the sentence has it. B committed: period `closed`, snapshot edges `{30,60,90,120}`, tenant edges unchanged. (The row lock precedes the BEFORE ROW trigger: `GetTupleForTrigger` locks the tuple in the mode the SET list implies, then fires the trigger; the CONTEXT line is consistent with that.)
**"change the edges in an UPDATE that names no unique column"** — **P3 (executed, control):** the same with `slug = slug` removed: no deadlock; A waited for the close (its NO KEY UPDATE on the tenant row does not conflict with the close's KEY SHARE), B closed with the old edges in the snapshot, A then committed `{10,20}`. Period `closed`, snapshot `{30,60,90,120}`, tenant `{10,20}`. The advice works.

**"So close, withdraw, and change tenant and user rows each in a transaction of its own"** — the advice, not a claim. **"The close takes no advisory lock and no customer, GL mapping or other period row; a period insert never takes the head"** — unchanged, verified r7 against the close's statements. **"Other cycles come from two transactions taking the writers' advisory locks … Each in a transaction of its own avoids them too."** — reworded from "The other cycles are"; "Other cycles come from" no longer asserts those are the only others. Good.

## Should-fix

None.

## Notes

- **N1** (executed, P1; wording only, optional). "a bare SELECT … FOR UPDATE … from tally_void" is a capability, not a path: tally_void is NOLOGIN (`pg_roles`, executed) and runs only inside -20's void function, which does not lock the head. The sentence is true as written ("what takes the rows" names who *can*); if a reader could take it as a shape to defend against, "(tally_void only inside the void, which does not)" would close it. Not a correction.
- **N2.** The findings file says r8 strict-applies, mutations 79/79 and ci all pass; I reproduced the strict apply only (twice). Battery and races are unchanged by hash and passed on my r7 clone; I did not re-run them on r8 (no code changed, so a re-run would prove nothing new) — **predicted** to pass, with the hash as the ground.
- **N3.** Seal: the diff touches no grant or role (executed: comment lines only); the head/period grants read on the clone match r7's (executed).

## Answers to the brief

1. Implemented: unchanged from r7; nothing missed or half-done.
2. Paths around a rule: none; the diff is comments.
3. Seal: unchanged (N3).
4. Snapshot: unchanged; P3 shows the close keeps the edges of its instant when an edges change waits behind it.
5. Aging: unchanged.
6. Invariants: unchanged.
7. Tests: unchanged by hash. P2 is a shape the paragraph now states but no race executes; CR13/CR14 cover the two-statement edges orders. Optional CR21 if the author wants the slug shape pinned; not blocking.
8. Residuals R1–R12: unchanged; none blocking.
