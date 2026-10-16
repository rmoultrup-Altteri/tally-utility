# Fable review: v5.4.2-22 r9

**Date:** 2026-10-16. **Reviewer:** Fable (claude-fable-5-1). **Round:** 9 (short round: comment lines only in the patch; no code, no test changed since r7).
**Frozen files:** all four md5s match the brief (executed): patch `d3422f3d…`, battery `45b95d5c…`, close-22 `58886f4c…`, mutations `aac49900…`; brief `33d9a1ad…`. The battery, race script and mutations hashes are the r7 hashes, so those three files are unchanged (executed by hash). `diff-22-r8-r9.diff` read in full: two hunks, every changed line a `--` comment line (executed).
**Clone:** `rv22fable9` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core — `has_database_privilege` f/f/f, executed). Strict apply (`search_path=''`, `check_function_bodies=on`) twice: the first silent, the second skipped on the `accounting_periods` marker (executed). Dropped at the end (executed).
**Read:** my r8 report, `review-findings-22-r8.md`, the diff, the r9 revision note (patch lines 102–107) and the lock-order paragraph in full (lines 236–275). Not read: any other reviewer's file.

## Verdict: ready

No blocking item, no should-fix. The two r9 hunks say exactly what the findings file says they should, and every factual claim they add I executed on the clone: the four FOR modes for tally_app on the head, the control that makes the one-column grant the difference, tally_void's login, membership and function ownership, and the DELETE on users and tenants by the owner and by tally_app. One note (N1) on a nuance of "the delete is refused" that is true as written and concerns only the owner.

## The diff, claim by claim

**Revision note (lines 102–107).** "Comments only" — true (executed: the diff). "Opus and Fable 'ready', nothing to fix; Ryan asked that the notes be fixed before the mirror" — matches the findings file. The three items and their attribution "(Opus N1-N3, Fable N1)" match the findings table rows 1–3 (my r8 N1 is row 2). "A bare SELECT in any FOR mode, not 'FOR UPDATE by ... FOR NO KEY UPDATE'" — accurately describes what was changed.

**"the head: … FOR UPDATE by a close. tally_app may also lock it by a bare SELECT in any FOR mode (its UPDATE grant on one column is enough; r9)."** — **P1 (executed).** `information_schema.column_privileges`: tally_app holds UPDATE on `accounting_close_heads(updated_at)` and no other column; its table grants are SELECT and INSERT. As tally_app (`SET LOCAL app.user_id`, `SET ROLE`), on the tenant's head row, each in its own transaction: `FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE`, `FOR KEY SHARE` all return 1 row. Control: tally_core (SELECT only) is refused "permission denied for table accounting_close_heads" in all four modes. So "any FOR mode" is true and "one column is enough" is exactly the difference. (The r8 wording that named FOR NO KEY UPDATE as a case of FOR UPDATE is gone; the new sentence names no mode and so misnames none.)

**"tally_void holds such a grant too, but it cannot log in and runs only inside the void"** — **P2 (executed).** tally_void: UPDATE on `accounting_close_heads(updated_at)` only; `pg_roles.rolcanlogin = f`, not BYPASSRLS, not superuser; `pg_auth_members` has no row where tally_void is role or member, so no session can `SET ROLE` to it short of the owner; `pg_proc` shows exactly one function owned by tally_void, `public.void_invoice(uuid,uuid,text,text,boolean)`, SECURITY DEFINER, and its body does not reference `accounting_close_heads` (regex on `prosrc`, executed). The patch's seal registry at line 1657 lists that same single function for tally_void. "Runs only inside the void" is therefore literally true, and "the void" is one function that never takes the head.

**"a users or tenant row FOR UPDATE: SELECT ... FOR UPDATE, or an UPDATE whose SET names a column under a unique index, changed or not (users: id, tenant_id, cognito_sub; tenants: id, slug)."** — the unique-index columns are unchanged from r7 (verified there against `pg_index`, P3 r7); the DELETE is dropped from the list, which is what the findings file says.

**"Only the owner may DELETE them, and the delete is refused."** — **P3 (executed).** `role_table_grants`: DELETE on `users` and on `tenants` is held by `tally` only, which is each table's owner (`pg_class.relowner`). No SECURITY DEFINER function in `public` has `DELETE FROM users|tenants` in its body (regex on `prosrc`, 0 rows), so no definer path deletes them on a caller's behalf. `pg_trigger`: `no_hard_delete` and `no_truncate` on both tables with `tgenabled = 'A'` (ENABLE ALWAYS), so a replica-role session does not skip them. `enforce_no_hard_delete()` is three lines: an unconditional `RAISE EXCEPTION … ERRCODE restrict_violation`. Executed as owner, in savepoints: `DELETE FROM users` and `DELETE FROM tenants` each raise "rows are never hard-deleted (CI-014)" and the rows remain. As tally_app both are "permission denied". Both halves of the sentence are true.

**Everything else in the paragraph** is unchanged from r8, where I verified each claim (r8 P1–P3 and the r7 record).

## Should-fix

None.

## Notes

- **N1 (executed; owner-only nuance, not a correction).** A refused DELETE is still a waiter. With a tally_app session holding the user's row `FOR KEY SHARE`, an owner `DELETE FROM users` under `lock_timeout = 1500ms` fails with "canceling statement due to lock timeout — while locking tuple (0,1) in relation users", not with the CI-014 refusal; with nobody holding the row the same DELETE is refused at once. The row lock (`GetTupleForTrigger`) precedes the BEFORE ROW trigger, so an owner's DELETE queues for the row FOR UPDATE before it is refused, and could in principle sit in a wait chain with a close. The sentence is true as written and the list is about app sessions, which cannot DELETE; the only session that can is `tally`, which runs no application code. Nothing to change; recorded so the fact is on file.
- **N2.** The findings file says r9 strict-applies, mutations 79/79 and ci all pass. I reproduced the strict apply (twice). Battery and races are unchanged by hash since r7 and passed on my r7 clone; no code changed since, so I did not re-run them — **predicted** to pass, with the hash as the ground.
- **N3.** Seal: the diff touches no grant, role or function (executed: comment lines only). The head grants read on the clone match r8's (executed).

## Answers to the brief

1. Implemented: unchanged from r8; nothing missed or half-done.
2. Paths around a rule: none; the diff is comments.
3. Seal: unchanged (N3).
4. Snapshot: unchanged.
5. Aging: unchanged.
6. Invariants: unchanged.
7. Tests: unchanged by hash. CR16–CR20 plus the executed-in-review shapes still cover the paragraph's claims.
8. Residuals R1–R12: unchanged; none blocking.
