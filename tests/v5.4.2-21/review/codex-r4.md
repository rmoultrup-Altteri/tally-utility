# Codex — v5.4.2-21 r4

Verdict: **ready** (predicted, source-only, scoped to r3→r4).

Checked all four MD5 hashes before reviewing the changes; all match the brief:

| Frozen file | MD5 |
|---|---|
| patch-21-frozen-r4.sql | `649db2b7094e585adde761f69a89a126` |
| battery-21-frozen-r4.sql | `60a45bb255ce9b5ede13ab6d61f5e7ce` |
| labels-21-frozen-r4.sh | `9c2eb69f2ee7c8da5fd714f2af49993c` |
| mutations-21-frozen-r4.py | `5a51b7cc5a92ccd9a005d022db815184` |

Read the brief, r3 disposition, supplied patch diff, actual frozen test diffs, my r1–r3 reviews and appended author outputs, and the relevant underlying identity, RLS and retention definitions. No Docker, database, strict apply, CI, race or mutation execution is claimed. The reported totals remain author evidence. **Predicted** denotes source reasoning; **probe 01** denotes the unexecuted SQL handoff below. No other reviewer's r4 was consulted.

## Blocking items

**B1 — predicted: none found in the scoped changes.** H1 closes the role-only removal paths previously missed by my r3 review. The previous distinction between demotion and switching an administrator off was insufficient for the stated protection; r4 correctly treats both as authorization acts. No additional removal path was identified through the requested columns under the existing app-role and trusted-session contract. Probe results should be assessed before treating these predictions as runtime evidence.

## Should-fix items

**S1 — predicted: update M53/M53b's descriptions to match the revised timeout tests.** Their labels still say the lock “waits without limit.” With r4's caller setting of `1700ms`, removing the guard's five-second override leaves a finite 1.7-second timeout. LR6/LR7 should catch this through their four-to-seven-second elapsed-time requirement, while still reporting restoration to 1700ms. This remains a meaningful behavioral catch of a missing five-second override; it no longer demonstrates an unlimited wait. Rename the descriptions accordingly. This is a test-description issue, not a patch blocker.

## Notes

**N1 — probe 01: H1 covers the full requested removal matrix in conjunction with existing guards.** The new trigger watches `role` and its function tests an actual departure from either OLD administrator role (`patch-21-frozen-r4.sql:1059–1088`). Its platform branch considers OLD as well as NEW. Consequently:

| Path | Predicted enforcement |
|---|---|
| Operator demotes tenant_admin | Supervisor gate, 42501. |
| Tenant_admin demotes platform_admin, including to tenant_admin | Platform gate, 42501. The grant permission for NEW tenant_admin does not authorize removal of OLD platform_admin. |
| Change `is_active` | Existing supervisor/platform checks still run in either direction, using OLD platform status too. |
| Change or clear an established binding | Supervisor/platform authorization plus the independent write-once guard; even an authorized supervisor cannot clear a non-NULL binding. Initial binding remains supervisor/platform controlled. |
| Change `id` alone or with other fields | Existing -12 `a_enforce_platform_admin_grant`, which watches `id`, rejects every app re-key (`sql/tu.sql:21968–22003`). No FK dependency is needed for this protection. |
| Move a target to another tenant | `users.tenant_isolation` uses the canonical predicate for both visibility and the implicit WITH CHECK (`sql/tu.sql:11300`). A non-platform session cannot write a foreign tenant_id; NULL also fails the schema. Moving within its own tenant changes no authority. Platform-authorized moves remain possible. |
| DELETE/reinsert or TRUNCATE | Existing -01 users retention guards/privilege revocations prevent removal; UPDATE guards need not implement these operations. |

Combining a role departure with binding, activation, id or tenant changes does not suppress the OLD-role check. An unchanged assignment is harmless and does not authorize the next statement. Splitting demotion/deactivation, re-key/demotion or tenant-move/demotion into two statements cannot get past the unauthorized first transition. A platform administrator can legitimately demote a platform row; a tenant supervisor can then manage that now-ordinary user. That is an authorized removal followed by ordinary management, not an unauthorized bypass. The rules do not enforce lifetime platform-role history or a last-administrator quorum.

Tenant membership is not frozen universally: a platform session may move an administrator and thereby remove its access to the old tenant. That caller already has authority to demote/deactivate the target. A tenant supervisor cannot use this permission. Changes to display name, email or preferences do not affect the database's role/id/active/binding lookup; any separate external identity workflow is outside this SQL contract.

**N2 — predicted: no source regression found in the new guard or invariant.** Merely listing `role` in UPDATE now invokes the guard, but unchanged roles with unchanged binding/activation return without demanding new authority. Existing promotion guards still authorize grants. Tenant_admin→platform_admin requires both the supervisor condition and the independent platform grant check; platform_admin→tenant_admin still requires platform authority. Authorized demotions of other users remain allowed. The trigger's ENABLE ALWAYS state remains, and the invariant string matches the expanded column list. Owner repair exceptions and the requirement to operate as `tally_app` are unchanged.

**N3 — predicted: H2 now establishes the named contention and surviving setting.** Both LR6 and LR7 start B in the background, call `waiting()` to observe B blocked by the named A backend, catch `lock_not_available` inside B, and print B's own `current_setting('lock_timeout')` after exception-subtransaction rollback. The success condition requires that observation, the exact 1700ms notice, and the expected elapsed interval. A zero-row DELETE or a successful DELETE supplies no timeout notice and cannot pass. One-second startup sleeps and wall-clock bounds still permit scheduler-related false failures; they no longer substitute for blocker evidence. This is source validation of the harness, not independent evidence of a completed race run.

**N4 — predicted: H3 and the new H1 battery checks support their labels.** U3j reads the target after activation and again after deactivation; `pg_temp.ok` rejects NULL as well as false. The inactive fixture makes a zero-row revival fail, and a zero-row switch-off after a successful revival also fails. U3m starts with a tenant_admin fixture and reads back `role = 'operator'`; zero rows cannot silently satisfy that transition. U3k/l require the correct SQLSTATE and guard diagnostic. M49d removes the demotion predicate and points to U3k, a forbidden demotion that would then be admitted, rather than merely producing a different refusal. It covers the platform branch; U3l supplies the tenant-admin baseline separately. These checks do not exhaust all combinations, which probe 01 supplements.

**N5 — predicted: H4 documents an existing r3 compatibility limit.** R10 adds no executable change. The gate still uses the elected valid date and transaction-start knowledge. A historical rebill can require current-classification figures, and a missing current assertion at that date fails classification. “Only rebilled at current knowledge” is not a workaround for a date with no visible replacement assertion: the selected date must actually resolve a classification. No latest-at-commit guarantee is introduced.

## Probe handoff

Run `codex-r4-probes/01-admin-power-paths.sql` using `psql -X -v ON_ERROR_STOP=1 -f ...` as superuser `tally` against a clone with `patch-21-frozen-r4.sql` already applied. It is self-contained, BEGIN/ROLLBACK, and changes no role definitions. App operations run under SET ROLE tally_app with transaction-local app.user_id. Its invoker helper rolls back every case, including unexpected successes, and reports each affected-row count and SQLSTATE through notices starting `PROBE`.

**N6 — probe 01: expected outcomes.** Unauthorized role, activation, id and tenant changes refuse with 42501; a supervisor clearing a bound tenant user's subject refuses with 23001. Combined and two-step attacks stop at their first forbidden transition; the no-op-then-demote case accepts one row at step 1 and refuses step 2. DELETE/reinsert stops at DELETE (inspect privilege/retention diagnostic). The final three authorized controls must report ALL STEPS ACCEPTED after ALL constraints, with one row per write. The explicit-id platform INSERT also corrects the fixture mistake in my r3 probe; the author's r3 23502 result did not test that positive path. A setup failure or unrelated refusal is not a pass.

## Probe outputs (author to append)

Not executed by the reviewer.

Run by the author, 2026-10-14, on a fresh clone of tally with patch-21-frozen-r4.sql strict-applied; psql -X -q -At, NOTICE lines kept.

\`\`\`
cd240000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:47: NOTICE:  PROBE 01 operator demotes tenant admin step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000003: only a supervisor (tenant_admin or platform administrator) binds a Cognito identity, switches a user on or off, or demotes a tenant_admin — a session that could bind or revive an administrator could promote itself (R1, v5.4.2-21)

psql:/tmp/probe.sql:49: NOTICE:  PROBE 01 tenant admin demotes platform step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000004: only a platform administrator binds a platform administrator's identity, switches one on or off, or demotes one (R1, v5.4.2-21)

psql:/tmp/probe.sql:51: NOTICE:  PROBE 01 operator switches supervisor off step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000003: only a supervisor (tenant_admin or platform administrator) binds a Cognito identity, switches a user on or off, or demotes a tenant_admin — a session that could bind or revive an administrator could promote itself (R1, v5.4.2-21)

psql:/tmp/probe.sql:53: NOTICE:  PROBE 01 tenant admin clears platform binding step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000004: only a platform administrator binds a platform administrator's identity, switches one on or off, or demotes one (R1, v5.4.2-21)


psql:/tmp/probe.sql:55: NOTICE:  PROBE 01 supervisor clears bound tenant admin step 1 REFUSED [23001] users: user cd240000-0000-4000-8000-000000000005 is bound to a Cognito identity, and the binding is write-once (R1, v5.4.2-21) — a new identity is a new user

psql:/tmp/probe.sql:57: NOTICE:  PROBE 01 operator rekeys tenant admin step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000003: a user's id is immutable — platform administration is looked up by id, so re-keying a row would transfer the role
psql:/tmp/probe.sql:59: NOTICE:  PROBE 01 tenant admin rekeys platform step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000004: a user's id is immutable — platform administration is looked up by id, so re-keying a row would transfer the role

psql:/tmp/probe.sql:61: NOTICE:  PROBE 01 operator moves supervisor to foreign tenant step 1 REFUSED [42501] new row violates row-level security policy for table "users"

psql:/tmp/probe.sql:63: NOTICE:  PROBE 01 tenant admin moves platform to foreign tenant step 1 REFUSED [42501] new row violates row-level security policy for table "users"

psql:/tmp/probe.sql:65: NOTICE:  PROBE 01 combined demotion deactivation rekey and tenant move step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000004: a user's id is immutable — platform administration is looked up by id, so re-keying a row would transfer the role

psql:/tmp/probe.sql:68: NOTICE:  PROBE 01 demote then deactivate platform step 1 REFUSED [42501] user cd240000-0000-4000-8000-000000000004: only a platform administrator binds a platform administrator's identity, switches one on or off, or demotes one (R1, v5.4.2-21)

psql:/tmp/probe.sql:71: NOTICE:  PROBE 01 move then demote supervisor step 1 REFUSED [42501] new row violates row-level security policy for table "users"

psql:/tmp/probe.sql:74: NOTICE:  PROBE 01 no-op role then demote platform step 1 ACCEPTED rows=1
psql:/tmp/probe.sql:74: NOTICE:  PROBE 01 no-op role then demote platform step 2 REFUSED [42501] user cd240000-0000-4000-8000-000000000004: only a platform administrator binds a platform administrator's identity, switches one on or off, or demotes one (R1, v5.4.2-21)

psql:/tmp/probe.sql:77: NOTICE:  PROBE 01 delete then reinsert administrator step 1 REFUSED [42501] permission denied for table users

psql:/tmp/probe.sql:82: NOTICE:  PROBE 01 authorized tenant demotion then deactivation step 1 ACCEPTED rows=1
psql:/tmp/probe.sql:82: NOTICE:  PROBE 01 authorized tenant demotion then deactivation step 2 ACCEPTED rows=1
psql:/tmp/probe.sql:82: NOTICE:  PROBE 01 authorized tenant demotion then deactivation ALL STEPS ACCEPTED after ALL constraints

psql:/tmp/probe.sql:84: NOTICE:  PROBE 01 authorized foreign platform combined demotion step 1 ACCEPTED rows=1
psql:/tmp/probe.sql:84: NOTICE:  PROBE 01 authorized foreign platform combined demotion ALL STEPS ACCEPTED after ALL constraints

psql:/tmp/probe.sql:86: NOTICE:  PROBE 01 authorized bound platform insert with explicit id step 1 ACCEPTED rows=1
psql:/tmp/probe.sql:86: NOTICE:  PROBE 01 authorized bound platform insert with explicit id ALL STEPS ACCEPTED after ALL constraints
\`\`\`
