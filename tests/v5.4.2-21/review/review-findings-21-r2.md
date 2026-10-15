# v5.4.2-21 review round 2: findings and their disposition

**Verdicts on r2** (patch md5 `11aad26f`): Codex "ready"; Opus "not yet"; Fable "not yet".
- Every r1 finding was verified fixed by its reviewer.
- Codex's nine probes were run by the author and appended to `codex-r2.md`; all matched its predictions.

## Blocking

| # | Finding | Who | Disposition in r3 |
|---|---|---|---|
| G1 | The arithmetic is read at the snapshot's `recorded_at`, which the caller chooses inside `[created_at, now()]`. A rider retracted and corrected to per unit after the bill was drafted issues with no figures. | Fable B1 (executed) | Read at `(snapshot.valid_at, now())`: the date the bill's, the knowledge current, as the surcharge sibling. A7 still refuses. Race AR1 (two committed instants); mutations M46 (period end) and M46b (snapshot knowledge). |
| G2 | A tenant_admin revives or binds a deactivated platform administrator of its tenant and becomes one; it can also switch an active one off. | Opus B1 (executed) | A platform administrator target, as it is or was, requires `is_platform_admin()`. U3h–j; M49c. |

## Should-fix

| # | Finding | Who | Disposition |
|---|---|---|---|
| G3 | No test checks that the guard restores the caller's `lock_timeout`; only one branch's timeout is mutation-tested. | Opus S1, Codex S2, Fable N | L7a–c (both branches, and after a caught refusal); race LR7 (the location branch's 5 s); M53b, M60, M60b. |
| G4 | Integrated issuance coverage. | Codex S1 | A8: a complete correction issues with every deferred check. |
| G5 | M16's label; the inventory's deadlock note; U3e's label. | Codex S3, Fable S1 | Corrected. |
| G6 | AC-43: self-signup needs a supervisor service identity, and the last tenant_admin can switch itself off. | Fable S2 | Stated in AC-43. |
| G7 | A `reverses_ledger_entry_id` on a non-void row is unguarded. | Fable S3 | Residual R8 (other reversal kinds are not ruled). |

## Notes

- **Opus S2.** The guard's 5 s replaces a shorter caller timeout for the LOCK only. This is stated in the guard's comment and header.
- **Fable.** `line_item_carries_base` classifies at the period end, not the elected date (pre-existing). Residual R9.
