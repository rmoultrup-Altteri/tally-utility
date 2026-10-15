# Fable review: v5.4.2-21 r2

**Date:** 2026-10-14. **Reviewer:** Fable. **Verdict: not yet** — one blocking item, in the r2 change that moved the arithmetic check onto the snapshot coordinate. Everything I raised in r1 is fixed and fixed correctly.

Hashes checked first, all four match the brief (`11aad26f…`, `08c7fd59…`, `2a3c8dad…`, `9e679180…`). Clone `rv21fable` (TEMPLATE tally, TEMP revoked from PUBLIC, tally_app, tally_core), r2 patch strict-applied twice (second run skipped on `users.cognito_sub`), dropped at the end. No role touched; `mutations-21.py` not run; no repo file but this one written.

**Reproduced (executed):** `battery-21-frozen-r2.sql` 131 PASS, "complete"; `labels-21-frozen-r2.sh` LR1, LR2, LR2b, LR3–LR6 PASS (LR6 gave up at 5 s).

Each claim is **executed** (run on the clone) or **predicted** (read from code and catalog).

---

## Blocking

### B1. The snapshot's `recorded_at` is the caller's to choose inside a window, and choosing it hides a reclassification — executed

r2 reads the arithmetic at `(v_snap.valid_at, v_snap.recorded_at)` (F2). `valid_at` is bound by -10 (`period_end`, or the elected rate date). `recorded_at` is only bound to `[created_at, now()]` for an off-run bill and `[run.started_at, now()]` on a run. Anything recorded about a rate item *after* the chosen instant is invisible to the check.

Repro (`fable-coord-r2c.sh`, three committed steps then a rolled-back issuance, all as `tally_app`):
1. Rate item FLIP8: version `fixed_monthly` from 2026-01-01, recorded T0. Draft bill, `created_at` = T0, with a surcharge line on FLIP8 and no figures.
2. 1.2 s later: the version is closed (`retracted`) and a correction `per_unit_usage` from 2026-01-01 is recorded at T1.
3. Snapshot at `(period_end, created_at)` — admissible, `recorded_at` is not before `created_at` and not in the future. `invoice_line_arithmetic_gap` at the snapshot coordinate: **NULL (needs nothing)**. At `(period_end, now())`: `usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed`. `UPDATE … status = 'pending'; SET CONSTRAINTS ALL IMMEDIATE`: **issued**, status `pending`.

This is the exact shape of Codex's r1 B2 with the other axis: there the line was classified at a date where the item was a different kind; here at a knowledge instant where it was. The surcharge sibling avoids it on purpose — its comment: "the snapshot's pair is caller-supplied … and would let a backdated coordinate hide the rule or the rider's calculation type (Fable HIGH-2)" — and reads `(period_end, now())`. r2 took the arithmetic check off that footing.

Fix: take the **date** from the snapshot and the **knowledge** from now: `invoice_line_arithmetic_gap(v_line, v_snap.valid_at, now())`. That keeps F2 (A7 still refuses: JF is per unit at 2026-02-28 under current knowledge) and closes this. A retracted classification is retracted; the figures a line must carry are judged by what the item is now known to have been on the rate date. Re-point M46 to `(NEW.period_end, now())` (it still catches at A7) and add a race-script case for `recorded_at` (two committed instants are needed; one transaction cannot show it, since every `recorded_at` is `now()` there). Note in passing (predicted, pre-existing): `line_item_carries_base` in the sibling still classifies at `period_end`, not the elected date, so Codex's B2 applies to the base-composition rule as well; a follow-up, not this patch.

---

## Should-fix

### S1. U3e's label — predicted
"an operator creates a user already bound": the sub `operators-second-account` is bound to nobody. The row proves "an operator inserts a bound user" (42501), which is the right test; rename it.

### S2. The onboarding consequence of F4 needs one more sentence — predicted (for Ryan, Q4)
Correct on the merits: `AdminCreateUser` returns the sub, so a supervisor's session binds at provisioning. Two things to state in AC-43 so the app is built to them: (a) self-signup / federated first-login provisioning cannot bind — if the product ever wants it, the binding would run under a service identity that is a supervisor, and that identity is then the self-promotion path F4 closes, so it must stay out of operators' reach; (b) a tenant's last active `tenant_admin` can switch itself off (P5a-style, as a supervisor) and the tenant is then re-opened only by a platform admin. Both are acceptable; both should be written down.

### S3. `reverses_ledger_entry_id` on a non-void row is still free — executed
P3d: an `adjustment` with `reference_type = 'manual'` naming an entry it "reverses", no reason: admitted. R2 covers void reversals; say in R2 that the link column on any other transaction type is unguarded (or add `reverses_ledger_entry_id IS NULL OR transaction_type = 'void_reversal'` if nothing else is meant to use it — predicted: nothing in tu.sql writes it outside the void).

---

## Notes

- **N1. r1 B1 fixed — executed.** Rename, re-point (`entity_type`), `type_key` rename, each followed by DELETE: refused 23001 "keeps its key, entity and tenant" (P1a–c). The owner too (P1f). A writable CTE that deletes and re-inserts the key in one statement: refused by the in-use guard (P1e). `id` of a label stays writable (P1d); nothing references it, harmless.
- **N2. r1 B2 fixed — executed.** Item with no version: gap "a classification: rate item … has no version visible at (…)" (P2a); per-unit item before its first version: same (P2b). With a snapshot, issuance refused 23514 listing the seven figures (P2c); with no snapshot, `enforce_invoice_has_snapshot` refuses first, no fallback (P2d).
- **N3. r1 S3 — executed.** Same entry reversed twice: 23505 `account_ledger_one_void_reversal_per_entry` (P3b). Adjustment filed as `invoice_void`: 23514 `account_ledger_void_reversal_reference_check` (P3c). A void_reversal naming a payment entry still admitted (P3a), as R2 now says.
- **N4. r1 S1 — predicted.** The header now names both deadlock shapes, the SHARE cost and the 5 s bound. The different-labels deadlock itself is unchanged (40P01, r1 E5); the header is right about it.
- **N5. r1 S2 — executed.** Born-unvoided set origin-only: `assert_wave1_guard_invariants()` raises 0LP01 naming the trigger (P7a). Labels' `no_truncate` disabled (P7b) and key freeze origin-only (P7c): `assert_no_hard_delete_invariants()` raises, naming table and guard.
- **N6. r1 S4 — executed.** A4j passes in the battery; the comment states the two-figure reading.
- **N7. r1 N7 — executed.** `retired_by` is `app.user_id` whatever the caller supplies (P9: b2 supplied, b1 stamped). The owner with no session user retires with `retired_by` NULL (P9b) — fine for a superuser repair; the comment could say so.
- **N8. lock_timeout save/restore (Q2) — executed.** Session `lock_timeout = 9s`: inside the transaction after a successful delete, 9s; after commit, 9s. Failure: A holds `customers`, B sets `SET LOCAL lock_timeout = '3s'`, deletes under a savepoint, gets 55P03 after the guard's 5 s, rolls back to the savepoint: `lock_timeout` is 3s (the caller's local value, the subtransaction rollback undid the guard's `set_config`); after commit, 9s. No leak either way. Note the guard's 5 s overrides a caller's *shorter* local timeout for the LOCK statement only (3s → 5s here); acceptable, but say "waits 5 s regardless of the caller's lock_timeout".
- **N9. The supervisor guard (Q2) — executed.** Operator deactivates itself: refused (P5a). Operator inserts an unbound `tenant_admin`: refused by -13 (P5b). `INSERT … ON CONFLICT DO UPDATE SET cognito_sub` on the unbound admin: refused (P5d). Operator sets its own role: refused by -13 (P5e); `platform_admin` has its own grant guard (`a_enforce_platform_admin_grant`, catalog). A T1 supervisor binding T2's unbound admin: 0 rows under RLS (P5f). Empty `app.user_id`: 22P02 from the uuid cast, fail-closed as AC-43 says (P5h). The owner binds and switches with no session user (P5i). Other roles: `tally_core` holds no UPDATE on users; `tally_seal`/`tally_void` hold nothing on users (seal invariant R6). The guard keys on `current_user = 'tally_app'` like `enforce_tenant_admin_grant`; consistent.
- **N10. Key freeze (Q2) — executed/predicted.** Frozen for every role including the owner (P1f). `UPDATE … SET tenant_id` refused (battery L6e). A new label with the old key cannot coexist (`UNIQUE (tenant_id, entity_type, field_key)`), so "add a new label and archive this one" means a new key — the message is right.
- **N11. Did r2 break anything (Q3) — executed/predicted.** The battery's `issue()` now snapshots first; the A-cases still pass. `enforce_invoice_line_arithmetic` returning NULL without a snapshot leans on `enforce_invoice_has_snapshot` being ENABLE ALWAYS (it is, 'A'). -15 C8b (owner meets the -15 guard, 23001) and -20 I1 (rate 100.00) keep their purpose. LR6's 4–7 s window around an 8 s hold is comfortable on this machine; on a loaded CI runner `date +%s` granularity makes 4 s the tight edge — consider `[ "$EL" -ge 4 ]` only, or measure with `%s%N`.
- **N12. F11 (Q4) — predicted.** Right on the merits: a rider's arithmetic is `usage_quantity × rate`; the commodity rate is the usage line's.
- **N13. Mutations (Q5) — predicted.** 62 named checks read right. M46 proves the date axis (A7); nothing proves the knowledge axis (B1). M53 removes only the first `set_config` — the location-type branch keeps its 5 s wait, so a mutation that drops the second branch's timeout passes; add M53b on `LOCK TABLE public.service_locations` or test LR6 on a location type.

---

## What I ran

- `rv21fable`: clone, REVOKE TEMP, strict apply ×2, frozen r2 battery (131 PASS), frozen r2 races (7 PASS).
- `fable-probes-r2.sql` (one rolled-back transaction): P1a–f, P2a–d, P3a–d, P5a–i, P7a–c, P9, P9b.
- `fable-lock-r2.sh`: lock_timeout on success and on 55P03 under a savepoint (two sessions).
- `fable-coord-r2c.sh`: B1 (three committed steps, issuance rolled back).
- Clone dropped.
