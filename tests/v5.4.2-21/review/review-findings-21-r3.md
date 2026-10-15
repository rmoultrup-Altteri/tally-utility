# v5.4.2-21 review round 3: findings and their disposition

**Verdicts on r3** (patch md5 `57f2d1f0`): Codex "ready"; Opus "not yet"; Fable "not yet", on the same item.
- Codex's two probes were run by the author and appended to `codex-r3.md`; both matched its predictions. One refusal there fails on the probe's own fixture.

## Blocking

| # | Finding | Who | Disposition in r4 |
|---|---|---|---|
| H1 | A role-only UPDATE demotes a tenant_admin (even by an operator) or a platform administrator (by a tenant_admin). It switches the supervisor off through the column the r2/r3 guard did not watch. | Opus B1, Fable B1 (both executed) | The supervisor guard also fires on `role`. Taking a user out of tenant_admin needs a supervisor; out of platform_admin, a platform administrator. U3k, U3l, U3m; mutation M49d. Granting stays the -13 guards'. |

## Should-fix

| # | Finding | Who | Disposition |
|---|---|---|---|
| H2 | LR6/LR7 never observe B blocked by A, and do not check the caller's setting after a contended timeout. | Codex S1 | Both legs now run B in the background, observe `pg_blocking_pids`, and catch the 55P03 inside B, reading its own `lock_timeout` (1700ms survives). |
| H3 | U3j treated a zero-row UPDATE as success. | Codex S2 | Reads back the state after each step. |
| H4 | "Current knowledge" is the transaction's start; a historical rebill of a since-reclassified item must carry current figures, and one retracted without a replacement cannot be reissued. | Codex N2/N3, Opus | Residual R10, by the fail-safe ruling. |
