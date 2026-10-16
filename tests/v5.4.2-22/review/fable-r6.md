# Fable review: v5.4.2-22 r6

**Date:** 2026-10-16. **Reviewer:** Fable (claude-fable-5-1). **Round:** 6 (short round on a small diff).
**Frozen files:** all four md5s match the brief (executed): patch `b3a3c982…`, battery `70b1003c…`, close-22 `512cf9c9…`, mutations `06f6f920…`; brief `11459967…`.
**Clone:** `rv22fable6` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core; `has_database_privilege('tally_app', …, 'TEMP')` = false, executed). Strict apply (`search_path=''`, `check_function_bodies=on`) twice: the first applied silently, the second skipped on the `accounting_periods` marker (executed). `assert_periods_guard_invariants()` and `assert_seal_role_invariants()` called by hand: both pass (executed). Dropped at the end (executed; `pg_database` count 0).
**Read:** my r5 report, `review-findings-22-r5.md`, `diff-22-r5-r6.diff` in full, the patch's header and the recovery function and the close function, the battery's R9b/R11b/R11c/R12e–R12o, the race script's header, helpers and CR16–CR18, the mutations M73–M79 and the runner. Also `stamp_log_created_at` in `sql/tu.sql` (the stamp is `now()`, kept only for a superuser; `account_ledger.created_at` is timestamptz). Not read: any other reviewer's file.

## Verdict: ready

No blocking item. Each r5 finding is closed by the mechanism the findings table names, and the 23514/40001 split does what it claims: an honest writer (tally_app) can only ever receive 40001, because its `created_at` is always its transaction's `now()`; a row whose time was chosen is refused for good and never retries (P3, executed). One should-fix: the lock-order paragraph's closing sentence, "These are the cycles -22's locks can make", is still not complete — three cycles that never touch the head deadlock with a close (S1, executed, three shapes and a control). The advice already given ("change tenant and user rows in a transaction of their own"; "withdraw in a transaction of its own") covers all three, so this is a wording fix, not a rule gap.

## Reproduced (executed)

- `battery-22-frozen-r6.sql` on the clone after `VACUUM public.account_ledger`, `statement_timeout=300s`: 166 PASS, 0 FAIL/ERROR, exit 0. R9b, R11b, R11c, R12e (23514, "a time chosen for it"), R12i (40001, "retry it"), R12j, R12k, R12l each PASS with the refusal their label names.
- `close-22-frozen-r6.sh rv22fable6`: 28 PASS lines (CR1–CR18 and sub-checks), nothing else printed, exit 0. CR16, CR16b, CR17, CR18 PASS.
- Did not run `mutations-22.py` (fixed `m22` name). M73–M79 reviewed by reading (N3).

## r5 findings, each checked

| # | r6 mechanism | Checked |
|---|---|---|
| 1, 2, 3 (lock order) | paragraph rewritten; CR16–CR18 | Read; CR16–CR18 PASS (executed). The paragraph is **true** for every cycle it states — I found none it states that cannot happen. It is **not complete** (S1). |
| 4 Opus N1 (chosen time, 23514) | `IF FOUND AND NEW.created_at <> now()` → 23514, before the 40001 branch | R12e, R12i PASS (executed). P3a–P3d (executed, below). |
| 5 Opus S2 (past history load) | R12k; M74 | R12k PASS (executed): three 2024 instants, one statement each, then a live recovery; the write-off's stored time kept. |
| 6 Fable N1 (`isfinite` leg) | R12j; M73 | R12j PASS (executed): `-infinity` refused with "non-finite or future time". |
| 7 messages, comment | "non-finite or future time"; comment names the write-off firing | Read; the messages print as the battery shows. |
| 8 Codex S2 (probes → checks) | R11b/R11c, R12l–R12o; M77–M79 | PASS (executed). R11b admits exactly 1,000 in one statement and R11c refuses the 1,001st naming row 1,000; R12n checks both caps by message prefix (`write-off <id>: on 2026-02-01`), so the inner and outer refusal are each attributed to the right write-off. |
| 9 CR15 barriers | `signal`/`await_app` on `application_name` | CR15, CR15b PASS (executed). |
| 10 R9b relabel | — | Read. |

## The 23514/40001 split (executed, P3, one transaction as the owner, rolled back)

Tree: a write-off `f6a2` at `now()`, then a recovery `f6a3` at `clock_timestamp()` (later than `now()`).
- **P3a** a recovery with a chosen time **equal** to the write-off's: admitted. `>` is strict, so a row at the same instant as a tree row is not "before" it (as rows of one statement are).
- **P3b** a superuser row with explicit `created_at = now()` (the transaction's start, before `f6a3`): **40001**, "retry it". A chosen `now()` is treated as a stamp, which it is; its retry is stamped later.
- **P3c** a superuser row at `now() - 1 second`: **23514**, "a time chosen for it". No retry can change it.
- **P3d** tally_app supplying `created_at = now() - 1 day` under the same tree: stamped `now()` by `stamp_log_created_at` (BEFORE INSERT, ENABLE ALWAYS, `now()`), then **40001**, never 23514.

So: an honest writer's `created_at` is `now()` by construction (R12m shows the same for a supplied infinity), the `<> now()` test is false for it, and only the 40001 branch can reach it. A chosen time before any row already in the tree is refused for good, as R12 now says; a chosen time at or after every tree row is admitted (R12k). Neither leg can strand a writer in a retry that cannot succeed. The r5 future-time rule is untouched by this diff except for its message.

## Should-fix

### S1. The lock-order paragraph's completeness claim omits three cycles that never touch the head — **executed**

The paragraph now says "These are the cycles -22's locks can make: writers under two write-offs; a withdrawal then a write; the tenant or a users row held FOR UPDATE then the head; and a write then a close." The close's own order is: head FOR UPDATE, period FOR UPDATE, then (the period UPDATE's `closed_by`, and the snapshot row's `closed_by`) the closing user's `users` row FOR KEY SHARE, then (the snapshot lines' `tenant_id`) the tenant row FOR KEY SHARE. Because the close holds the period row and the users row *before* it asks for the tenant row, these also deadlock, with no head involved:

- **P1′** A: `SELECT … FROM tenants WHERE id = T FOR UPDATE`; waits until the close is blocked on that row; then `SELECT … FROM users WHERE id = <closing user> FOR UPDATE`. B: closes March (which has activity). **Deadlock**: B (the close) aborted 40P01, A committed, March stays open (executed). Control **P1b′**, the reverse order in A (users row, then tenant row): no deadlock; the close waited, then closed (executed) — as the close's internal order (users before tenant) predicts.
- **P2** A: the closing user's row FOR UPDATE; waits until the close is blocked on it; then, as tally_app, withdraws the period being closed (`UPDATE accounting_periods SET status = 'withdrawn'`, which waits on the period row the close holds). **Deadlock**: the close aborted 40P01, the withdrawal committed, the period is withdrawn (executed).
- **P2b′** As P2 with the tenant row held FOR UPDATE instead. **Deadlock**: the close aborted, the period withdrawn (executed).

Nothing admits money, one side is aborted and nothing is written by it, and the advice already in the paragraph covers every shape (tenant and user rows in a transaction of their own; withdraw in a transaction of its own). The fix is wording: either drop the "These are the cycles" sentence, or extend it — "the tenant or a users row held FOR UPDATE, then the head, **the period row (a withdrawal), or the other of those two rows (the close takes the users row before the tenant row)**". No new race is needed; a test is optional (CR17's shape with a withdrawal in A's place would pin P2b′ in one leg).

Not a cycle (predicted, from the lock order): a money write that then changes a unique column of the tenant or a users row — the close takes the head first and holds nothing else while it waits on the head, so the writer's later FOR UPDATE is never blocked by the close.

## Notes

- N1. **A close with no activity and no aging never touches the tenant row** (executed, by accident): my first P1 and P2b ran against a period with no ledger rows; the close committed without ever blocking on the tenant row A held, because no snapshot line was written and the snapshot row's FKs are the period and `closed_by` only. CR17 is right because the race fixture has rows; the paragraph's "takes FOR KEY SHARE on the tenant row" is true whenever the close writes a line, which is every real close. Worth one word in the paragraph ("when it writes a snapshot line") only if exactness is wanted.
- N2. **The 23514 message** names the chosen time and the later row, and says "a history row is recorded after every row already in its tree" — right. The 40001 message is unchanged.
- N3. **Mutations** (predicted from reading, with the runner's first-FAIL rule): M73 drops the `isfinite` leg → `-infinity` admitted at R12j, nothing earlier touched (R12f's infinity is still caught by `> clock_timestamp()`). M74 refuses a past write-off → R12k's 2024 write-off refused; R12e (`now()`) and R12i (`clock_timestamp()`) are not before `now()`, so they pass first. M75 `IF false` → R12e gets 40001, not 23514 → fails at R12e. M76 `IF FOUND` → R12e still 23514, R12i gets 23514 → fails at R12i, the right reason. M77 (outermost only) → R12n's inner overflow admitted (outer nets 81 of 100) → the check's own RAISE. M78 (999) → R11b's 1,000 refused. M79 (`WHERE true`) → R12o's walk reaches C1's +500 and the +500 back to C5 → refused instead of the sentinel. Each anchor is unique in the r6 text (checked by grep on the frozen patch). None passes for a wrong reason that I can see.
- N4. **CR16b** checks the survivor's posting by comparing the snapshot's `ledger_entry_count` to the committed August rows, which is the right assertion: the loser's posting is rolled back with its transaction, so the counts agree only if exactly one posted-and-closed.
- N5. **Seal** (executed): tally_close's grants are unchanged in r6; `assert_seal_role_invariants()` passes. Nothing in the diff touches a role or a grant.
- N6. **Residuals R1–R12:** none blocking. R12's new sentence is what P3b/P3c show.

## Answers to the brief

1. Implemented: every P/S/G/W row and the drafting calls, as in r2–r5; the r5 findings closed by the stated mechanisms; nothing missed or half-done.
2. Paths around a rule: none found. The diff changes one SQLSTATE and words; the battery's P/H/C/F/G rows and CR1–CR14 pass unchanged (executed). Netting past the cap or below zero: refused at every date and recorded instant (R12–R12o, CR5, CR11, CR15). Wrong customer or sign, loops, over-long chains: refused (R9b, R11–R11c, R12o).
3. Seal: meets -20; grant list unchanged and least (N5).
4. Snapshot: figures unchanged (C rows, CR7, CR16b); edges the tenant's at the instant (CR13, CR14).
5. Aging: unchanged in r6; correct for the cases above; RLS-safe; coordinates required (W1).
6. Invariants: unchanged in r6 and passing; each claim matches its check.
7. Tests: no check weaker than its label; no mutation caught for a wrong reason (N3). Missing: nothing I would block on; S1's shapes could be pinned by one more leg, optional.
8. Residuals: none blocking.
