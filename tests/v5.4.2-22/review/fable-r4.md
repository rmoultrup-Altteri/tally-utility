# Fable review: v5.4.2-22 r4

**Date:** 2026-10-16. **Reviewer:** Fable (claude-fable-5-1). **Round:** 4.
**Frozen files:** all four md5s match the brief (executed): patch `5228060d…`, battery `e01f02aa…`, close-22 `8e49101d…`, mutations `4349c1e2…`; brief `a3b50614…`.
**Clone:** `rv22fable4` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core), strict apply (`search_path=''`, `check_function_bodies=on`) twice: the first applied, the second skipped on the marker (executed). `assert_periods_guard_invariants()` and `assert_seal_role_invariants()` called again by hand after the apply: both pass (executed). Dropped at the end.
**Read:** my r3 report, `review-findings-22-r3.md`, `diff-22-r3-r4.diff` in full, the patch's sections 1–9 and the invariants' function pin, the battery's R12–R12e, the race script's fixtures and CR13–CR15, the mutations' M22–M25 and M53–M68. Not read: any other reviewer's file.

## Verdict: ready

No blocking item. Each r3 finding is closed by the mechanism the findings table names, and I found no path that admits money past the cap, below zero, at a date or recorded instant the cap did not check, into a closed period, or around the close, the head, the snapshot or the seal. Two should-fix items: the edges lock adds one detected deadlock the header does not state (S1, executed, three sessions), and the walks' plan settings are not pinned by the invariant, so M68 is caught only by a 30 s timing (S2).

## Reproduced (executed)

- `battery-22-frozen-r4.sql` on the clone: 154 PASS, no FAIL, no ERROR, exit 0.
- `close-22-frozen-r4.sh rv22fable4`: CR1–CR15 (24 lines) all PASS.
- Did not run `mutations-22.py` (fixed `m22` name). M64–M68 and the re-anchored M23, M25, M55, M56, M62 reviewed by reading (N6).

## r3 findings, each checked

| # | r4 mechanism | Checked |
|---|---|---|
| 1 Opus B1: cap only at the end | running net by `transaction_date` over the tree, each date in [0, −amount]; a row dated on or after its parent | R12–R12d PASS (executed). My P1a: a same-date bounce and new recovery in one statement are admitted (peers of one date sum together: the net at Sep 20 is 100); P1b: the new recovery one day before the bounce is refused "on 2026-09-19 … 200.00" (executed). P2 nested write-offs below. |
| 1b author: recorded order | a tree row with `created_at` later than NEW's refuses NEW with 40001 | R12e PASS; CR15/CR15b PASS, two real sessions (executed). The prefix argument in "The cap" below. |
| 2 Codex B1: edges read without a lock | `enforce_aging_edges_close_order` takes the head FOR SHARE | CR13/CR13b, CR14/CR14b PASS (executed). The trigger is in the periods invariant's pinned list and the invariant passes (executed). tally_app is the only non-owner with UPDATE on `tenants`, and it holds UPDATE(updated_at) on the head, which FOR SHARE needs; tally_core has no UPDATE on `tenants` (executed, catalog). |
| 3 Opus S1: final join scanned | the up walk carries type and customer; both walks `enable_seqscan/hashjoin/mergejoin = off` | `pg_proc.proconfig` holds the three settings on both functions (executed). Plans on the vacuumed clone as tally_app (executed, P4): the down walk's step is `Index Scan using idx_account_ledger_reverses (reverses_ledger_entry_id = d_1.id)` in a nested loop; the up walk's and the lineage walk's steps are memoized index scans on `account_ledger_id_tenant_id_key`; the recorded-order lookup is a BitmapOr of two pkey-index probes. With the settings at their defaults on the same ledger the down walk is `Seq Scan` + `Hash Join` with the RLS functions on every row: the author's r4 observation, reproduced. |
| 4 Fable S1 / Codex S1 / Opus N1 | stated in the lock-order paragraph | Read; the wording matches what I executed in r3. |
| 5 Codex S1: claim stronger than evidence | header states measured sizes (R11) | Read. |
| 6 Codex S2 tests | R12 shapes; Codex probes n9/n10 | Present and passing (executed). |
| 7 Opus N4: no mutation on the up step | M56 on `WHERE u.mine AND u.depth < c_max`; M68 on the settings | Read (N6). |

## The cap at every (date, recorded instant)

- **Dates (executed and predicted).** The window `sum(amount) OVER (ORDER BY transaction_date)` with its default RANGE frame sums every row of a date together, so each distinct date's net is the net of the rows dated on or before it, which is what `receivables_aging_as_of(tenant, D, T, edges)` nets into the root on D (the `tree` CTE joins on `reverses_ledger_entry_id` within the customer, over rows dated ≤ D). The date-order rule (`NEW.transaction_date >= parent's`) makes every tree row's ancestors fall inside any date window that holds the row, so no tree row becomes its own root in aging; without it, an earlier-dated recovery would age as a fresh debit (Opus's B1). The rule applies only where a write-off is above (R8 says so).
- **Recorded instants (predicted; CR15 executed).** The check runs under the write-off's advisory lock at READ COMMITTED, so it sees every committed tree row. It refuses NEW when any tree row (or the write-off) has `created_at > NEW.created_at`. Hence the rows admitted, ordered by `created_at`, are the order in which the cap checked them; the set visible at any instant T (`created_at <= T`) is a prefix of that order, and each prefix passed the per-date check. Combined with the date filter, the state at (D, T) is a date-prefix of a checked prefix, which the per-date check covered. Equal `created_at` across transactions (same `now()` to the microsecond) is admitted; the second-checked saw the first, so the shared instant shows the checked state.
- **Caller's `created_at` (executed, P3).** `a_stamp_created_at` (BEFORE INSERT, ENABLE ALWAYS) sets `created_at := now()` unless `current_user` is a superuser. tally_app asked for `now() + 1 day` and got `now()`. The owner's value being kept is not a hole for the cap: a superuser's future stamp still leaves every instant seeing a checked prefix (later rows are refused until the stamp passes, N3); a past stamp is refused by the check itself.
- **Nested write-offs (executed, P2).** W1 −100 (Sep 1); R1 +100 (Sep 10); W3 −100 (Oct 1) names R1; R3 +100 (Oct 5) names W3: admitted. A bounce of R1 dated Sep 15 is refused "on 2026-10-01 … −100.00": on Oct 1 W3 would have written off a receivable the bounce says was never recovered, which is the inconsistency the per-date cap exists to refuse. The same bounce dated Oct 10 is admitted. The backdated bounce is admitted after W3 is unwound (bounce R3 on Oct 5, recover W3 +100 on Oct 1): four rows, each in date order and within both caps. See N1.
- **Other customer's rows, loops, isolation:** unchanged from r3 (R10f, E2, E4c, E8 then); the diff touches none of those branches.

## Lock order

- **Writers under two write-offs:** stated now, as asked in r3.
- **The edges lock (executed, three sessions, P5):** session A (tally_app) holds the open August period FOR UPDATE (a withdrawal's lock); the close S takes the head FOR UPDATE and waits on A for the period row; session B (tally_app) updates the tenant's `slug` (a key column, unique index `tenants_slug_key`: a FOR UPDATE row lock), then its aging edges, and waits on S for the head. A commits; S reaches its snapshot-line insert, whose FK `accounting_period_snapshot_lines_tenant_fkey` takes the tenant row FOR KEY SHARE, held by B: **deadlock detected**, the close aborted (`DeadLockReport` on the `FOR KEY SHARE OF x` RI statement), nothing written (August still open); B committed its slug and edges. Without A the window is the close's few milliseconds, but it exists. A non-key edges change alone (CR13/CR14) takes FOR NO KEY UPDATE, which KEY SHARE does not conflict with; the shape needs a key update of the tenant row in the same transaction, before the edges change. See S1.
- **The close's other KEY SHARE** is on `users` through `accounting_period_snapshots.closed_by` (predicted): a transaction that key-updates a user row and then changes the edges has the same shape.

## Blocking

None.

## Should fix

### S1. The edges lock and the close's FK lock on the tenant row can deadlock — **executed**

Order B: tenant row (key update, FOR UPDATE) → head FOR SHARE; close: head FOR UPDATE → tenant row FOR KEY SHARE (the snapshot-line FK). The header's lock-order paragraph says the edges change "holds the tenant row, and the close never locks the tenant row": the close's FK checks do. Same class as the withdraw-and-close deadlock the header states: detected, one side aborted, nothing admitted. State it there ("a key update of the tenant row and an edges change in one transaction, against a close, can deadlock; the close is retried"). Optional and cheap: point `accounting_period_snapshot_lines`' tenant FK at `accounting_periods(id, tenant_id)` as the snapshot's own FK does, so the close's KEY SHARE falls on the period row it already holds and the tenant leg disappears (the `users` leg remains; the statement covers it).

### S2. The walks' plan settings are not pinned — **executed (catalog), predicted (mutation)**

`assert_periods_guard_invariants()` pins the triggers by definition and nothing about the two walk functions' `proconfig`. M68 (the settings dropped) is caught only when R10g exceeds 30 s on a just-vacuumed ledger: a faster machine, a different autovacuum moment or a planner change lets the mutation pass, and in production a `CREATE OR REPLACE` without the settings would go unnoticed until a slow close. Pin `proconfig @> ARRAY['enable_seqscan=off','enable_hashjoin=off','enable_mergejoin=off']` for `enforce_write_off_recovery` and `enforce_ledger_lineage_acyclic` in the invariant (the seal invariant already pins `search_path` this way); M68 is then caught at apply.

## Notes

- N1. **Backdated corrections under a nested write-off** (executed, P2): a bounce dated before a later write-off that depends on the recovery is refused, and must be posted after that write-off is unwound in date order. That is the per-date cap doing its job; the four-row path exists. Worth a line in R8 so an operator's refusal is explained.
- N2. **The 40001 retry is not wait-free** (predicted): each refusal means another writer committed into the same tree between this writer's start and its lock, so one writer always progresses, but a transaction that runs long before its ledger insert can be starved by short writers to the same write-off. At the product's volumes (a few recoveries per write-off, ever) this is theoretical.
- N3. **A superuser's future `created_at`** on a tree row (predicted) refuses every later row of that tree until the stamp passes; a past one is refused outright. Same class as r2's close check on a superuser's chosen `created_at`; no money admitted.
- N4. **Scope of the plan settings** (executed, P4): inside the functions they also govern the RLS policy functions (pkey lookups on `users`), the three per-row lookups by id and the `id = ANY(tree)` queries; all are index or bitmap-index plans. No other statement runs inside them, and the settings are restored on exit. No step can choose a sequential scan while an index path exists; every step has one (`account_ledger_pkey`/`account_ledger_id_tenant_id_key`, `idx_account_ledger_reverses`, whose partial predicate the join condition implies).
- N5. **The up walk's `mine` on the first row** (read): a parent of another customer yields `mine = false` and the walk stops before stepping, so the recovery's own customer check (the FK-shaped refusal above it) stays the only rule for a cross-customer name; consistent with r3 N1.
- N6. **Mutations** (predicted from reading): M64 admits R12b's early recovery; M65 (`OVER ()`) nets R12 to 100 at the end and admits Feb 20; M66 admits R12e; M67 drops the share lock so CR13's close takes its instant with the old edges and stores them; M23/M55 re-anchored to the window's `WHERE`; M25 to `v_wo_id`; M56 to `WHERE u.mine AND u.depth < c_max`; M62 to `array_agg … WHERE d.mine`; M68 see S2. The runner's first-FAIL rule holds for each; none passes for a wrong reason that I can see.
- N7. **The close's edges read** (read): after the head FOR UPDATE, with every edges change holding the head FOR SHARE, the `SELECT … FROM tenants` sees the edges in force at `v_at`; CR13b/CR14b show both sides. R10's new sentence (the waiting change's history row dated at its own start) is accurate and the snapshot's stored edges remain the record.
- N8. **Seal** (executed): `tally_close`'s grants are unchanged in r4; `assert_seal_role_invariants()` passes on the clone. The edges trigger is invoker-rights and adds nothing to the role.
- N9. **Residuals R1–R11:** none blocking. R8's new sentence is right; R11 states what was measured and no more (and P4 shows why the pin matters).

## Answers to the brief

1. Implemented: every P/S/G/W row and the drafting calls; the r3 findings each closed by the stated mechanism; nothing missed or half-done.
2. Paths around a rule: none found. Money in a closed period, period edits, gaps/overlaps, close order, snapshot writes, head moves and GL mappings are untouched by the diff (executed in r2/r3; the battery's P/H/C/F/G rows still pass). Netting past the cap or below zero: refused at every date and recorded instant (R12–R12e, CR15, P1, P2). Wrong customer or sign: refused. Loops and over-long chains: refused.
3. Seal: meets -20; grants exact and least (N8).
4. Snapshot: figures unchanged (C9–C12, C17–C18, CR7); the edges are the tenant's at the instant, now by lock (CR13b, CR14b).
5. Aging: correct for the shapes above; RLS-safe; coordinates required; the date-order rule keeps every tree row's root inside any window that holds the row.
6. Invariants: the new trigger is pinned; the walk functions' settings are not (S2).
7. Tests: no check weaker than its label; M68's catch is timing-based (S2). Missing: the key-update-then-edges deadlock shape (S1), a nested write-off with a backdated bounce (P2).
8. Residuals: none blocking.
