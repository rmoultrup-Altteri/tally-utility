# v5.4.2-21 r4 — Opus review (scoped to the r3→r4 diff)

**Verdict: ready.** H1 closes my r3 B1. I found no other way to remove an administrator's power through `users`, and r4 breaks nothing I can find.

**Hashes checked first.** All four frozen r4 files match the brief: patch `649db2b7…`, battery `60a45bb2…`, labels `9c2eb69f…`, mutations `5a51b7cc…`.

**Clone.** `rv21opus`, cloned from `tally`. TEMP was revoked from PUBLIC, `tally_app` and `tally_core`. The r4 patch was applied strictly. The clone is dropped at the end.

**Reproduced (executed):**
- Strict apply, twice. The second run is skipped by its marker.
- `battery-21`: 143 PASS, no FAIL.
- `labels-21.sh`: 9 cases PASS (LR1–LR7, LR2b, AR1).

**Not reproduced:**
- `ci.sh`, because of the shared database names.
- The mutations, which the brief forbids.

The probes ran the battery's r4 preamble and then mine, as `tally_app` under `app.user_id`.

## Blocking

None.

## Should fix

None.

## Notes

### N1. H1 is complete: every power-bearing column of `users` is guarded (executed)

The columns of `users` are `id, tenant_id, role, display_name, email, is_active, last_login_at, preferences, created_at, updated_at, cognito_sub`. Of these, the helpers read `id`, `tenant_id`, `role`, `is_active`, and the login path reads `cognito_sub`.

**As an operator, every one of these is refused 42501:**

| Probe | Statement | Refused by |
|---|---|---|
| D1 | demote its `tenant_admin` (my r3 B1 repro) | the binding guard: "only a supervisor" |
| D1v | demote its `tenant_admin` to `viewer` | the binding guard |
| D2 | demote the active platform admin (my r3 B1 repro) | the binding guard: "only a platform administrator" |
| T1 | move its `tenant_admin` to tenant 2 | RLS WITH CHECK |
| T2 | move the platform admin to tenant 2 | RLS WITH CHECK |
| T3 | set the tenant admin's `tenant_id` to NULL | RLS WITH CHECK |
| I1 | re-key the tenant admin's `id` | `enforce_platform_admin_grant` (the id is immutable) |
| C1 | clear the admin's binding | the binding guard |
| C2 | change the admin's binding | the binding guard |
| X1 | role and tenant in one statement | the binding guard |
| X2 | `INSERT … ON CONFLICT DO UPDATE SET role` | the binding guard |
| X3 | a demotion inside a writable CTE | the binding guard |

**As a tenant admin:**
- Demoting the platform admin (L3) is refused: "only a platform administrator".
- Moving a fellow tenant admin (L4) or the platform admin (L5) to tenant 2 is refused by RLS.
- Demoting a fellow tenant admin (L2) is accepted. That is the peer act, the supervisor case.
- Demoting an operator to viewer (L1) is accepted. It is not an administrator, so it is unguarded by design.

**As a platform admin:**
- Demoting the deactivated platform admin (L6) is accepted.
- Moving a tenant admin to another tenant (L7) is accepted. A platform admin is global; R1 accepts that.

Across two statements, demote first and then revive: the first step is now refused (D1, D2), so the two-step from r3 (G2d) is closed at its first step.

### N2. Nothing broken (executed)

- The battery and every race pass on the r4 build.
- The invariant's trigger string matches the new `OF cognito_sub, is_active, role` (the patch tail ran `assert_wave1_guard_invariants()` without error).
- Legitimate supervisor demotions still pass: U3m, and L2 above.

### N3. The new checks match their labels (read)

- **U3k** (a tenant admin demotes a platform admin) and **U3l** (an operator demotes its tenant admin) each assert the refusal and the message.
- **U3m** reads back `role = 'operator'`.
- **U3j** now reads `is_active` back after each step.
- **M49d** removes exactly the role clause, and is named at U3k.

A demotion of a platform admin by an operator (my D2) is not a battery row. U3k covers the same clause from a tenant admin. That is optional.

### N4. R10 states the fail-safe side of G1 accurately

It covers the replay-mode rebill of a reclassified item, and the retracted-with-no-replacement case being rebillable only at current knowledge. That matches my r3 N3.
