# Fable review: v5.4.2-22 r2

**Date:** 2026-10-15. **Reviewer:** Fable (claude-fable-5-1). **Round:** 2.
**Frozen files:** all four md5s match the brief (executed).
**Clone:** `rv22fable2` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core), strict apply (`search_path=''`, `check_function_bodies=on`) twice: first applied, second skipped on the marker (executed). Dropped at the end.
**Read:** my r1 report, `review-findings-22-r1.md`, `diff-22-r1-r2.diff`, the four frozen files in full. Not read: any other reviewer's file.

## Verdict: ready

No blocking item. Every r1 finding I raised (B1, S1–S6) is closed by the mechanism the findings table names, and I found no new path around any of them. One should-fix (S1) is a consequence of the r2 fix for the recovery cap; it narrows what the cap admits rather than widens it, so it does not block.

## Reproduced (executed)

- `battery-22-frozen-r2.sql` on the clone: 135 PASS, no FAIL.
- `close-22-frozen-r2.sh rv22fable2`: CR1–CR10 (16 lines) all PASS.
- Did not run `mutations-22.py` (fixed `m22` name). The 52 mutations were reviewed by reading; one is discussed in N4.

## r1 findings, each checked (executed unless marked)

| r1 | r2 mechanism | Checked |
|---|---|---|
| B1 cycle vanishes from aging | `enforce_ledger_lineage_acyclic` AFTER INSERT + aging raises on uncovered entries | Multi-row VALUES (battery R8), writable CTE, a three-row cycle, COPY as the owner: each refused "returns to itself". COPY as `tally_app` is unreachable anyway ("COPY FROM not supported with row-level security"). Self-reference is caught first by -21's `not_self_check`; the walk would catch it too (predicted from the body: `up` starts at NEW.reverses = NEW.id). A legitimate three-row chain in one statement posts and ages correctly (25.00 in bucket 2). The FK is NOT DEFERRABLE, so a cycle across two statements cannot form (first statement fails on the FK). Aging with the walk disabled raises `data_exception` (battery W16). |
| S1 CR7 under a concurrent bucket change | reproduction with the snapshot's own edges; `receivables_aging_as_of(…, edges)` | CR7 now compares against `s.aging_bucket_days`; the comments no longer claim the 3-arg form reproduces. The 3-arg form reads history as before (W12); the 4-arg form validates the edges (W1d) and checks the head is visible (N2). |
| S2 reinstated write-off escapes the cap | a row naming a write_off must be a `write_off_recovery` | An `adjustment` and a `write_off` naming a write-off are both refused (battery R7; my E2b). See S1 below for the flip side. |
| S3 mistyped open period is permanent | withdrawal by status | Latest open withdrawn; a non-latest refused; closed refused; withdrawn not reopened; dates free again; chain of withdrawals (Feb', then Feb, then Jan) each latest in turn; after all are withdrawn the first period may start anywhere; after a close the replacement must start at closed_through+1 (a Mar 1 start after withdrawing Feb refused "no gaps"). Extra column changes in the withdrawing UPDATE are refused; `withdrawn_by` is overwritten with the session's user, `withdrawn_at` with `clock_timestamp()`. REPEATABLE READ refused. |
| S4 superuser future `created_at` | the close refuses while such a row exists | Battery C19 (W8's "later" row blocks March). The check covers the ledger only, which is all the snapshot counts. |
| S5 ledger immutability unpinned | pinned in `assert_periods_guard_invariants()` | Disabling `enforce_account_ledger_immutable` (ENABLE, not ALWAYS) raises; dropping `accounting_periods_no_overlap` raises with the exact definition. |
| S6 test gaps | W14 chain/early-dated; CR9 GL race; multi-row R8; C5 at UTC-12 | Present. The `v_at`-after-lock lexical check I suggested is not there (N5); the multi-row/CTE *freeze* shape is still untested, but I executed it in r1 and the mechanism is unchanged. |

## Races and lock order (executed, two sessions, B seen blocked by A via `pg_blocking_pids` in every leg)

- close(Feb) holds → withdraw(Feb) waits on the period row, then refused "never edited" (OLD.status re-read as closed).
- withdraw(Mar) holds → close(Mar) waits at `FOR UPDATE`, then refused (message: N1).
- INSERT(Apr) holds the chain advisory lock → withdraw(Mar) waits, then refused "only the tenant's latest".
- withdraw(Apr) holds → INSERT(May) waits, then refused "no gaps" (the no-gap check re-reads: latest is Mar again).
- withdraw ∥ withdraw of the same period: second waits, then refused.
- Two-tenant move: with the owner holding T1's head FOR UPDATE, a platform admin moving a pending payment T2→T1 blocks; with the OLD tenant's head held, moving it T1→T2 blocks as well: both heads are locked. A Jan-dated payment moved into a tenant closed through Jan 31 is refused by the new head (F2e covers the old head).
- No deadlock in any leg. Reasoning (predicted): the withdrawal takes the period row, then the advisory lock; the close takes head, then period; the INSERT takes the advisory lock and, because the no-gap check keeps the new row clear of every live period, never waits on the EXCLUDE for an in-flight withdrawal. No cycle among those three. The id-ordered lock in the move covers the move's own statement only; a multi-statement cross-tenant transaction that already holds another tenant's head from an earlier row can still form a cycle with two concurrent closes and an opposite-order peer — PostgreSQL detects it (40P01), it predates r2, and the header's "writers never wait for each other" stays true (N6).

## Blocking

None.

## Should fix

### S1. The recovery cap counts recoveries gross: a recovery that is itself reversed still consumes the cap — **executed**

Write-off −50; `write_off_recovery` +50 names it; an `adjustment` −50 names the *recovery* ("posted in error": allowed, it names a recovery, not a write-off); the customer's balance is back to 0 and the debt is still written off. A real `write_off_recovery` +50 is then refused: "recoveries of 100.00 would exceed the 50.00 written off". The operator's only way to record the real money is an entry that names nothing, which loses the lineage R-02 wants. r2's rule "a row that names a write_off is a recovery" is right; the cap base should be net of the recoveries' own reversals (`sum(recoveries) − sum(entries naming those recoveries)`), or, if netting through a reversal of a reversal is -23's general rule, R8 should say so explicitly ("a reversed recovery still counts against the cap until -23") so the core does not route around it with lineage-less adjustments. Not blocking: the direction of the error is a refusal, never money admitted past the cap.

## Notes

- N1. **Message for a withdrawn period at the close** (executed): `close_accounting_period(<withdrawn>)` says "is already closed; a closed period never reopens". Refused correctly (`v_p.status <> 'open'`), wrong words. Same in the race leg withdraw-then-close.
- N2. **The 4-arg aging's visibility test** (predicted): it checks `accounting_close_heads` rather than the setting; for a tenant user naming another tenant it raises `no_data_found` "not visible". Correct under RLS for both a platform admin and a tenant user; coordinates required, no live fallback, edges validated before anything is read.
- N3. **Constraints not pinned** (executed): `tenant_configuration_history_key_known_check` (re-issued by -22 with the two new keys) and -21's `account_ledger_reversal_not_self_check` can be dropped without `assert_periods_guard_invariants()` noticing. The first is a key list, not money; the second is redundant with the walk. The comment lists exactly what is pinned, so the claim is not wider than the check.
- N4. **M48 is caught by a constraint, not by the guard it names** (executed): relaxing the withdrawal branch to `NEW.status = 'withdrawn'` and withdrawing a closed period fails on `accounting_periods_closed_stamp_check` (status withdrawn with `closed_at` set), SQLSTATE 23514, before the trigger's `OLD.status = 'open'` matters. The runner still counts it (first FAIL line is P9e's). The label holds; the belt is the CHECK.
- N5. **Still untested**: the recorded instant taken after the head lock (a lexical check on `prosrc` would do), and the multi-row/CTE statement shape at the freeze (executed in r1, unchanged).
- N6. **Deadlock envelope** (predicted): see the lock-order paragraph; nothing new in r2.
- N7. **Withdrawal is any operator's act** (executed as `operator`): consistent with the period INSERT; only the close is a supervisor's. `assert_seal_role_invariants()`'s comment still says "only tally_close writes … a period's status"; the check itself was moved to `closed_at`, which is right, but the comment drifted.
- N8. **Seal** (executed via `assert_seal_role_invariants()` passing, and the catalog): tally_close NOLOGIN, no BYPASSRLS/SUPERUSER, no members either way, owns exactly `close_accounting_period(uuid,numeric,text)`, grant list exact (the 4-arg aging and `aging_bucket_days_valid` are needed inside the definer; `customers.tenant_id` is gone). Diffing the -21 body against r2's: the only changes are the third role in `c_owns`/`c_grants`/the loop, tally_void's two new head privileges, the -22 clause, and comments. `tally_void`'s table-level SELECT on the head could be `(tenant_id, closed_through)` (as r1 N3); least at table level.
- N9. **Snapshot** (executed C9–C12, C17–C18, CR1b, CR7/7b): opening < start, activity within, closing = opening + activity, count, aging lines from the stored edges; nothing passed in that should be computed; the unbilled figure is D-2's reported figure with its basis.
- N10. **GL precedence** (executed): class-only (4) beats territory+tax (3) — "CLASS" returned; battery G6b covers class vs territory. `created_at`/`closed_at` from `clock_timestamp()` (G1d, G7d).
- N11. **Pending payments** (executed, predicted): a `pending` payment in a closed period keeps a mutable amount (CI-013 freezes identity only once not pending). Pending is not ledger money and the snapshot never reads payments; the freeze's claim is about dates, which holds.
- N12. **Settings reachable** (executed): tally_app holds UPDATE on `receivables_aging_bucket_days` and `write_off_threshold_days` (table-level UPDATE on tenants); both recorded in history, the threshold born `null`.
- N13. **Residuals R1–R9**: none blocking. R8's new wording ("forbids loops for every reversal") is accurate; S1 is the one thing I would add to it.

## Answers to the brief

1. Implemented: every P/S/G/W row, plus the seven drafting calls; W3's threshold now present. Nothing missed or half-done.
2. Paths around a rule: none found. Money dated in a closed period: refused for ledger/payments/credits, owner included, both tenants on a move, every isolation (CR2/CR3), multi-row/CTE/COPY. Period reopened/edited/deleted/born closed or withdrawn: refused. Gap/overlap: refused, withdrawn periods excluded from both. Out of order/early: refused. Snapshot outside the close: refused for everyone. Head backward or by anyone else: refused. Recovery past the cap, wrong customer, wrong sign, or disguised as another type: refused (S1 is the opposite error). GL in a closed period: refused at insert and at close.
3. Seal: meets -20; the re-issued invariant is -21's plus the third role (N8); tally_void's grant is the least at table level.
4. Snapshot: right (N9).
5. Aging: right for chains, early-dated reversals, cross-customer naming, cycles (raises); RLS-safe; coordinates required (N2).
6. Invariants: catch what they claim (E6 executed); N3 for two constraints outside the claim.
7. Tests: no check weaker than its label; M48 passes on a secondary mechanism (N4); gaps in N5.
8. Residuals: none blocking.
