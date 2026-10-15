# Codex — v5.4.2-21 r2

Verdict: **ready** (predicted, source-only).

The four frozen hashes were checked first and match the brief:

| File | md5 |
|---|---|
| patch-21-frozen-r2.sql | `11aad26ff3f58cb4ac7245d4ff421a6a` |
| battery-21-frozen-r2.sql | `08c7fd59501322ffe18ac91c2d94c415` |
| labels-21-frozen-r2.sh | `2a3c8dadf6efe5631bf46dbd56df0c52` |
| mutations-21-frozen-r2.py | `9e6791807686e8380a8d87aa1d8c61cc` |

Reviewed the brief, my r1 review including the author's appended outputs, the findings disposition, frozen r2 files, r1→r2 patch diff, source inventory, and relevant existing guards in `sql/tu.sql`. No other reviewer's r2 file was read. No Docker/database execution, strict application, CI, concurrency execution, or mutation execution is claimed. Every substantive conclusion below is **predicted**; **probe NN** identifies an unexecuted handoff, not an observed result. The author's reported 131 checks, 32 CI steps and 62/62 mutations remain author evidence.

## Blocking items

**B1 — predicted: none found in the agreed r2 scope.** The two original Codex blockers are fixed in source. Running the supplied probes remains necessary to turn these predictions into database evidence; an unexpected result must be assessed before relying on this verdict.

## Should-fix items

**S1 — predicted; probes 01, 02, 08, 09: keep integrated arithmetic coverage in the permanent battery.** `pg_temp.issue()` explicitly forces only `enforce_invoice_line_arithmetic`, then rolls its subtransaction back. That is a useful unit test, but A7 does not itself demonstrate a complete correction issuance, nor does A4j establish that the complete gas rider can pass all sibling constraints. Probes 01/02 force ALL deferred checks on the original negative repros; 08 tests the missing-snapshot dependency and coordinate refusals; 09 supplies a positive complete correction with the relaxed gas-rider requirement. Incorporate those integration cases. This is a coverage recommendation, not evidence of a failing r2 issuance path.

**S2 — predicted; probe 07: test timeout restoration explicitly.** LR6 tests a contended field-label SHARE request timing out with 55P03. It does not catch the error and inspect the caller's surviving transaction setting, and it does not test the location-label branch. Probe 07 checks both branches' successful restoration and restoration after a caught in-use refusal, with a nondefault `1700ms` setting. Add a two-session leg that catches an actual 55P03 and checks the setting afterwards. The single-session probe deliberately does not claim to reproduce that case. Source predicts restoration, as explained in N3.

**S3 — predicted: finish the wording cleanup.** M16 now points to the right behavioral test, K3d2, but its description still says “a retirement can be undone.” Removing that branch permits rewriting retirement metadata; it does not revive the edge, because the remaining code still stamps `retired_at := now()`. Rename the mutant accordingly. The source inventory's L3 deadlock example also retains the old narrow same-label example; bring it into line with the corrected frozen patch header. Neither is a behavioral blocker.

## Round-1 disposition

| Original Codex item | R2 conclusion and evidence |
|---|---|
| B1: missing classification admitted | **Probe 01 / predicted fixed.** `invoice_line_arithmetic_gap()` now returns a classification gap when the as-of lookup returns no version. It refuses even a fully populated but unclassifiable surcharge, rather than guessing its kind. A4g/A4h cover absent/hidden versions. Expected integrated outcome: 23514, missing classification. |
| B2: period-end/live coordinates instead of bound calculation coordinates | **Probe 02 / predicted fixed.** The arithmetic trigger reads `invoice_calculation_snapshots.valid_at, recorded_at`; no live-coordinate fallback remains. Expected correction outcome: 23514, missing usage figures at February's elected date. Probe 09 is the complete positive control. |
| S1: missing label TRUNCATE invariant | **Probe 04 / predicted fixed.** The invariant checks exact definitions and ENABLE ALWAYS state for all three label guards on both tables. Disabling both label `no_truncate` triggers must now produce 0LP01. The separate wave-1 invariant pins the five additional guard definitions/states. |
| S2: diagnostic-only M12/M16 catches | **Probe 05 / predicted fixed.** K3a2 supplies a valid retirement together with the notes edit; K3d2 rewrites a retired reason to another non-NULL reason. Removing the respective guard now admits the forbidden write, rather than merely changing the diagnostic. The baseline should refuse both with 23001. M16's remaining naming issue is S3. |
| S3: deadlock/cost explanation | **Predicted fixed in the patch header.** It now explains different-label cycles, table-wide writer/maintenance conflicts, whole-transaction retries, and short administrative transactions. The SHARE acquisition has a five-second timeout. This does not bound how long an acquired lock is held. |
| S4: undocumented Cognito superuser exception | **Predicted fixed; probe 06.** The header, column comment and inventory U3 now state the exception, and U1f exercises it. The write-once trigger exempts superusers specifically; the new supervisor gate exempts all roles other than `tally_app`, subject to their actual privileges. |
| N2 / probe 03: delete then write the key | **Probe 03 / predicted unchanged by design.** The dependent writable CTE can still leave a used key with no definition. The patch now explicitly calls this a deletion-time check. LR2b checks the analogous later-writer result. The new key freeze closes UPDATE-based loss of a definition, not this disclosed no-writer-side-validation scope. |

The author's r1 outputs reproduced both arithmetic admissions, the invariant miss, the writable-CTE behavior and the two stronger retirement refusals. They are historical evidence against r1, not execution evidence against r2.

## Notes

**N1 — predicted; probe 06: supervisor boundary and onboarding.** Both INSERT with a non-NULL subject and UPDATE changing either protected field enter the supervisor gate. An operator cannot evade it by inserting an active tenant administrator with no subject: the existing tenant-admin grant trigger rejects that role grant. ON CONFLICT DO UPDATE still fires the UPDATE guard; probe 06 includes revival through an upsert. Assigning the existing value is allowed and conveys no new authority.

A tenant administrator is constrained to its tenant by users RLS. An active platform administrator in another tenant is deliberately a supervisor and can bind/reactivate a target across tenants; being “of another tenant” does not strip platform authority. Even that platform user cannot rewrite a non-NULL binding through `tally_app`, because the independent write-once trigger still applies. The superuser can repair it. `tally_core` lacks users write privileges; the sealed `tally_seal`/`tally_void` roles have no users write grants and cannot be assumed by the app under the existing role invariants. Probe 06 attempts the core write and reports effective privileges/membership for these roles without altering role definitions. A future login role granted direct users writes and used without SET ROLE tally_app would bypass the supervisor test: the contract requires the app to operate as tally_app, as the older role-grant guards do. This patch is not a universal supervisor rule for arbitrary future database roles.

F4's onboarding consequence is sound on the stated merits: binding a privileged identity is an authorization act, not something an unbound first-login session should authorize for itself. Existing owner bootstrap is still needed for the first supervisor; subsequent provisioning uses a supervisor session. This conclusion assumes the accepted trusted `app.user_id` model, not protection against arbitrary impersonation through that setting.

**N2 — predicted; probes 02 and 08: callers select admissible coordinates, not arbitrary ones.** The existing `calculation_snapshot_coordinate_violation()` binds ordinary valid_at to period_end and recorded_at to the run-start/draft-creation through now window. Corrections require a visible same-tenant, previously issued void predecessor, correction run/target, and the recorded date election; recorded_at is in the current run window or exactly the predecessor snapshot's instant. The INSERT validator applies those rules before accepting a snapshot. UPDATE of the snapshot is forbidden, issued snapshots cannot be deleted, and related draft bindings are frozen while snapshotted. Missing snapshots are rejected by the separate deferred issuance guard. Thus choosing an allowed correction election or allowed knowledge instant is intentional, not a way around r2's arithmetic classification.

The new helper still relies on rate-version visibility, not an explicit equality between the line's tenant and the rate version's tenant. A platform session can see multiple tenants. Do not generalize A4h (an invisible foreign item) into a schema-wide tenant-composite FK guarantee; repairing all existing tenant-blind references is outside this patch's stated scope.

**N3 — predicted; probe 07: key freeze and timeout behavior.** The freeze is an unconditional BEFORE UPDATE trigger on each table, compares the full specified key tuple with IS DISTINCT FROM, and has no superuser exemption. Changing only presentation/status remains possible. UPSERT's UPDATE side is covered; doing nothing to the key is not a bypass. ENABLE ALWAYS and the exact invariant cover replication-mode trigger state, not hostile owner DDL replacing the function.

For each locking branch, `v_saved` captures the caller's `lock_timeout`; the code sets five seconds immediately before LOCK and restores the saved value immediately after acquisition. A subsequent in-use exception occurs after restoration. If LOCK itself throws, there is no local handler that swallows the exception: a caller's exception subtransaction or rollback to a savepoint also rolls back the local GUC change; without recovery the transaction is aborted. No successful return leaves five seconds installed. This is a per-SHARE-acquisition wait limit, not a five-second bound on the whole DELETE (including initial row locks), a multi-label statement, or the transaction. It also temporarily replaces a caller's shorter timeout rather than taking the minimum; callers needing a strict overall deadline still need an independent statement/transaction budget.

**N4 — predicted; probe 09: F11 is a reasonable drafting correction.** A gas rider's unit price is its own `rate`. Requiring the commodity rate as well conflated the rider with the usage charge. R2 retains the quantity, unit, rider rate, meter factor, Ccf and therms requirement while leaving the commodity-rate requirement intact for gas usage charges. A4j tests the omission in isolation; probe 09 tests a complete elected-date correction without it. Presence still does not prove multiplication, tier allocation or price correctness, as explicitly agreed.

**N5 — predicted: other r2 changes are consistent with their stated requirements.** The void charge lookup now binds customer as well as tenant/invoice/type and retains deterministic earliest selection. The new reference CHECK uses coalesce so NULL cannot evade the invoice_void/void_reversal equivalence; the partial unique index enforces one void reversal per named entry, including competing inserts. It does not impose the explicitly unruled same-customer/charge-kind constraint on arbitrary reversal writers. The amount remains negative amount_due. Retirement stamps retired_by from the session and retains write-once columns, live uniqueness and the schedule mutex. The new invariant checks trigger definitions/state, not function bodies or every new CHECK/index. No further regression was identified in these changes.

**N6 — predicted: test labels and evidence limits.** The revised G7 checks actual index definitions rather than names; V1d now claims atomic refusal, not internal execution order. LR2b explicitly verifies the disclosed dangling key. The M12/M16 behavior fix is real, with M16's residual label issue noted above. The arithmetic helper's isolated success must not be reported as full issuance (S1), and LR6 does not establish restoration (S2). The existing disclosed issued→issued/FOR SHARE mutation gaps remain. Nothing in this source review independently reproduces strict application twice or the reported suite counts.

## Probe handoff

Run each file independently as superuser `tally` against a clone of `tally` with `patch-21-frozen-r2.sql` already applied, using `psql -X -v ON_ERROR_STOP=1 -f <file>`. Every file is self-contained and enclosed in BEGIN/ROLLBACK. App writes use SET ROLE tally_app and transaction-local app.user_id. Owner setup creates any pg_temp helpers before switching role; the helpers are invoker functions. No roles or databases are created/altered/dropped. Probe 04's trigger disabling is transactional. Probe 06 briefly selects tally_core to test its privilege boundary.

| File in `codex-r2-probes/` | Predicted result |
|---|---|
| 01-missing-rate-version.sql | Non-NULL classification gap; issuance refused with 23514. |
| 02-classification-coordinate.sql | January helper gap NULL, February gap non-NULL; correction refused with 23514 for missing usage figures. |
| 03-label-writable-cte.sql | Inserted=1, label_exists=false, key_in_use=true: intentional deletion-time scope. |
| 04-label-truncate-invariant.sql | Baseline accepted; disabled label guards refused with 0LP01. |
| 05-dependency-edit-with-retirement.sql | Both edits refused with 23001. |
| 06-identity-paths.sql | Operator binding/revival/role-grant/upsert paths refused; own-tenant supervisor binding succeeds; foreign tenant-admin UPDATE affects zero rows; foreign platform binding succeeds; platform rewrite refused; core write denied; superuser repair succeeds; sealed/core users write privileges and app memberships false. |
| 07-label-key-and-timeout.sql | App/owner key changes refused with 23001; both unused-label deletes succeed; in-use delete refused; all reported timeout values remain 1700ms. Not a contention test. |
| 08-snapshot-boundary.sql | Wrong date, future/pre-creation time, missing-snapshot issuance and snapshot UPDATE all refused. Inspect each diagnostic to distinguish intended guard from fixture failure. |
| 09-complete-gas-correction.sql | Complete February gas rider correction accepted after ALL checks, with gas_commodity_rate absent. |

Setup errors stop the file. Target exceptions print SQLSTATE and the full message in NOTICE lines beginning PROBE; an arbitrary refusal is not automatically a pass. In particular 01/02 must reach the arithmetic guard and 09 must actually succeed. Append the author's outputs below without relabeling these source predictions as reviewer-executed tests.

## Probe outputs (author to append)

Run by the author, 2026-10-14, each file on a fresh clone of tally with patch-21-frozen-r2.sql strict-applied; psql -X -q -At, NOTICE lines kept.

```
==== 01-missing-rate-version.sql
cd210000-0000-4000-8000-000000000002

psql:/tmp/probe.sql:59: NOTICE:  PROBE 01 helper gap for absent version = a classification: rate item cd210000-0000-4000-8000-000000000005 has no version visible at (2026-01-31, 2026-10-15 01:18:52.519391+00) (NULL means admitted)
psql:/tmp/probe.sql:59: NOTICE:  PROBE 01 ISSUE REFUSED [23514] invoice CODEX-ISSUE cannot be issued: line 0 (surcharge, Unclassifiable surcharge) does not carry its arithmetic — missing a classification: rate item cd210000-0000-4000-8000-000000000005 has no version visible at (2026-01-31, 2026-10-15 01:18:52.519391+00) (CI-016, v5.4.2-21)
==== 02-classification-coordinate.sql
cd210000-0000-4000-8000-000000000002
2
psql:/tmp/probe.sql:59: NOTICE:  PROBE 02 same amount-only line: period_end gap=<NULL>, correction valid_at gap=usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed
psql:/tmp/probe.sql:59: NOTICE:  PROBE 02 January classification=fixed_monthly, February classification=per_unit_usage

{"invoice_id": "cd210000-0000-4000-8000-000000000006", "had_payment": false, "credit_balance": 0.00, "invoice_number": "CODEX-ORIGINAL", "reads_released": 0, "ledger_entry_id": "d0d86505-2df0-46a1-b883-ac39f747300a", "rebill_expected": true, "reversal_amount": -10.00, "void_reason_code": "wrong_rate", "charges_auto_reverted": 0, "charges_pending_review": 0, "reverses_ledger_entry_id": "8ed47a5d-1bd8-4720-8d9a-6b87198c7568", "duplicate_no_match_warning": false}

psql:/tmp/probe.sql:87: NOTICE:  PROBE 02 CORRECTION REFUSED [23514] invoice CODEX-CORRECTED cannot be issued: line 0 (surcharge, February per-unit price for January correction) does not carry its arithmetic — missing usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed (CI-016, v5.4.2-21)
==== 03-label-writable-cte.sql
cd210000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:33: NOTICE:  PROBE 03 delete-then-write CTE accepted: inserted=1 label_exists=f key_in_use=t
==== 04-label-truncate-invariant.sql
psql:/tmp/probe.sql:8: NOTICE:  PROBE 04 baseline invariant accepted
psql:/tmp/probe.sql:18: NOTICE:  PROBE 04 invariant REFUSED [0LP01] a label guard is missing, changed or not ENABLE ALWAYS: custom_field_definitions no_truncate, custom_location_types no_truncate (CI-014, v5.4.2-21)
==== 05-dependency-edit-with-retirement.sql
cd210000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:30: NOTICE:  PROBE 05 simultaneous edit/retire REFUSED [23001] rate_item_dependencies: dependency cd210000-0000-4000-8000-000000000007 is write-once — retire it and add a new one (CI-014, v5.4.2-21)
psql:/tmp/probe.sql:41: NOTICE:  PROBE 05 retirement rewrite REFUSED [23001] rate_item_dependencies: dependency cd210000-0000-4000-8000-000000000007 is retired, and a retirement is permanent — add the dependency again (CI-014, v5.4.2-21)
==== 06-identity-paths.sql
cd210000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:33: NOTICE:  PROBE 06 operator binds administrator REFUSED [42501] user cd210000-0000-4000-8000-000000000012: only a supervisor (tenant_admin or platform administrator) binds a Cognito identity or switches a user on or off — a session that could bind or revive an administrator could promote itself (R1, v5.4.2-21)

psql:/tmp/probe.sql:34: NOTICE:  PROBE 06 operator revives administrator REFUSED [42501] user cd210000-0000-4000-8000-000000000013: only a supervisor (tenant_admin or platform administrator) binds a Cognito identity or switches a user on or off — a session that could bind or revive an administrator could promote itself (R1, v5.4.2-21)

psql:/tmp/probe.sql:35: NOTICE:  PROBE 06 operator inserts bound user REFUSED [42501] user : only a supervisor (tenant_admin or platform administrator) binds a Cognito identity or switches a user on or off — a session that could bind or revive an administrator could promote itself (R1, v5.4.2-21)

psql:/tmp/probe.sql:36: NOTICE:  PROBE 06 operator inserts unbound active administrator REFUSED [42501] user : only a supervisor (tenant_admin or platform administrator) may grant the tenant_admin role — the backbilling approval gates rest on it, so a session that could promote itself could approve its own charge (v5.4.2-13)

psql:/tmp/probe.sql:37: NOTICE:  PROBE 06 operator upserts inactive administrator active REFUSED [42501] user cd210000-0000-4000-8000-000000000013: only a supervisor (tenant_admin or platform administrator) binds a Cognito identity or switches a user on or off — a session that could bind or revive an administrator could promote itself (R1, v5.4.2-21)

cd210000-0000-4000-8000-000000000012
psql:/tmp/probe.sql:39: NOTICE:  PROBE 06 tenant supervisor binds own operator ACCEPTED rows=1 role=tally_app

psql:/tmp/probe.sql:40: NOTICE:  PROBE 06 tenant supervisor updates foreign platform user ACCEPTED rows=0 role=tally_app

cd210000-0000-4000-8000-000000000014
psql:/tmp/probe.sql:42: NOTICE:  PROBE 06 foreign platform admin binds tenant supervisor ACCEPTED rows=1 role=tally_app

psql:/tmp/probe.sql:43: NOTICE:  PROBE 06 platform admin rewrites binding REFUSED [23001] users: user cd210000-0000-4000-8000-000000000012 is bound to a Cognito identity, and the binding is write-once (R1, v5.4.2-21) — a new identity is a new user

cd210000-0000-4000-8000-000000000014
psql:/tmp/probe.sql:47: NOTICE:  PROBE 06 core attempts identity update REFUSED [42501] permission denied for table users

psql:/tmp/probe.sql:49: NOTICE:  PROBE 06 superuser repairs binding ACCEPTED rows=1 role=tally

psql:/tmp/probe.sql:58: NOTICE:  PROBE 06 role=tally_core users INSERT=f binding UPDATE=f active UPDATE=f app can become=f
psql:/tmp/probe.sql:58: NOTICE:  PROBE 06 role=tally_seal users INSERT=f binding UPDATE=f active UPDATE=f app can become=f
psql:/tmp/probe.sql:58: NOTICE:  PROBE 06 role=tally_void users INSERT=f binding UPDATE=f active UPDATE=f app can become=f
==== 07-label-key-and-timeout.sql
cd210000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:38: NOTICE:  PROBE 07 app key rewrite REFUSED [23001] custom_field_definitions: label cd210000-0000-4000-8000-000000000008 keeps its key, entity and tenant — add a new label and archive this one (CI-014, v5.4.2-21)
psql:/tmp/probe.sql:38: NOTICE:  PROBE 07 successful field delete lock_timeout=1700ms (expected 1700ms)
psql:/tmp/probe.sql:38: NOTICE:  PROBE 07 successful location delete lock_timeout=1700ms (expected 1700ms)
psql:/tmp/probe.sql:38: NOTICE:  PROBE 07 in-use delete REFUSED [23001] custom_field_definitions: label r2_used is in use on customers — archive it (status = archived) or clear it from those rows first (CI-014, v5.4.2-21)
psql:/tmp/probe.sql:38: NOTICE:  PROBE 07 after caught refusal lock_timeout=1700ms (expected 1700ms)
psql:/tmp/probe.sql:45: NOTICE:  PROBE 07 owner entity rewrite REFUSED [23001] custom_field_definitions: label cd210000-0000-4000-8000-000000000008 keeps its key, entity and tenant — add a new label and archive this one (CI-014, v5.4.2-21)
==== 08-snapshot-boundary.sql
cd210000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:63: NOTICE:  PROBE 08 wrong ordinary valid_at REFUSED [23514] snapshot rejected for invoice CODEX-ISSUE: valid_at 2026-02-28 must equal the invoice's period_end 2026-01-31 — an ordinary bill is priced at the last day of its service period (v5.4.2-03 convention; v5.4.2-10, strict) (v5.4.2-10 — the coordinate pair is bound to the invoice, its run and its correction election)
psql:/tmp/probe.sql:63: NOTICE:  PROBE 08 future recorded_at REFUSED [23514] snapshot rejected for invoice CODEX-ISSUE: recorded_at may not lie in the future (it is the transaction-time coordinate the run used, AC-15) (v5.4.2-10 — the coordinate pair is bound to the invoice, its run and its correction election)
psql:/tmp/probe.sql:63: NOTICE:  PROBE 08 pre-creation recorded_at REFUSED [23514] snapshot rejected for invoice CODEX-ISSUE: recorded_at 2026-10-14 01:18:55.963068+00 predates the invoice's creation 2026-10-15 01:18:55.963068+00 — an off-run bill's knowledge cannot be older than its draft (v5.4.2-10 — the coordinate pair is bound to the invoice, its run and its correction election)
psql:/tmp/probe.sql:63: NOTICE:  PROBE 08 missing snapshot ISSUE REFUSED [23514] invoice CODEX-ISSUE cannot be issued (status pending) without a calculation snapshot (CI-015): insert invoice_calculation_snapshots in the same transaction, after the line items

psql:/tmp/probe.sql:71: NOTICE:  PROBE 08 snapshot coordinate rewrite REFUSED [42501] permission denied for table invoice_calculation_snapshots
==== 09-complete-gas-correction.sql
cd210000-0000-4000-8000-000000000002
2
psql:/tmp/probe.sql:60: NOTICE:  PROBE 09 same amount-only line: period_end gap=<NULL>, correction valid_at gap=usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed
psql:/tmp/probe.sql:60: NOTICE:  PROBE 09 January classification=fixed_monthly, February classification=per_unit_usage

{"invoice_id": "cd210000-0000-4000-8000-000000000006", "had_payment": false, "credit_balance": 0.00, "invoice_number": "CODEX-ORIGINAL", "reads_released": 0, "ledger_entry_id": "2a020454-1123-43ca-b1b7-017e3088aafd", "rebill_expected": true, "reversal_amount": -10.00, "void_reason_code": "wrong_rate", "charges_auto_reverted": 0, "charges_pending_review": 0, "reverses_ledger_entry_id": "6a30000e-a8f9-4bbe-91f7-852ae776aa15", "duplicate_no_match_warning": false}

psql:/tmp/probe.sql:88: NOTICE:  PROBE 09 CORRECTION ACCEPTED after ALL checks: complete February per-unit gas rider, no gas_commodity_rate (expected)
```
