# Fable review: v5.4.2-22 r5

**Date:** 2026-10-16. **Reviewer:** Fable (claude-fable-5-1). **Round:** 5.
**Frozen files:** all four md5s match the brief (executed): patch `7e914bda…`, battery `a5369adf…`, close-22 `59554ed2…`, mutations `8513d1d2…`; brief `9197fc98…`.
**Clone:** `rv22fable5` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core), strict apply (`search_path=''`, `check_function_bodies=on`) twice: the first applied silently, the second skipped on the marker (executed). `assert_periods_guard_invariants()` and `assert_seal_role_invariants()` called again by hand: both pass (executed). Dropped at the end.
**Read:** my r4 report, `review-findings-22-r4.md`, `diff-22-r4-r5.diff` in full, the patch in full (header, sections 1–12), the battery's fixtures and R10e–R12h, the race script's fixtures and CR13–CR15, the mutations runner and M64–M72. Not read: any other reviewer's file.

## Verdict: ready

No blocking item. Each r4 finding is closed by the mechanism the findings table names. The future-time rule strands no honest writer and no history load posted one statement per instant, and the widened trigger changes nothing for rows outside a write-off's tree (probes A1–A5 below, executed). One should-fix: the lock-order paragraph still understates the close's row locks — the close also takes the closing user's `users` row FOR KEY SHARE, and any head-FOR-SHARE taker (a money write or a GL mapping write, not only an edges change) completes the cycle (S1, executed, three shapes). One wording fix (S2).

## Reproduced (executed)

- `battery-22-frozen-r5.sql` on the clone after `VACUUM public.account_ledger`: 157 PASS, 0 FAIL/ERROR, exit 0.
- `close-22-frozen-r5.sh rv22fable5`: 24 PASS lines (CR1–CR15, CR13b, CR14b, CR15b and the sub-checks), nothing else printed.
- Did not run `mutations-22.py` (fixed `m22` name). M69–M72 and the re-anchored M68 reviewed by reading (N5).
- `pg_proc.proconfig` of both walk functions is exactly `{search_path=public, pg_temp, enable_seqscan=off, enable_hashjoin=off, enable_mergejoin=off}` (executed, catalog).

## r4 findings, each checked

| # | r5 mechanism | Checked |
|---|---|---|
| 1 Codex B1: a future `created_at` strands the tree | `v_future` (not finite, or after `clock_timestamp()`) refuses a `write_off` before anything else, and any row under a write-off inside the loop after the advisory lock; the trigger WHEN gains `transaction_type = 'write_off'`; pinned in the invariant | R12f, R12g PASS (executed). Probes: a nested write-off naming a recovery at 2200 and at `-infinity` refused by the first check (A2, A2b); a plain write-off at `clock_timestamp()` admitted, at `clock_timestamp() + 1 ms` refused (A2c, A2d); a history tree loaded one statement per instant then a live recovery admitted (A4a–d); the owner's history load with two instants in one statement, and a row at an instant between two loaded ones, refused 40001 as R12 says (A4e, A4f). Outside a tree nothing changes: a payment reversal at 2200, a later honest row naming the same payment, a write-off *below* that future row and its recovery are all admitted (A3–A3d); another customer's row at 2200 naming into a tree is admitted and strands nothing (A5, A5b). |
| 2 Opus S1 / Fable S1: the edges-lock deadlock | stated in the lock-order paragraph | Read. The statement is accurate for the shape it names but is not the only shape (S1). |
| 3 Fable S2: plan settings unpinned | exact `proconfig` equality for both walks | Executed (catalog, invariant passes). M68 is now `APPLY:lost its plan settings` and the anchor removes exactly the three SET lines, so the apply must refuse (read). |
| 4 Codex S1: mixed-instant batch | residual R12 | Read; A4f reproduces the refusal it describes. |
| 5 Opus N: same-date netting | R12h; M71 | R12h PASS (executed): a recovery, its reversal and a new recovery on one date net 100 of 100. M71 (`ROWS UNBOUNDED PRECEDING`) is caught at R10f, whose two same-date rows (`-1` after the C1 row) also cross when taken one by one; the runner's first-FAIL rule makes the name right (read). |
| 6 Codex S2: CR15's SQLSTATE | `grep "ERROR:  40001:"` with `VERBOSITY=verbose`, and "retry it" | CR15 PASS (executed); the `-v VERBOSITY=verbose` in `PSQL` is what makes the SQLSTATE print. |

## The future-time rule (executed and predicted)

- **Who can set `created_at`.** `stamp_log_created_at` (BEFORE INSERT, ENABLE ALWAYS) overwrites `created_at` with `now()` for every non-superuser; tally_app's `created_at` of 2200 on a charge and on a write-off was stored as `now()` (A1, A1b, executed). So the rule binds superuser history loads only, as the comment says, and an honest writer's stamp is always `now()` of its own transaction, which is never after `clock_timestamp()` at trigger time: no honest writer is refused by `v_future` (A2c shows the boundary is `clock_timestamp()` itself).
- **Stranding.** With every tree row finite and already reached, the recorded-order refusal (40001) fires only when a committed tree row has a later stamp than NEW's, which for an honest writer means a transaction that began later committed first; its retry gets a fresh `now()` later than every committed stamp, so it succeeds unless beaten again (my r4 N2 still holds). A past-dated load row behind later rows is refused for good (A4e), which is R12 and the intended order.
- **Scope.** The under-write-off check runs only inside the loop, so only rows with a same-customer write-off above them are bound; the up walk stops at the first row of another customer, so a cross-customer row naming into a tree is not bound (A5) and, since `v_tree` is `WHERE d.mine`, cannot strand the tree either. Consistent with aging, which roots such a row on itself.
- **The write-off itself.** The first check runs before the early `RETURN NULL`, so a plain write-off (no `reverses_ledger_entry_id`) is bound; a nested one is bound by the same check before the loop (A2).

## Should-fix

### S1. The close's row locks, and so its deadlocks, are more than the header states — **executed**

The header says the close takes "the head, then (its snapshot rows' tenant key) the tenant row FOR KEY SHARE", and names one partner: a transaction that holds the tenant row FOR UPDATE and then changes the edges. Executed on the clone against a close of the race tenant's August period, each with the close as the session that was aborted (40P01, "while locking tuple … FOR KEY SHARE"):

- **D1.** A holds the closing supervisor's `users` row FOR UPDATE (`SELECT … FOR UPDATE`), then changes the edges; B closes as that supervisor. The close deadlocks at `UPDATE accounting_periods … closed_by = v_user` (the `closed_by` FK takes KEY SHARE on `users`).
- **D2.** A updates the tenant's `slug` (a unique column, so FOR UPDATE strength), then posts a ledger row; B closes. The close deadlocks at the snapshot lines' tenant FK. The partner is a money write, not an edges change.
- **D3.** A updates the supervisor's `cognito_sub` (unique), then inserts a GL mapping; B closes as that supervisor. Deadlock at the `closed_by` FK again; the partner is a GL mapping write.
- **D4** (control). A holds the customer's row FOR UPDATE, then posts a ledger row; B closes. No deadlock: the close completes, as predicted (it locks no customer row; the aging only reads `customers`).

The complete statement: the close takes the head FOR UPDATE, the period FOR UPDATE, then KEY SHARE on the tenant row (snapshot lines) and on the closing user's `users` row (`closed_by` on the period and the snapshot). A transaction that holds either row FOR UPDATE (a key or unique column in its SET — `slug`, `cognito_sub`, `id` — or `SELECT … FOR UPDATE`) and then takes the head FOR SHARE by any path — a money write, a GL mapping write, an edges change — can deadlock with a close; one side is aborted and nothing is written. Nothing admits money; the fix is the paragraph (and the comment on `close_accounting_period`), as r4's disposition chose. Not taken by me either: rerouting the FKs.

### S2. "Change the edges in a statement of their own" — **read**

The deadlock the paragraph names arises when the *transaction* already holds the tenant row FOR UPDATE from an earlier statement (its own example: an ORM save). A statement of its own in that transaction still holds the row. The withdrawal paragraph says it right: "in a transaction of its own". Say the same here, and (S1) for the users row.

## Notes

- N1. **`isfinite` leg untested** (read; A2b executed): `'infinity' > clock_timestamp()` is true, so R12f's infinity is caught by the second leg of `v_future` as well; only `-infinity` needs `NOT isfinite`. A mutation dropping the `isfinite` leg passes the battery. `-infinity` strands nothing (no stamp is earlier than it) and is refused today (A2b), so this is a test gap, not a rule gap. A one-line R12f variant with `'-infinity'` closes it.
- N2. **Boundary of "already reached"** (executed, A2c/A2d): the comparison is against `clock_timestamp()` at the trigger's run, strict. A superuser's stamp equal to the session clock at the INSERT is admitted, one millisecond later refused. Honest stamps are `now()`, earlier than either.
- N3. **R2's close check and future rows outside a tree** (predicted): a superuser row at 2200 dated inside a period being closed (A3's shape) blocks that period's close until the stamp passes, under r2's "recorded after the instant" refusal. Pre-r5 behaviour, superuser only, no money admitted; the operator sees the message naming the instant.
- N4. **Trigger widening cost** (read): for a plain write-off the function evaluates `v_future` and returns at the first `IF`; no walk, no lock. tally_void writes `void_reversal`, never `write_off`, so the void path is untouched.
- N5. **Mutations** (predicted from reading): M69 (`IF v_future` → `IF false` inside the loop) admits R12g's 2200 recovery; M70 admits R12f's write-off; M72 (WHEN narrowed) changes the pinned definition and fails the invariant at apply; M68 as above. M69's anchor `        IF v_future THEN\n` is unique (the first check is `IF NEW.transaction_type = 'write_off' AND v_future THEN`), so it mutates the loop check only. None passes for a wrong reason that I can see.
- N6. **Seal** (executed): tally_close's grant list is unchanged in r5 and `assert_seal_role_invariants()` passes on the clone; the widened trigger and the invariant's new check are the owner's and add nothing to the role. The grant list remains the least the close needs (nothing in r5 adds a read or a write).
- N7. **Invariant exactness** (read): the `proconfig` pin is whole-array equality, so a future `SET jit = off` on a walk would fail the invariant until the pin is re-captured. Intended strictness; worth remembering when the walks are next touched.
- N8. **Residuals R1–R12:** none blocking. R12 describes exactly what A4e/A4f show.

## Answers to the brief

1. Implemented: every P/S/G/W row and the drafting calls, as in r2–r4; the r4 findings closed by the stated mechanisms; nothing missed or half-done.
2. Paths around a rule: none found. Money in a closed period, period edits, gaps and overlaps, close order, snapshot writes, head moves and GL mappings are untouched by the diff (the battery's P/H/C/F/G rows pass, executed). Netting past the cap or below zero: refused at every date and recorded instant (R12–R12h, CR15, A4). Wrong customer or sign, loops and over-long chains: refused as before.
3. Seal: meets -20; grants exact and least (N6).
4. Snapshot: figures unchanged (C rows, CR7); edges are the tenant's at the instant by lock (CR13b, CR14b).
5. Aging: correct for the shapes above (A6: the historic tree nets to the expected balance); RLS-safe; coordinates required; unchanged in r5.
6. Invariants: the widened trigger and the walks' settings are pinned; each claim matches its check (N7).
7. Tests: no check weaker than its label; the `isfinite` leg has no catching test (N1). Missing: the users-row and money-write deadlock shapes (S1) as a stated limit, not a test.
8. Residuals: none blocking.
