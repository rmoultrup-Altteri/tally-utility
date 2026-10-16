# Fable review: v5.4.2-22 r1

**Date:** 2026-10-15. **Reviewer:** Fable (claude-fable-5-1). **Round:** 1.
**Frozen files:** all four md5s match the brief (executed).
**Clone:** `rv22fable` (TEMPLATE tally, TEMP revoked from PUBLIC/tally_app/tally_core), strict apply (`search_path=''`, `check_function_bodies=on`) twice: first applied, second skipped on the marker (executed). Dropped at the end.

## Verdict: not yet

One blocking item (B1), found by an ordinary application statement; the fix is small. Everything else is should-fix or notes.

## Reproduced (executed)

- `battery-22-frozen-r1.sql` on the clone: 115 PASS, no FAIL.
- `close-22-frozen-r1.sh rv22fable`: CR1–CR8 (14 lines) all PASS.
- Did not run `mutations-22.py` (fixed `m22` name, per the brief). The mutation list was reviewed by reading.

## Blocking

### B1. A reversal cycle makes a customer with an open balance vanish from the aging and from the snapshot's aging lines — **executed**

`tally_app` can insert two `adjustment` rows in one statement, each naming the other as `reverses_ledger_entry_id`: the FK (`reverses_ledger_entry_id, tenant_id`) is checked at statement end, `account_ledger_reversal_not_self_check` only forbids self-reference, and nothing else guards the lineage of an `adjustment` (-21 binds `void_reversal`; -22 binds `write_off_recovery`; the general rule is -23's, R8). Repro, as `tally_app` under an operator's `app.user_id`:

```sql
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
  (:a, :t, :c, DATE '2026-03-05', 'adjustment', 'cycle a', 30.00, :b, 'x'),
  (:b, :t, :c, DATE '2026-03-06', 'adjustment', 'cycle b', 20.00, :a, 'y');
-- accepted. Then:
SELECT sum(amount) FROM account_ledger WHERE customer_id = :c;            -- 50.00
SELECT * FROM receivables_aging_as_of(:t, DATE '2026-03-31', clock_timestamp()) WHERE customer_id = :c;  -- zero rows
```

Why: in `receivables_aging_as_of`, `tree` starts from roots (entries whose named parent is not in the window for the same customer) and recurses downward. A cycle has no root and is reachable from none, so its entries are in `bal` but in no `nets`/`debits`; the customer has `b > 0` yet no `bucketed` row and no credit row, so `rows_out` has nothing for it. The customer disappears from the aging, from `C`'s aging snapshot lines, and from the `entry_count` of customers — silently; the ledger balance says 50. The same holds for a cycle of any length, and for a cycle hanging off a larger chain only if the cycle itself is closed (an entry has one parent, so a cycle is always disjoint from every tree). No infinite recursion (recursion starts only at roots), so it fails quietly rather than loudly.

Fix (either; both is better):
1. In the aging, make every entry belong to some tree: after `tree`, add the unreached entries as their own roots (`SELECT id, id, customer_id FROM l WHERE id NOT IN (SELECT id FROM tree)`), or define roots as "parent not in window OR not reachable". Then bucket sums always equal the balance.
2. At insert, require the named entry to already exist (as `enforce_write_off_recovery` does: `SELECT ... WHERE id = NEW.reverses_ledger_entry_id`, NOT FOUND raises). This forbids same-statement cycles for every reversal type now rather than in -23. Add a battery check whose label is "bucket sums equal the balance for every customer" over a cycle fixture, so the mutation that drops the fix is caught at a named check.

## Should fix

### S1. The CR7 reproduction claim fails under a concurrent bucket-setting change — **executed**

Session A: `BEGIN; UPDATE tenants SET receivables_aging_bucket_days = '{15,45}' WHERE id = :t; pg_sleep(4); COMMIT`. Session B, one second later, closes January (does not wait: the tenants update touches no head). Afterwards:

| | |
|---|---|
| snapshot `aging_bucket_days` | `{30,60,90,120}` |
| `receivables_aging_bucket_days_as_of(:t, recorded_at)` | `{15,45}` |
| snapshot aging line | `0-30 = 100.00` |
| `receivables_aging_as_of(:t, period_end, recorded_at)` | bucket 1, `16-45 = 100.00` |

A's history row has `effective_from` = A's transaction start (`now()` default) = 02:10:19.28, the close's `recorded_at` = 02:10:20.33, so at `recorded_at` the history "knows" the new edges although the close could not. The snapshot's stored figures are right and self-describing (`aging_bucket_days` is on the row), so the books are not wrong; what is wrong is the header's and the table comment's claim that `receivables_aging_as_of(tenant, period_end, recorded_at)` reproduces the aging lines, which CR7 tests only without a concurrent change. The same race applies, by the same mechanism, to any "as recorded at" lookup whose stamp is the writer's transaction start (memory: "date from snapshot, knowledge from now"); the ledger avoids it only because the head lock orders writers before `v_at`.

Fix options, cheapest first: (a) state the reproduction with the snapshot's own edges and add an overload `receivables_aging_as_of(tenant, on, recorded, edges integer[])` that the close calls and that CR7 uses; (b) make a bucket change take the head FOR SHARE (BEFORE UPDATE OF `receivables_aging_bucket_days` on `tenants`) and stamp that history row's `effective_from` with `clock_timestamp()` taken after the lock, so a change that waits for a close is recorded after `v_at`. (b) alone is not enough with the current `now()` stamp (a change whose transaction started before `v_at` and updated after the close committed is still stamped before `v_at`).

### S2. The recovery cap ignores a reinstated write-off — **executed**

Charge 50 (Jan 10); `write_off` -50 naming it; `adjustment` +50 naming the write-off ("reinstated"); then `write_off_recovery` +50 naming the write-off: accepted. Balance 100 for a 50 debt. `v_recovered` sums only `write_off_recovery` rows; any other entry reversing the write-off (an adjustment, a `void_reversal`) is not counted. R-02 says a reversal is capped against what it reverses; here the write-off has already been reversed in full before the recovery. Cheapest fix: cap on `-v_wo.amount - sum(every entry naming the write-off)`, i.e. all children, not only recoveries; or refuse a recovery of a write-off that is itself named by any other reversal. R8 defers the general rule to -23, but this recovery guard is -22's and its cap is the one claim it makes.

### S3. A mistyped open period is permanent and locks the tenant's chain — **executed**

Insert `[2026-01-01, 2027-01-31]` by mistake. `UPDATE ... SET period_end` is refused ("never edited"), `DELETE` is refused ("never deleted"), and the next insert must start 2027-02-01 (no gaps). Nothing can be closed until 2027 and no correct period can be inserted: the tenant's books cannot be closed, ever, without a superuser `ALTER TABLE ... DISABLE TRIGGER`. The same follows from a first period whose start is in the future. "Never edited or deleted" is the right rule for a closed period (a snapshot stands on it) but is unjustified for an open one that is the tenant's latest, which nothing stands on. Allow DELETE of the latest open period (no snapshot, status open, `period_end` = tenant max), or allow `period_end` to change while open and latest. Add the check to the battery.

### S4. A superuser-chosen `created_at` in the future lands money inside a closed period that no snapshot ever counts — **executed**

`stamp_log_created_at` lets a superuser keep a supplied `created_at`. As `tally`: insert dated 2026-03-15 (open) with `created_at = now() + 1 day`; close March. Snapshot closing 250.00; ledger through March 31 now 1249.00; `closed_through` = 2026-03-31. The 999 row is dated in a closed period, in no activity line, in no closing balance, and will appear in a later period's `opening_balance` once its `created_at` passes (opening_{n+1} ≠ closing_n). The application cannot do this (its `created_at` is stamped; executed, E9). A superuser load that backdates `created_at` is harmless to closed periods (the date check still refuses). Only a future stamp breaks it: have `stamp_log_created_at` (or the freeze) refuse `created_at > clock_timestamp()`, for everyone. Cheap, and it closes the one superuser path the brief asks about.

### S5. The ledger freeze is INSERT-only and so stands on guards that no invariant pins — **executed (grep of tu.sql)**

`a_enforce_accounting_freeze` on `account_ledger` fires on INSERT only (right: the ledger is immutable). That makes the freeze depend on `enforce_account_ledger_immutable` (BEFORE UPDATE) and `no_hard_delete`/`no_truncate` on the ledger being present and ENABLE ALWAYS. They are today (`tgenabled = 'A'`), but I found no `assert_*` function that pins their definitions; `assert_no_hard_delete_invariants` does not name the immutable trigger, and the only ENABLE ALWAYS of it is the one-time loop at `sql/tu.sql:14480`. A later patch that drops and recreates the ledger's UPDATE guard without ENABLE ALWAYS would reopen "money dated in a closed period" through UPDATE of `transaction_date`/`amount` under replication or `session_replication_role = replica`. Add the three ledger trigger definitions to `c_triggers` in `assert_periods_guard_invariants()`; that is exactly the kind of dependency the function's comment claims to cover ("the freeze on the ledger").

### S6. Test gaps

- No race for a GL mapping insert or close in flight against a period close (the `FOR SHARE` in `enforce_gl_account_mapping` is untested; a mutation removing it would be missed). Add a CR: A inserts a mapping effective in the period being closed and holds; B closes; B waits, then A's... (or the reverse: A closes and holds, B inserts, is refused by the floor).
- No aging fixture with a reversal chain, a reversal dated before its original, or a cycle (B1). My chain probe passed: charge 100 (Jan 10), -100 reversal dated Jan 5 naming it, +100 reversal of the reversal → one row, 100 at the Jan 10 date (80 days, bucket 2) on Mar 31; on Jan 7 (only the early reversal in the window) a credit row of -100 — coherent balance-forward behaviour (executed). Pin it.
- No test that the recorded instant is taken after the head lock (a mutation moving `v_at := clock_timestamp()` above the `FOR UPDATE` would be missed: CR1's in-flight writer started before B, so its `created_at` is below either instant). Hard to test by race; at least a lexical check in the battery (`v_at` assignment text appears after the `FOR UPDATE` text in `prosrc`) would catch a reorder.
- No multi-row or writable-CTE statement in the tests. Executed here: both shapes (one row Mar 1 open, one row Feb 10 frozen; and a CTE inserting the open row then the frozen one) waited on the close and were refused whole. Add one to the battery (single session, after a close) — cheap.

## Notes

- N1. The handshake (executed and predicted). READ COMMITTED: the trigger's `SELECT ... FOR SHARE` is its own statement and re-reads the head after waiting (CR2, E6). REPEATABLE READ and SERIALIZABLE: a writer whose snapshot predates the close's commit gets 40001 on the lock (CR3); one whose snapshot already sees the moved head is refused by the date (executed, SERIALIZABLE, E12). A writer that has not touched the head yet takes it on its first money row; a writer holding FOR SHARE from an earlier statement passes a later row dated in the period being closed, but the close then counts it (`created_at` = that writer's transaction start < `v_at`), which is the intended order. `void_invoice` dates its reversal `CURRENT_DATE`, so it meets the freeze only through the head lock, never the date (predicted). `tally_core` holds no UPDATE on the head and writes nothing (predicted).
- N2. The recorded instant: `created_at` (writer's transaction start) ≤ the moment it took FOR SHARE < the close's `v_at`, for every writer the close waited for; later writers are refused or dated after. Reproducible for the ledger sums; not for the aging lines through the bucket setting (S1) nor for the customer status column (`effective_at` is `customers.status_changed_at`, caller-visible; R4 says "as recorded", but it is as-of a caller-chosen stamp — predicted, minor, the status is not in the stored lines).
- N3. Supervisor-only close. `session_is_supervisor()` reads `users.id, role, tenant_id` (and `is_active` only through the definer helpers); the three-column grant is exact (predicted from the body). `tally_close`'s table-level SELECT on `customer_state_events` and `tenant_configuration_history` could be column lists (the aging and the edges lookup read four or five columns each); `tally_void`'s table SELECT on the head could be `(tenant_id, closed_through)`. Least-privilege nits, not holes.
- N4. The seal. NOLOGIN, no BYPASSRLS, no members, exact grants, owns only the pinned definer: the re-issued invariant is -21's plus the third role and the -22 clause on the snapshot tables and the head (read side by side; predicted). A superuser can still `SET ROLE tally_close` — the known limit of the pattern.
- N5. GL mapping (executed, E11 and battery G): insert floor `effective_from <= closed_through`, close floor `effective_to <= closed_through` with `[from, to)` semantics are exactly right (a close with `effective_to = closed_through` would end the row on `closed_through - 1`, a closed day: refused; `closed_through + 1` leaves every closed day unchanged: allowed). The insert-time `effective_to <= v_through` test is redundant with `range_check` but harmless. A row's effect inside a closed period cannot change by insert, by close, or in recorded time.
- N6. Aging allocation (read + E4): sum of positive nets ≥ balance always (balance = positive nets + non-positive nets), so the newest-first allocation sums exactly to the balance; `least(net, b - (cum - net))` with `cum - net < b` is strictly positive; bucket index `count(e < age)` with `from = e[idx]+1`, `to = e[idx+1]` is right at both edges (W3 pins 120 → "91-120"). Under RLS a tenant user aging another tenant raises on the edges lookup (W1b); a platform admin ages any tenant.
- N7. `tally_app` holds UPDATE on `updated_at`, so it can also take the head `FOR UPDATE` and hold it: the close and every other writer of that tenant wait on it. A stuck application transaction holding FOR SHARE blocks the close anyway; this is not new exposure, only a note that the lock column grant is "any lock", not "share only".
- N8. Freezing `payments.payment_date` means a check received on Jan 30 but keyed on Feb 2 after January closed cannot carry its receipt date; it must be dated Feb 2 or refused. That follows D-2 ("the correction posts into an open period") and R2; worth a line in the header so the core's intake knows the rule. The freeze on a `pending` payment's date, which is not yet money, is the same choice.
- N9. `record_tenant_configuration_change` is re-issued without a `search_path` pin, as -12 wrote it; strict apply passes because plpgsql bodies are not resolved at creation. Pre-existing; the trigger runs on `tenants` only.
- N10. `assert_periods_guard_invariants()` checks triggers and the recovery CHECK; the periods and GL EXCLUDEs, `tenants_receivables_aging_bucket_days_check`, `accounting_periods_closed_stamp_check` and the snapshot's unbilled CHECK are not pinned (M30 is caught only by W10). The comment says "guards exist exactly as defined" and lists triggers, so the claim is not wider than the check; adding the CHECK/EXCLUDE names would be cheap.
- N11. Residuals R1–R9: none blocking. R2 (status move without date change) is consistent with N8. R9 is right by construction (the backfill row's `effective_from` is the patch's transaction start).
- N12. Q1 (requirements): P1–P3, S1–S2, G1–G4, W1–W3 are each built and tested as the inventory table says; W4 is an index with no check. Drafting calls 1–7 are implemented as written; call 5's netting is where B1 lives, call 6 is N2.

## Answers to the brief, in one line each

1. Implemented: yes, every P/S/G/W row; W3's cap is narrower than R-02 (S2).
2. Paths around a rule: B1 (aging, not the freeze), S3 (a period born wrong is permanent), S4 (superuser future stamp). No path for money dated in a closed period by any role, isolation or statement shape I tried (E6, E12, F1–F5, CR2–CR3); no reopen, edit, delete, gap, overlap, out-of-order or early close; no snapshot write outside the close; no backward head; no recovery past the cap of recoveries (S2 for the cap's base), wrong customer or sign; no GL change in a closed period.
3. Seal: meets -20; exact lists; `tally_void`'s grant is the least that FOR SHARE needs at table level (N3 for column level).
4. Snapshot figures: right (C9–C12, CR1b, CR7b reproduced); nothing passed in that should be computed; the unbilled figure is D-2's reported figure.
5. Aging: wrong only for a cycle (B1); right for chains and early-dated reversals (E4); coordinates required, no fallback; RLS-safe.
6. Invariants: catch what they claim; S5 names the dependency they should also pin.
7. Tests: no check weaker than its label found; no mutation passing for the wrong reason found by reading; gaps in S6.
8. Residuals: none blocking.
