# v5.4.2-21 review round 1: findings and their disposition

**Verdicts on r1** (patch md5 `0900a47c`): Opus "not yet", Fable "not yet", Codex "not yet".
- Codex reviewed source only. Its five probes were run by the author and appended to `codex-r1.md`; every prediction reproduced.
- Opus and Fable executed their repros on their own clones.

## Blocking

| # | Finding | Who | Disposition in r2 |
|---|---|---|---|
| F1 | A surcharge whose rate item has no version visible at the coordinate needs no figures. The cases: no version at that date, or another tenant's item hidden by RLS. `coalesce(… , false)` read "unknown" as "fixed". | all three (Opus B1, Fable B2, Codex B1; probe 01) | `v_calc IS NULL` is now a gap ("a classification"). Battery A4g, A4h; mutation M45. |
| F2 | The arithmetic is classified at `(period_end, now())`, but a correction is priced at its elected rate date. A February per-unit price on a January correction passed with no figures. | Codex B2 (probe 02); Opus N3 thought it acceptable | Read at the bill's snapshot coordinate `(valid_at, recorded_at)`, validated and frozen since -10. With no snapshot, the snapshot check refuses issuance; there is no live fallback. Battery A7; mutation M46. |
| F3 | An in-use label can be renamed or re-pointed (key, entity, tenant), then deleted, or simply left renamed. | Opus B3, Fable B1 | The key columns are write-once for every role (`enforce_custom_label_key_frozen`, ENABLE ALWAYS). Battery L6a–e; mutations M48, M48b. |
| F4 | An operator binds its own second Cognito account to an unbound tenant_admin, or revives a deactivated one, and becomes a supervisor. It can also switch its supervisors off. | Opus B2 | For `tally_app`, binding an identity and changing `is_active` require `session_is_supervisor()`, mirroring `enforce_tenant_admin_grant`. Consequence: a user is bound when a supervisor provisions it. Battery U3a–g, U1f; mutations M49, M49b, M58. |

## Should-fix

| # | Finding | Who | Disposition |
|---|---|---|---|
| F5 | The void's charge lookup is not bound to the bill's customer. | Opus S1 (Fable N3) | `AND l.customer_id = v_invoice.customer_id`. V1e, plus V1f for the tie-break and V1g for the tenant filter as a platform admin; M50, M50b. |
| F6 | The void's reversal can be filed as an `adjustment` against `invoice_void` with no link. | Opus S2 | CHECK: `reference_type = 'invoice_void'` if and only if `void_reversal`. G2e, G2f; M51. |
| F7 | A void_reversal can name the same entry twice. | Fable S3 | A partial UNIQUE index, one void reversal per entry. G2g; M52. The customer binding of the FK stays unruled (residual R2). |
| F8 | The deadlock note is too narrow (different labels deadlock too), SHARE's cost is understated, and there is no bound on the wait. | all three (Codex S3, Opus S3, Fable S1) | The header is rewritten. The guard sets `lock_timeout` to 5 s around its LOCK and restores it. Race LR6; mutation M53. |
| F9 | `retired_by` names any user, of any tenant. | Opus S4, Fable N7 | Stamped from `app.user_id` by the database. K3e; M54. |
| F10 | The invariants miss the labels' `no_truncate` and the ENABLE ALWAYS state of the new guards. | Codex S1, Fable S2 | The retention invariant checks the labels' three guards. A new `assert_wave1_guard_invariants()` covers the arithmetic, born-unvoided, Cognito and supervisor guards and the dependency guard. CI step added. Mutations M10, M48b, M56–M59. |
| F11 | A gas rider is required to carry the usage line's commodity rate. | Fable S4 | The commodity rate is required on usage lines only; a rider's rate is `rate`. A4j; M47. This is a drafting call, reported to Ryan. |
| F12 | Two mutations were caught for an indirect reason (M12, M16). | Codex S2 (probe 05) | New rows K3a2 (an edit inside a retirement) and K3d2 (a retired reason rewritten); the mutations are re-pointed to them. |
| F13 | The superuser exception to the Cognito write-once is unstated. | Codex S4 | Stated in the inventory, the column comment and the header. Row U1f. |
| F14 | Test gaps. | Opus S5, Fable S5 | - V1d relabelled (the refusal is atomic; ordering is not testable).<br>- G7 checks each index's definition.<br>- -15 C8b runs as the owner.<br>- LR2b asserts the late write's dangling key (the stated scope).<br>- -20 I1's line carries its rate. |

## Notes taken into the header or comments

- **Scope of the label check** (Codex N2): a deletion-time check, not referential integrity.
- **Retained children** (Fable N1): a tenant, a customer or a read cycle instance with one can no longer be deleted.
- **Superuser loads** (Fable N3, Codex N5): "posted" is `first_issued_at` for what the application writes; a superuser load sets the stamp with the bill (residual R6).
- **`invoice_line_arithmetic_gap`** (Fable N6): executable by `tally_app` because the issuance check calls it with the caller's rights.
- **The issued→issued skip and the lines' FOR SHARE:** not mutation-tested (residual R7).

## Not taken

- **Binding `account_ledger.reverses_ledger_entry_id` to the customer** (Fable S3, optional): a reversal across customers was not ruled. Residual R2.
- **"The named entry is a charge"** (Fable S3): needs a trigger. It stays in residual R2.
