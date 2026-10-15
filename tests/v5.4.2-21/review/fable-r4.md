# Fable review: v5.4.2-21 r4 (scoped to the r3→r4 diff)

**Date:** 2026-10-14. **Reviewer:** Fable. **Verdict: ready.** H1 closes my r3 B1 and every variant of it I could construct; nothing in the r3→r4 diff breaks what r3 had right; the new checks are at least as strong as their labels.

Hashes checked first, all four match the brief (`649db2b7…`, `60a45bb2…`, `9c2eb69f…`, `5a51b7cc…`). Clone `rv21fable` (TEMPLATE tally, TEMP revoked from PUBLIC, tally_app, tally_core), r4 patch strict-applied twice (second run skipped on `users.cognito_sub`), dropped at the end. No role touched; mutations not run; no repo file but this one written.

**Reproduced (executed):** `battery-21-frozen-r4.sql` 143 PASS, "complete"; `labels-21-frozen-r4.sh` LR1–LR7, LR2b, AR1 all PASS (LR6/LR7 now report B seen blocked by A and B's own `lock_timeout` surviving the 55P03).

Each claim is **executed** (run on the clone) or **predicted** (read from code and catalog).

---

## Blocking

None.

## Should-fix

None in the r3→r4 scope.

---

## Notes

- **N1. r3 B1 closed — executed.** As a `tenant_admin` of T1 against an active `platform_admin` of T1: `SET role = 'operator'` refused 42501 "only a platform administrator binds …, switches one on or off, or demotes one"; `SET role = 'operator', is_active = false` in one statement refused; `SET role = 'operator', cognito_sub = …` refused. As an operator: demoting a `tenant_admin` refused ("only a supervisor … or demotes a tenant_admin"); demoting a `platform_admin` refused. The two-step path (demote, then switch off) no longer has a first step.
- **N2. H1 completeness, the other columns (Q1) — executed.** `id`: re-keying a `tenant_admin` or a `platform_admin` is refused by `enforce_platform_admin_grant` ("a user's id is immutable"), by an operator and by a tenant_admin alike. `tenant_id`: moving an administrator to another tenant is refused by the RLS `WITH CHECK` ("new row violates row-level security policy") for operator and tenant_admin; a platform administrator may (P3, 1 row — correct, platform administration is global and the move is theirs). `email`, `display_name`: an operator changes a `tenant_admin`'s email, a tenant_admin a `platform_admin`'s (O6, T6, 1 row each). Harmless under AC-43: identity is `app.user_id`, bound by `cognito_sub`; the app never resolves a session by email. Worth one sentence in AC-43 so it stays that way. A no-op `SET role = 'tenant_admin'` on a tenant_admin by an operator is admitted (O7): the guard tests `IS DISTINCT FROM`, so an app that writes every column back does not trip it.
- **N3. What is admitted by design — executed.** A tenant_admin demotes another tenant_admin (T7), binds an unbound tenant_admin to any identity including its own second account (T8 — supervisor to supervisor, no escalation), and demotes itself (T9; afterwards `session_is_supervisor()` is false and it cannot promote itself back, T10 refused by the -13 grant guard). A platform administrator demotes and re-promotes a platform administrator (P1, P2) and may demote itself (P4). The lockout consequences (a tenant's last tenant_admin, the last platform administrator) are the r2 S2 / r3 N4 notes; AC-43 now carries the onboarding side, and the owner can always repair.
- **N4. Below the administrator line — executed.** An operator demotes another operator to `viewer` (O3, admitted). Not an administrator's power, so outside H1; whether operators may change each other's roles at all is an app-permission question, not a database rule. Mention it under R-something if a reader might expect the database to hold it.
- **N5. Did r4 break anything (Q2) — executed/predicted.** The guard's predicate gained one disjunct and the trigger one column; `a_enforce_platform_admin_grant` (role, id) and `a_enforce_tenant_admin_grant` (role) still fire before it in name order, so a grant is refused by its own guard with its own message and a demotion by this one. The wave-1 invariant string was updated to `OF cognito_sub, is_active, role`; the patch tail passes it. Battery 143 and races 9 pass. `invoice_line_arithmetic` and the void are untouched since r3 (AR1 still passes).
- **N6. New checks vs labels (Q3) — predicted.** U3k (tenant_admin demotes a platform administrator, 42501 "only a platform administrator") and U3l (operator demotes its tenant administrator, 42501 "only a supervisor") name the exact guard. U3j now reads back `is_active` after each step, so both acts are asserted, not assumed. U3m reads back `role = 'operator'` after a supervisor's demotion. LR6/LR7 require all four: B seen blocked (`pg_blocking_pids`), the 55P03 caught inside B, B's `lock_timeout` still `1700ms` after it, and the 4–7 s window; a mutation dropping either `set_config` (M53b, M60, M60b) or the lock itself (M04) fails one of them. M49d removes the role disjunct and is caught at U3k.
- **N7. R10 — predicted.** States the `now()` semantics as I described them in r3 N3 (transaction start; a reclassification committed during the issuance is not seen; a retracted-with-no-replacement item cannot be reissued, only rebilled). Accurate.

---

## What I ran

- `rv21fable`: clone, REVOKE TEMP, strict apply ×2, frozen r4 battery (143 PASS), frozen r4 races (9 PASS).
- `fable-probes-r4.sql` (one rolled-back transaction, row counts on every admitted statement): O1–O7 as an operator, T1–T10 as a tenant_admin, P1–P4 as a platform administrator.
- Clone dropped.
