# v5.4.2-21 r3 — Opus review (scoped to the r2→r3 diff)

**Verdict: not yet.** One blocking item. G2 fixes the escalation I raised in r2, but "switching a supervisor off" is still open through `role`, and even an operator can do it. The guard is narrower than its claim: guard the act, not the label.

**Hashes checked first.** All four frozen r3 files match the brief: patch `57f2d1f0…`, battery `e3a432c0…`, labels `0056d791…`, mutations `5fb86c42…`.

**Clone.** `rv21opus`, cloned from `tally`. TEMP was revoked from PUBLIC, `tally_app` and `tally_core`. The r3 patch was applied strictly. The clone is dropped at the end.

**Reproduced (executed):**
- Strict apply, twice. The second run is skipped by its marker.
- `battery-21`: 139 PASS, no FAIL.
- `labels-21.sh`: LR1–LR7, LR2b and AR1 PASS.

**Not reproduced:**
- `ci.sh`, because of the shared database names.
- `mutations-21.py`, which the brief forbids.

The probes ran the battery's r3 preamble and then mine, as `tally_app` under `app.user_id`.

---

## Blocking

### B1. An operator (or a tenant admin) switches a supervisor off by demoting it — executed

`enforce_user_binding_by_supervisor` guards `cognito_sub` and `is_active`. The two -13 grant guards guard only *granting* a role: `NEW.role = 'tenant_admin'` or `'platform_admin'`, from something else. Nothing guards taking a role away.

| Probe | Session | Statement | Result |
|---|---|---|---|
| D1 | operator (b1) | `UPDATE users SET role = 'operator' WHERE id = <its tenant_admin b4>` | **ACCEPTED**; b4's `session_is_supervisor()` is now **false** |
| D2 | operator (b1) | `UPDATE users SET role = 'operator' WHERE id = <active platform admin b9>` | **ACCEPTED**; b9's `is_platform_admin()` is now **false** |
| G2c | tenant admin (b4) | the same on b9 | **ACCEPTED** |
| control, U3i | tenant admin (b4) | `UPDATE users SET is_active = false WHERE id = b9` | refused 42501 |

So the act G2 now reserves to a platform administrator, U3i's "a tenant administrator switches a platform administrator off", is done through another column, and by a lower role than r2's E5 needed.

r2 also listed "an operator … can switch its supervisors off" as fixed (F4, U3d). Through `role`, it is not. The defect is pre-existing in the -13 grant guards, but -21's F4 and G2 claim the act. By the standing rules (checks narrower than their claim; guard the act), it belongs here.

What this is and is not:
- It is not an escalation. Demoting someone gains the operator nothing (G2d3 below).
- It is a lockout. An operator can strip every approver of the backbilling gates (-13) and every platform admin homed in its tenant. Only a supervisor or a platform admin can then repair it, and possibly none is left.

**Fix**, one clause in each grant guard, mirroring the grant:
- `OLD.role = 'tenant_admin' AND NEW.role IS DISTINCT FROM OLD.role` requires `session_is_supervisor()`.
- `OLD.role = 'platform_admin' AND NEW.role IS DISTINCT FROM OLD.role` requires `is_platform_admin()`.

Add battery rows for D1 and D2, and two mutations. If Ryan rules demotion out of -21's scope, record it as a residual. Either way, F4's and G2's wording should not say "switch off" while the role path stays open.

---

## G2: what holds (executed)

- **The r2 repro is fixed.** E2 (revive and bind the deactivated platform admin), E2b (bind only) and E5 (switch off the active platform admin), all as a tenant admin, are refused 42501 ("only a platform administrator binds …").
- **A role change in the same UPDATE is caught.**
  - G2a: `SET role = 'operator', is_active = true, cognito_sub = …` on the platform admin row is refused. The trigger reads `OLD.role`.
  - G2d: demoting first, in a separate UPDATE that touches neither column, is accepted. Then reviving and binding the demoted row (G2d2) is accepted. But that session's `is_platform_admin()` is **false** (G2d3), so no escalation survives the two-step. The demotion itself is B1.
- **An INSERT of a bound platform admin** is refused (G2b), by `enforce_platform_admin_grant` first.
- **A platform admin of another tenant** binding a tenant-2 user is accepted (G2f). This is by design: a platform admin is global.

## G1: the snapshot date under current knowledge

- **N1. It is right (executed in part).**
  - The date is pinned: `valid_at` is the period end or the recorded election, validated since -10.
  - The knowledge is `now()`, the same instant as the surcharge sibling's.
  - AR1 (executed, PASS) shows that a classification retracted after the snapshot's instant now decides the figures.
  - The snapshot's presence cannot be steered: with no snapshot, `enforce_invoice_has_snapshot` refuses for every role (r2 N2).
- **N2. The only remaining lever: reclassify in the same transaction (predicted).** A caller who may write rate versions could record a reclassification in the issuing transaction, which then decides. That is a real, committed and sealed (-20) change to the rate, visible to every later bill, not a hidden coordinate. Acceptable.
- **N3. Historical-mode rebills fail on the safe side (predicted).**
  - A correction replaying the original's knowledge, where the item has since been reclassified as per-unit, must now carry the usage figures. The core holds them.
  - The edge: an item whose version at that date was retracted with no replacement. That correction is unissuable in replay mode ("missing a classification") and must be rebilled at current knowledge.
  - Refusing is the right side, because a classification retracted is retracted. It is worth one line in AC or R4 so the core knows the replay mode can be refused.

## Tests

- **N4.** L7a–c, U3h–j, LR7, AR1 and A8 match their labels, as far as I read them.
- **N5.** No row covers a demotion (B1).

## Has r3 broken anything r2 had right?

**N6.** Nothing found. The diff touches only the coordinate, the binding guard and text. Battery-21 and the races pass in full on the r3 build.
