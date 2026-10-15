# Codex — v5.4.2-21 r3

Verdict: **ready** (predicted, source-only, scoped to r2→r3).

The four MD5 hashes were checked first and match:

| Frozen file | MD5 |
|---|---|
| patch-21-frozen-r3.sql | `57f2d1f007b41e4aee2b9ad7568aff4e` |
| battery-21-frozen-r3.sql | `e3a432c03f23b263d74a43ede58fdce2` |
| labels-21-frozen-r3.sh | `0056d791653ba17f17f172b86db6ed2e` |
| mutations-21-frozen-r3.py | `5fb86c42895f9bc6e6c62d59228675db` |

Reviewed the brief, supplied patch diff, actual frozen test diffs, my previous reviews and appended author outputs, r2 disposition, and relevant underlying functions/policies in `sql/tu.sql`. No other reviewer's r3 was read. No database, Docker, strict apply, CI, concurrency test or mutation was run. The reported suite totals remain author evidence. **Predicted** is a source conclusion; **probe NN** identifies an unexecuted SQL handoff, not a reproduced finding.

## Blocking items

**B1 — predicted: none found in the scoped changes under the stated current-knowledge policy.** G1 removes the caller-selected snapshot knowledge coordinate from the arithmetic decision; G2 closes binding/reactivation of a same-tenant platform administrator by a tenant supervisor. The historical-replay restriction in N2 is a deliberate compatibility cost, not proof that every previously valid rebill still issues. Unexpected probe outputs should be assessed before relying on this verdict.

## Should-fix items

**S1 — predicted: LR7 does not establish everything the race-script header promises.** `labels-21-frozen-r3.sh:168–191` uses a one-second sleep, then checks for `55P03` and elapsed time of four to seven seconds. Unlike the header's “Every race leg” claim, this leg never observes B blocked by A through `pg_blocking_pids`. It is a useful timeout regression test on an isolated clone, but scheduler timing can make it flaky and the output does not positively identify the blocker. Synchronize on A holding its writer lock and observe B's blocker, or narrow the header. LR7 also does not catch the timeout inside B and verify the surviving caller setting. L7c covers rollback after an **in-use refusal**, not after a contended LOCK timeout. Source still predicts correct GUC restoration through exception-subtransaction rollback; this is an evidence gap, not a discovered leaked setting.

**S2 — probe 01: retain the G2 edge cases and strengthen the positive assertion.** U3h/i exercise activation changes, not identity binding, INSERT, or OLD-role protection during simultaneous demotion. M49c catches removal of the whole platform branch but cannot establish these individual paths. U3j's helper (`battery-21-frozen-r3.sql:675–677`) regards a zero-row UPDATE as success; it neither asserts one affected row nor reads back the two states, and prints its PASS before the switch-off statement. Existing fixtures make the intended writes plausible, but the assertion is weaker than “revives one, and switches it off again.” Add row-count/state assertions and the probe's cases. The new guard itself is correct for these paths by inspection.

## Notes

**N1 — predicted: G1 preserves the date binding and cannot be bypassed merely by omitting a snapshot.** The arithmetic call at `patch-21-frozen-r3.sql:502` uses `v_snap.valid_at` and `now()`. Ordinary snapshots must use the invoice's period end; corrections must use their recorded rate-date election. The insertion validator, binding freezes, and issuance recheck in -10 still apply. A caller can select an allowed correction election (or draft a different ordinary period), which can select another classification; that is the existing date-selection contract, not arbitrary snapshot-date substitution. The gate's no-snapshot return delegates to `enforce_invoice_has_snapshot`, which rejects issuance without one. Snapshot deletion cannot turn this into an accepted final state under ALL constraints. No fallback to period_end was reintroduced.

**N2 — probe 02: current knowledge intentionally overrides original-world replay for this completeness gate.** A fixed rider issued at T0, retracted and replaced with per-unit usage at T1, can still have an admissible correction snapshot at the original bill's recorded instant. R3 nevertheless requires the current per-unit fields. The probe constructs that complete lineage and predicts: historical helper gap NULL; current helper gap non-NULL; amount-only correction refused by CI-016 with 23514; populated control accepted after ALL checks, without a commodity rate.

This can refuse a legitimate historical-mode reconstruction that r2 accepted: its original calculation did not use those usage fields. Under G1's explicit decision that a retracted classification must not justify an amount-only newly issued bill, refusal is the right side to fail on. Do not fabricate figures merely to pass. Supporting unrestricted original-world replay would need a separately specified, trustworthy binding to the calculation/assertion actually used. Conversely, if current knowledge changes per-unit to fixed, this gate no longer demands the old per-unit fields; it is current-classification completeness, not a guarantee that every historical calculation operand is present. Document this operational consequence alongside historical correction behavior.

My r2 N2 conclusion that an admissible knowledge instant was therefore not an arithmetic bypass was too broad. Admissibility of a snapshot coordinate does not make that coordinate sufficient for the newly stated current-knowledge eligibility policy. R3 retains the elected-date fix from my r1 B2 while changing the knowledge policy.

**N3 — predicted: “current” means transaction-start time, not wall-clock time at deferred execution or commit.** PostgreSQL `now()` is fixed for the transaction. Beginning an issuance transaction before a later reclassification can still select the earlier temporal assertion, even if the reclassification commits before the deferred gate runs; the as-of function uses the passed timestamp. R3 closes backdating through `snapshot.recorded_at`, not every possible concurrent knowledge change. AR1 starts issuance after the reclassification and does not test an overlapping transaction. This matches the chosen `now()` convention and existing surcharge sibling; a stronger latest-at-commit guarantee would require a concurrency design, not just this substitution. Do not describe G1 as that stronger guarantee.

**N4 — probe 01: G2 covers INSERT, both sides of a role-changing UPDATE, and cross-tenant platform authority.** The guard (`patch-21-frozen-r3.sql:1043–1062`) enters for a non-NULL binding on INSERT or an actual binding/active change on UPDATE. NEW platform role requires `is_platform_admin()`; OLD platform role also requires it on UPDATE, so demoting and binding/reactivating in one statement cannot evade the check. The separate platform-role grant guard still rejects an unbound platform INSERT or promotion by a non-platform caller. A tenant supervisor cannot reach another tenant's platform row through RLS (expect zero rows, not a trigger exception); an active platform session from another tenant can reach and legitimately bind/revive it. Write-once Cognito protection remains independent.

“Was a platform administrator” here means OLD.role for this update, not a lifetime role history. Existing -12 explicitly allows dropping the platform role. Demotion in an earlier statement followed by binding is therefore possible for a now-ordinary user, but does not restore platform powers; granting those powers again remains platform-only. G2 is not a new general protection against demotion or a full account-administration policy. Trusted app.user_id and owner-repair exceptions remain unchanged.

**N5 — predicted: the other new checks improve r2 without an identified source regression.** A8 forces ALL deferred constraints for a populated elected-date gas correction; the sentinel exception rolls back the attempted issuance only after those checks have run. That addresses the prior integrated positive-coverage gap. AR1 supplies the separate committed knowledge instants missing from a single-transaction battery, and M46b targets precisely the old snapshot-knowledge call. M46 still distinguishes the correction date from period_end. L7a/b directly inspect restoration on both successful branches; M60/M60b remove the respective restoration statements. M53b targets the other timeout-setting branch. M16's new label accurately names retirement rewriting. These are meaningful source-level test improvements; they do not independently substantiate 139 checks or 67/67 catches here. R8/R9 disclose existing limits and introduce no new enforcement change.

## Probe handoff

Run each file using `psql -X -v ON_ERROR_STOP=1 -f <file>` as superuser `tally` against a fresh throwaway clone with `patch-21-frozen-r3.sql` already applied. No role or database definitions are changed. Helpers are invoker functions created by the owner before SET ROLE; application actions use tally_app and transaction-local app.user_id. Target outcomes are NOTICE lines beginning `PROBE`, with SQLSTATE and diagnostics on refusal; arbitrary setup failures or unrelated refusals are not passes.

| File in `codex-r3-probes/` | Predicted output / transaction behavior |
|---|---|
| `01-platform-binding.sql` | First four tenant-admin attempts refused with 42501 and platform-authority diagnostic; foreign-target tenant UPDATE affects zero rows; three authorized foreign-platform writes affect one row each. Entire file BEGIN/ROLLBACK. |
| `02-historical-reclassification.sql` | T0 original fixed rider issues with ALL checks and is voided; T1 reclassifies it. T2 accepts the historical snapshot, refuses amount-only correction with 23514/missing usage figures, then accepts populated control with ALL checks. **T0 and T1 commit; T2 rolls back. Fixtures remain; discard the clone.** |

## Probe outputs (author to append)

Not executed by the reviewer.

Run by the author, 2026-10-14, each file on a fresh clone of tally with patch-21-frozen-r3.sql strict-applied; psql -X -q -At, NOTICE lines kept.

```
==== 01-platform-binding.sql
cd230000-0000-4000-8000-000000000002

psql:/tmp/probe.sql:24: NOTICE:  PROBE 01 tenant binds inactive platform REFUSED [42501] user cd230000-0000-4000-8000-000000000003: only a platform administrator binds a platform administrator's identity or switches one on or off (R1, v5.4.2-21)
psql:/tmp/probe.sql:25: NOTICE:  PROBE 01 tenant inserts bound platform REFUSED [42501] user : only a platform administrator may grant the platform_admin role — a tenant session that could promote itself would hold every platform-only control, including tenants.cutover_date

psql:/tmp/probe.sql:26: NOTICE:  PROBE 01 tenant demotes and binds platform in same UPDATE REFUSED [42501] user cd230000-0000-4000-8000-000000000003: only a platform administrator binds a platform administrator's identity or switches one on or off (R1, v5.4.2-21)

psql:/tmp/probe.sql:27: NOTICE:  PROBE 01 tenant promotes and binds operator in same UPDATE REFUSED [42501] user cd230000-0000-4000-8000-000000000004: only a platform administrator may grant the platform_admin role — a tenant session that could promote itself would hold every platform-only control, including tenants.cutover_date

psql:/tmp/probe.sql:28: NOTICE:  PROBE 01 tenant switches foreign platform off (expect zero rows) ACCEPTED rows=0

cd230000-0000-4000-8000-000000000012
psql:/tmp/probe.sql:30: NOTICE:  PROBE 01 foreign platform binds and revives platform (expect one row) ACCEPTED rows=1


psql:/tmp/probe.sql:31: NOTICE:  PROBE 01 foreign platform inserts bound platform (expect one row) REFUSED [23502] null value in column "id" of relation "users" violates not-null constraint
psql:/tmp/probe.sql:32: NOTICE:  PROBE 01 foreign platform switches platform off (expect one row) ACCEPTED rows=1

==== 02-historical-reclassification.sql
cd232000-0000-4000-8000-000000000002
2

{"invoice_id": "cd232000-0000-4000-8000-000000000006", "had_payment": false, "credit_balance": 0.00, "invoice_number": "CODEX-ORIGINAL", "reads_released": 0, "ledger_entry_id": "78517572-4b93-42da-af67-6a6c0f03f79e", "rebill_expected": true, "reversal_amount": -10.00, "void_reason_code": "wrong_rate", "charges_auto_reverted": 0, "charges_pending_review": 0, "reverses_ledger_entry_id": "8265a07d-fdfe-47df-8984-45094be490a1", "duplicate_no_match_warning": false}
psql:/tmp/probe.sql:59: NOTICE:  PROBE 02 T0 original fixed rider issued with ALL checks and voided

cd232000-0000-4000-8000-000000000002
3
psql:/tmp/probe.sql:70: NOTICE:  PROBE 02 T1 reclassification committed next

cd232000-0000-4000-8000-000000000002

psql:/tmp/probe.sql:104: NOTICE:  PROBE 02 snapshot accepted; historical gap=<NULL>, current gap=usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed
psql:/tmp/probe.sql:104: NOTICE:  PROBE 02 historical amount-only correction REFUSED [23514] invoice CODEX-CORRECTED cannot be issued: line 0 (surcharge, Historical fixed rider) does not carry its arithmetic — missing usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed (CI-016, v5.4.2-21)

psql:/tmp/probe.sql:119: NOTICE:  PROBE 02 populated historical correction ACCEPTED after ALL checks
```
Author's note: 'foreign platform inserts bound platform' fails on the probe's own fixture (users.id has no default and the probe omits it); not a finding.
