# Opus review: v5.4.2-22 r9

**Date:** 2026-10-16. **Reviewer:** Opus. **Verdict: ready.**

r9 changes comment lines only. It folds my round-8 notes N1–N3. I checked each new sentence against the database. None is false, and the lock-order paragraph claims nothing false. One small imprecision remains (N1 below). It is owner-only and needs no change.

Each claim is marked **[E]** (executed) or **[P]** (predicted, or read in the source).

**Hashes [E].**
- The brief's md5 is `33d9a1adc3c41f16aa76b3c6b6162d14`.
- The frozen files match the brief: patch `d3422f3d…`, battery `45b95d5c…`, close `58886f4c…`, mutations `aac49900…`. The live copies are identical to them.

**What I ran [E].**
- I cloned `rv22opus9` from `tally`, then revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
- I strict-applied the frozen patch twice. The second run skipped: "already applied (accounting_periods exists)".
- I ran `VACUUM ANALYZE account_ledger`, then the battery: **167 PASS**, rc 0.
- I ran `close-22-frozen-r9.sh rv22opus9` once: **30 PASS lines, CR1–CR20**, rc 0.
- I ran lock probes on a tenant and user of my own (below), and queried the grants, role attributes, memberships, function owners and triggers.
- I did not run `mutations-22.py`.
- I dropped the clone and removed my files from the container.

I read only the diff, my r8 report and `review-findings-22-r8.md`. I did not read the other reviewers' files.

---

## Blocking

None.

## Should fix

None.

---

## The r9 sentences, one by one

**"FOR SHARE by every money write, GL mapping write and edges change; FOR UPDATE by a close."** This is unchanged in substance, and was verified in r8 [read].

**"tally_app may also lock it by a bare SELECT in any FOR mode (its UPDATE grant on one column is enough; r9)."**
- Grant [E]: `tally_app` holds UPDATE(`updated_at`) on `accounting_close_heads`, and no other UPDATE there.
- Probe [E]: `tally_app` ran under RLS as an operator of its own tenant. It held the head in each of FOR KEY SHARE, FOR SHARE, FOR NO KEY UPDATE and FOR UPDATE. In all four cases, an owner `SELECT … FOR UPDATE` (the close's mode) hit its 1 s lock timeout "while locking tuple".
- Control [E]: `tally_core` has no UPDATE on the head. Its `SELECT … FOR KEY SHARE` is refused with "permission denied for table accounting_close_heads". So the grant is what enables the lock, as the sentence says.
- "Any FOR mode" is exact, and it now covers my r8 N2 (bare FOR SHARE / FOR KEY SHARE).

**"tally_void holds such a grant too, but it cannot log in and runs only inside the void."**
- Grant [E]: `tally_void` holds UPDATE(`updated_at`) on the head.
- Role [E]: `tally_void` is `rolcanlogin = f`, and no role is a member of it (pg_auth_members is empty both ways).
- Functions [E]: it owns exactly one function, `void_invoice(uuid,uuid,text,text,boolean)`, which is SECURITY DEFINER. So only the void runs as it. That function takes the head only FOR SHARE, through the money-write trigger [read, r8].
- The sentence is exact. (A superuser could `SET ROLE tally_void`, but a superuser is outside every guard here.)

**The period line.** It is unchanged, and was verified in r8 [E, r8].

**"a users or tenant row FOR UPDATE: SELECT … FOR UPDATE, or an UPDATE whose SET names a column under a unique index, changed or not (…). Only the owner may DELETE them, and the delete is refused."**
- DELETE grants [E]: only `tally`, the owner (a superuser), holds DELETE on `users` and `tenants`. `tally_app`'s DELETE is refused with "permission denied for table users".
- Refusal [E]: `no_hard_delete` is a BEFORE ROW DELETE trigger, ENABLE ALWAYS, on both tables. Its body raises unconditionally (`restrict_violation`). An owner DELETE of my user was refused with "users rows are never hard-deleted (CI-014)".
- The rest of the line is unchanged from r8, and the column lists were verified there [E, r8].

**The r9 header entry** cites the right notes (Opus N1–N3, Fable N1, which I take on the findings file's word). It says correctly that this is a comments-only change, and it quotes the old wording accurately [read].

**The rest of the paragraph** is unchanged from r8. It reads consistently with the new lines: the rule's "holds the head FOR SHARE and then closes" plus "no list of shapes is promised complete" covers the bare-KEY-SHARE-then-close upgrade [read].

---

## Notes

**N1. A refused DELETE still queues for the row lock first [E].**
- When `tally` held my users row FOR KEY SHARE, an owner `DELETE` of that row did not fail at once. It hit its 1 s lock timeout "while locking tuple (0,1) in relation users". Once the holder committed, the same DELETE was refused by `no_hard_delete`.
- So the owner's DELETE still asks for the row FOR UPDATE, and so it can wait on a close, or be part of a cycle with one, before it is refused.
- This misleads no one in practice. It is owner-only (a superuser). It writes nothing either way. PostgreSQL aborts one side of any cycle, and the paragraph promises no complete list.
- If the sentence is touched again: "Only the owner may DELETE them; the delete waits for the row like an UPDATE, then is refused." No change is needed for the mirror.

**N2. "Cannot log in" holds for `tally_app` too, in this cluster [E].** `tally_app` is also NOLOGIN with no members here. The contrast the sentence draws is between a role the application's login role is granted in deployment (`tally_app`) and a sealed definer role that is never granted (`tally_void`, under the -20 pattern). That contrast is right. Nothing needs to change.

---

## Answers to the brief

1. **Inventory and rulings.** No code changed [read the diff]. My earlier answers stand: nothing is missed or half done.
2. **Paths around a rule.** No code changed. The battery (167) and the races (CR1–CR20, 30 PASS) pass on my clone [E].
3. **The seal.** No grant changed. The patch-tail invariants passed on apply [E]. `tally_void`'s and `tally_close`'s grants on the head are as r8 had them [E].
4. **The snapshot.** It is unchanged. CR7, CR13b, CR14b and CR16b pass [E].
5. **The aging function.** It is unchanged [read].
6. **The invariants.** They are unchanged, and passed on apply [E].
7. **The tests.** They are unchanged from r7, and pass [E]. Nothing new is missing, because nothing new was added.
8. **Residuals R1–R12.** None is blocking.
