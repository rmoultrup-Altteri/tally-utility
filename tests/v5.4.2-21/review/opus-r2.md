# v5.4.2-21 r2 — Opus review

**Verdict: not yet.** One blocking item. My r1 B2 is fixed for operators, but the same self-promotion still works one level up: a tenant admin can become a platform admin. Every other r1 finding of mine is fixed, and I re-ran each repro to check.

**Hashes checked first.** All four frozen r2 files match the brief: patch `11aad26f…`, battery `08c7fd59…`, labels `2a3c8dad…`, mutations `9e679180…`.

**Clone.** `rv21opus`, cloned from `tally`. TEMP was revoked from PUBLIC, `tally_app` and `tally_core`. The frozen r2 patch was applied strictly. The clone is dropped at the end.

**Reproduced (executed):**
- Strict apply, twice. The second run is skipped by its marker.
- `battery-21`: 131 PASS, no FAIL.
- `labels-21.sh` on `rv21opus`: LR1–LR6 and LR2b PASS.

**Not reproduced:**
- `ci.sh`, because of the shared `ci_*` database names.
- `mutations-21.py`, which the brief forbids.

The probes ran the battery's own r2 preamble (fixtures, `issue()`, `snap()`) and then mine, all as `tally_app` under `app.user_id` unless stated otherwise.

---

## Blocking

### B1. A tenant admin can revive or bind a platform administrator, and becomes one — executed

`enforce_user_binding_by_supervisor` accepts any supervisor for any target. A tenant admin passes `session_is_supervisor()`. Platform admin rows live in a tenant (`users.tenant_id`; the battery's own `OldAdmin` is in T1), so the tenant admin's RLS shows them. Session as T1's tenant admin `Sup` (b4):

- **E1.** `Sup` sees the deactivated, unbound platform admin `OldAdmin` (ba).
- **E2.** `UPDATE users SET is_active = true, cognito_sub = 'tadmin-alt' WHERE id = ba`: **ACCEPTED**.
- **E3.** With `app.user_id` set to the user bound to `tadmin-alt` (what AC-43 does at login), `is_platform_admin()` is **true**.
- **E4.** That session sees **tenant 2's** customers.
- **E5.** `Sup` deactivates the active platform admin (b9): **ACCEPTED**.
- **E6, the control.** `Sup` inserting a user with role `platform_admin` is **refused** by `enforce_platform_admin_grant`: "only a platform administrator may grant the platform_admin role — a tenant session that could promote itself would hold every platform-only control".

So E2 reaches exactly what E6 refuses, without touching `role`. It is the r1 B2 shape one level up:
- A tenant admin crosses every tenant.
- It can also switch the platform's administrators off.

Binding an *active* unbound platform admin takes the same code path (predicted).

**Fix:** in `enforce_user_binding_by_supervisor`, when the target is a platform administrator (`OLD.role = 'platform_admin'` on UPDATE, `NEW.role` on INSERT), require `is_platform_admin()`, not `session_is_supervisor()`. Apply it to binding and to `is_active` in both directions. This mirrors `enforce_platform_admin_grant` exactly. Add battery rows for E2 and E5 as a tenant admin, and a mutation that drops the clause.

Optional, a question for Ryan: whether a tenant admin may switch off *another* tenant admin. That is a peer act. I would leave it allowed.

---

## Should fix

### S1. Nothing tests that the lock wait is restored

I executed the restore myself, and it is right:
- **Success path.** `SET LOCAL lock_timeout = '1min'`, delete an unused label: afterwards `lock_timeout` = `1min`.
- **Failure path.** Session A held a customers write for 16 s. B's label delete under `SAVEPOINT` timed out at 5.0 s (`canceling statement due to lock timeout … LOCK TABLE customers IN SHARE MODE`). After `ROLLBACK TO`, `lock_timeout` = `1min`.
- **Inside a PL/pgSQL EXCEPTION block** that caught 55P03, it was also `1min`. The subtransaction rollback undoes the guard's `set_config(…, true)`.

So nothing leaks, on success or on failure. But LR6 checks only the 5 s refusal: a mutation that drops either restore line would pass every test (predicted). Add a battery row: set `lock_timeout` local, delete an unused label, assert the value afterwards.

### S2. The guard *raises* a shorter caller timeout to 5 s — predicted

A caller running with `lock_timeout = '1s'` now waits up to 5 s inside the guard. Consider `least(current, 5s)`, treating 0 as infinite. Minor.

---

## My r1 findings re-run against r2 (all executed)

| r1 | Repro | r2 result |
|---|---|---|
| B1 | A surcharge on an item with no version at the coordinate (P-A4x), or on tenant 2's item (P-A4y), with no figures. A snapshot was written first by `issue()`. | Refused: "missing a classification". **Fixed.** |
| B2 | An operator binds an unbound tenant admin, revives a deactivated one, or inserts a user already bound. | Refused 42501 each time. **Fixed for operators**, but see B1 above. |
| B3 | Rename the field key; rename the type key; re-point `entity_type`; the owner renames. | Refused 23001 each time. Archiving and relabelling are still accepted. **Fixed.** |
| S1 | A void whose only charge entry is another customer's. | Refused P0002 ("no charge entry"). **Fixed.** |
| S2 | An `adjustment` against `invoice_void`; a `void_reversal` against `manual`; a `void_reversal` with a NULL `reference_type`. | Refused by `account_ledger_void_reversal_reference_check` each time. **Fixed.** |
| S3 | The deadlock and queueing note. | Header rewritten: it states both deadlock shapes and the queueing while the delete waits. Bounded at 5 s (LR6, and my own run above). **Fixed.** |
| S4 | `retired_by` set to tenant 2's user. | Stamped as the session's user (b1). **Fixed.** |
| S5 | Invariant and test gaps. | The labels' three guards are in the retention invariant, `assert_wave1_guard_invariants()` is new, C8b runs as the owner, and LR2b is added. **Fixed**, apart from S1 above. |

---

## Notes

- **N1. The snapshot coordinate: can a caller choose it?** Only inside the window that has been validated since -10 (predicted, from `calculation_snapshot_coordinate_violation`):
  - `valid_at` is pinned: the period end for an ordinary bill, the recorded election for a correction.
  - `recorded_at` falls in [run start, or the draft's `created_at`, … now], or equals the replaced bill's snapshot instant.
  - So the only room is a reclassification of the item recorded *during the bill's own drafting window*, and the snapshot is then the coordinate the price claims to use. I accept F2.
  - The arithmetic check and the surcharge sibling now read different coordinates. The sibling's comment rejects the snapshot pair as caller-supplied. That comment is now a stated difference, not an error, but a line in the arithmetic function's comment saying why it may use the pair (frozen and bounded since -10) would stop the next reader tripping on it.
- **N2. With no snapshot the check returns NULL** and defers to `enforce_invoice_has_snapshot`, which exempts no role. A born-issued bill cannot get a snapshot (r1 N1, executed then), so this falls back onto no live columns. It is correct.
- **N3. The supervisor guard's other paths.**
  - Keying on `current_user = 'tally_app'` is sound today: `tally_app` is NOLOGIN with no members, and `tally_core` holds no INSERT or UPDATE on `users` (catalog, executed).
  - No definer function updates `users` (catalog, executed).
  - The INSERT path is covered (B2c refused).
  - A platform admin of another tenant may bind anyone. That is by design, since a platform admin is global.
  - The owner stands aside, as in -13.
- **N4. Nothing r1 had right is broken** that I can find. `void_invoice()` is the only function that writes `void_reversal` or `invoice_void` (catalog, executed), so the new CHECK and the one-per-entry index break no writer.
- **N5. The two drafting calls are right on the merits.**
  - **F4.** Cognito's admin create returns the sub, so a supervisor binding the user at provisioning is workable. AC-43 now says so. Self-signup was never in scope for utility staff.
  - **F11.** A per-Ccf rider has no commodity rate. Requiring one would force a meaningless figure, and the rider's own price is `rate`.
- **N6. Tests.** The new rows match their labels as far as I read them: L6a–e, A4g/h/j, A7, G2e–g, V1e–g, K3e, U3a–g, U1f, LR6. The one gap is S1. A U3 row for a tenant admin against a platform admin is missing, which is B1.
