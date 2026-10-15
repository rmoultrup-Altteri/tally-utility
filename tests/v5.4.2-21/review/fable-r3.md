# Fable review: v5.4.2-21 r3 (scoped to the r2→r3 diff)

**Date:** 2026-10-14. **Reviewer:** Fable. **Verdict: not yet** — G1 is right and my r2 B1 is closed; G2 has one path left open, a role-only demotion, which does what G2 forbids.

Hashes checked first, all four match the brief (`57f2d1f0…`, `e3a432c0…`, `0056d791…`, `5fb86c42…`). Clone `rv21fable` (TEMPLATE tally, TEMP revoked from PUBLIC, tally_app, tally_core), r3 patch strict-applied twice (second run skipped on `users.cognito_sub`), dropped at the end. No role touched; mutations not run; no repo file but this one written.

**Reproduced (executed):** `battery-21-frozen-r3.sql` 139 PASS, "complete"; `labels-21-frozen-r3.sh` LR1–LR7, LR2b, AR1 all PASS.

Each claim is **executed** (run on the clone) or **predicted** (read from code and catalog).

---

## Blocking

### B1. A tenant administrator demotes a platform administrator with a role-only UPDATE, then switches the demoted user off — executed

G2 says binding, reviving or switching off a platform administrator takes `is_platform_admin()`. The r3 guard fires `BEFORE INSERT OR UPDATE OF cognito_sub, is_active`; `enforce_platform_admin_grant` fires on `role` but refuses only the *grant* (`NEW.role = 'platform_admin' AND OLD.role IS DISTINCT FROM 'platform_admin'`) and the id swap. Nothing refuses `OLD.role = 'platform_admin' AND NEW.role <> 'platform_admin'`.

As `tally_app`, `app.user_id` = Sup (`tenant_admin`, T1), against UnboundPA (`platform_admin`, active, T1):

| | statement | result |
|---|---|---|
| G2c | `UPDATE users SET cognito_sub = 'r3-sup-second' WHERE id = UnboundPA` | refused 42501 "only a platform administrator binds …" (the r3 guard works) |
| G2d | `… SET role = 'operator', is_active = true WHERE id = OldPA` | refused (the r3 guard sees `OLD.role`) |
| **G2f** | `… SET role = 'operator' WHERE id = UnboundPA` | **admitted, 1 row**; `role` is now `operator` |
| **G2f2** | `… SET is_active = false WHERE id = UnboundPA` | **admitted, 1 row** — a supervisor may switch an operator off |
| | as UnboundPA: `is_platform_admin()` | **false** |
| G2f3 | `… SET role = 'viewer' WHERE id = UnboundPA` (fresh) | admitted, 1 row |

So a tenant_admin removes platform administration from every platform administrator of its tenant (RLS limits it to its own tenant; G2g against T2's row touched 0 rows), and from there switches them off like any operator. It is the outcome G2 names — "switches one off" — through the one column the two guards don't share. Pre-existing in `enforce_platform_admin_grant`, but G2 is the claim r3 makes, and the demotion defeats it.

Fix, one branch in `enforce_platform_admin_grant` (already keyed on `role`, already `current_user = 'tally_app'`-gated): `IF TG_OP = 'UPDATE' AND OLD.role = 'platform_admin' AND NEW.role IS DISTINCT FROM 'platform_admin' AND NOT public.is_platform_admin() THEN RAISE …` — "only a platform administrator removes the platform_admin role". Battery row U3k (tenant_admin demotes a platform administrator: 42501) and U3l (a platform administrator demotes one: admitted); mutation M49d. The r3 guard itself needs no change.

---

## Should-fix

None in the r2→r3 scope beyond B1.

---

## Notes

- **N1. G1 (Q1) — executed.** My r2 B1 shape against r3 (`fable-coord-r2c.sh`: FLIP8 fixed at T0, bill drafted at T0 with a figure-less rider line; at T1 the version is retracted and corrected to per unit; snapshot at `(period_end, created_at)`): gap at the snapshot coordinate is still NULL, at `(period_end, now())` six figures, and the issuance is now **refused** 23514 "missing usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed". AR1 in the race script is the same case and passes.
- **N2. Can a caller still steer the classification (Q1) — predicted.** The date: `valid_at` is bound by -10 (`period_end`, or a correction's elected rate date from `correction_run_targets` — the operator's election by design, validated at snapshot insert). The knowledge: `now()`; a version written in the same transaction is visible (`recorded_at = now() <= now()`), which is a real reclassification by someone holding the version check, not steering. Presence: no snapshot → `enforce_invoice_has_snapshot` refuses (r2 P2d, executed), and it is ENABLE ALWAYS ('A'). A reclassification *after* issue changes nothing: the lines are frozen.
- **N3. Does `now()` refuse a legitimate historical replay (Q1) — predicted.** Yes, in one case: a correction replaying the original's knowledge instant (`recorded_at` = the original snapshot's) for a rider that was fixed then and is per unit now, with a line carrying no figures. That is the right side to fail on: the check is presence-only, the figures (quantity, unit, rate, meter figures) exist for any rider priced on usage and cost the core four columns; a retracted classification is retracted. Say so in the comment ("a replay of a since-retracted classification carries the figures the current classification asks for").
- **N4. G2, the paths that hold (Q2) — executed.** A tenant_admin: INSERT of a bound platform_admin → refused by the grant guard (G2a); INSERT of an unbound one → refused (G2b); bind → refused by r3 (G2c); demote + revive in one UPDATE → refused by r3 (G2d); promote + bind in one UPDATE → refused by the grant guard (G2e); revive T2's platform admin → 0 rows (RLS; G2g). A deactivated platform admin reviving itself → 0 rows (RLS hides every row from an inactive session; H1). An active platform admin: revives T2's platform admin cross-tenant (H2, 1 row — correct, platform administration is global), binds the unbound one (H3), switches itself off (H4, 1 row — recoverable by another platform administrator or the owner; the r2 S2 lockout note applies here too).
- **N5. Did r3 break anything (Q3) — executed/predicted.** The r3 guard's early `RETURN NEW` when neither column changes is equivalent to r2's predicate. The battery (139) and races (9) pass. `is_platform_admin()` is the -11 definer the app already executes. For a platform_admin row the supervisor branch is skipped and `is_platform_admin()` is required; a platform administrator is a supervisor, so no legitimate caller lost a path.
- **N6. New checks vs labels (Q4) — predicted.** L7a–c assert `current_setting('lock_timeout') = '1700ms'` after each branch and after a refusal: exact. LR7 mirrors LR6 for the location branch; M53b/M60/M60b point at them. AR1 asserts both the admissible instant and the refusal text. A8 runs `SET CONSTRAINTS ALL IMMEDIATE`, so the complete correction meets the snapshot, surcharge and arithmetic checks together. U3h–j: U3j's switch-off is a bare statement after `admits()`, so `ON_ERROR_STOP` is what would catch it; fine, but the label claims both acts. M46b (recorded_at back) caught at AR1 — the knowledge axis now has its mutation. The r1 "U3e" label is fixed.
- **N7. R8/R9 — predicted.** R8 states the unguarded `reverses_ledger_entry_id` on non-void rows (my r2 S3); R9 the sibling's `line_item_carries_base` at the period end. Both as I described them.

---

## What I ran

- `rv21fable`: clone, REVOKE TEMP, strict apply ×2, frozen r3 battery (139 PASS), frozen r3 races (9 PASS).
- `fable-coord-r2b.sh` + `fable-coord-r2c.sh` (r2 B1 shape, three committed steps, issuance rolled back): refused on r3.
- `fable-probes-r3.sql`, `fable-probes-r3b.sql` (rolled-back transactions): G2a–g, H1–H4, G2f/G2f2/G2f3 with row counts.
- Clone dropped.
