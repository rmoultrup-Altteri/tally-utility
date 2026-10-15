# Codex — v5.4.2-21 r1

Verdict: **not yet**.

Source-only review, 2026-10-14. No Docker, database execution, strict apply, CI, race, or mutation result is claimed here. **Predicted** means a source conclusion, not a reproduced database result. **Probe NN** also means unexecuted: the corresponding self-contained SQL file awaits the author's output. No other reviewer's r1 was consulted.

The four hashes were checked before examining the patch and matched:

| Frozen file | md5 |
|---|---|
| patch-21-frozen-r1.sql | `0900a47c5d7baf90e43e9064162ae4b7` |
| battery-21-frozen-r1.sql | `da9e348164fba0f955068a28ed9e9a25` |
| labels-21-frozen-r1.sh | `12cb39e6948c63fbdaf9b51d15c40365` |
| mutations-21-frozen-r1.py | `d263033b4b0760e84c7cf492340839f0` |

## Blocking items

**B1 — probe 01: an unclassifiable surcharge passes the advertised fail-safe check.**

In `invoice_line_arithmetic_gap()` (frozen patch:328–337), only a NULL `rate_item_id` is rejected. A non-NULL header with no version at the requested coordinates gives NULL `v_calc`; `coalesce(v_calc IN (...), false)` then requires no arithmetic. `rate_item_as_of()` returns an empty set in this case; it does not raise (`tu.sql:16009–16024`). The line's FK proves only that the header exists. A missing assertion, a valid-time gap, or an assertion invisible through RLS is not evidence that the item is fixed or percentage based.

Concrete path: create an item header without a version; create a gas surcharge naming it, with no quantity, unit, rate or gas figures; snapshot the draft; issue it. Probe 01 runs as `tally_app` and forces **ALL** deferred constraints, not just the new arithmetic trigger. Predicted result: `PROBE 01 ISSUE ACCEPTED`. This contradicts A4's stated fail-safe rationale that an unclassifiable line cannot be shown to need nothing.

Required change: require a visible, same-tenant rate assertion at the selected coordinate before deciding which arithmetic is optional. Refuse an absent classification explicitly. Add this case alongside the existing NULL-pointer case, including an actual issuance test.

**B2 — probe 02: classification uses the wrong coordinates for a legitimately bound correction.**

The gate always calls the helper with `(NEW.period_end, now())` (patch:389). The decision says to recognize per-unit surcharges at the **bill's coordinates**. The -10 binding explicitly permits a correction's `valid_at` to be a custom/current date and its `recorded_at` to be the original bill's knowledge instant (`tu.sql:20720–20845`). Those are validated and frozen; they are no longer arbitrary caller-supplied coordinates.

Concrete path: the same item is fixed in January and per-unit from February. Correct a January bill using a valid, frozen custom rate date of February 28. The correction has a gas surcharge naming that item with no arithmetic. Its snapshot valid_at resolves the per-unit version, but the new gate resolves January's fixed version and admits the line. Probe 02 builds and voids an original bill through the ordinary app path, creates the correction run and target, takes the correction snapshot, then forces **ALL** deferred constraints. Predicted result: `PROBE 02 CORRECTION ACCEPTED` despite the helper reporting missing figures at the correction's valid_at.

The reverse classification change can require usage/gas figures that a legitimately fixed-price correction did not use. Transaction-time reclassification produces the analogous problem for original-world replay. Copying the -07 surcharge gate is not sufficient justification: its comment still reasons from the pre--10 unbound snapshot model.

Required change: resolve arithmetic classification from the bill's validated calculation coordinates (or an equally strong binding to the assertion actually used). If current regulatory eligibility must also be checked, keep that separate from the arithmetic of the price actually calculated. Preserve a final issuance check and explicitly handle missing classifications as B1 requires.

## Should-fix items

**S1 — probe 04: the retention invariant does not cover label TRUNCATE guards.**

The patch creates ENABLE ALWAYS `no_truncate` on both label tables, but `assert_no_hard_delete_invariants()` checks only their DELETE guard. Disabling both label `no_truncate` triggers still satisfies this invariant. The actual frozen guards are present, so this is a drift-detection gap, not a present app TRUNCATE exploit. D4's narrow inventory and the function's detailed COMMENT accurately describe the smaller check; the patch header's claim to check “L's guards” is broader. Include L5's exact trigger definitions and ENABLE ALWAYS state. Probe 04 makes only transactional catalog changes and rolls them back.

**S2 — predicted; probe 05 supplies stronger baseline cases: two mutation catches are diagnostic-sensitive rather than demonstrations of the named forbidden write.**

- M12 permits changing `notes` in the write-once comparison. K3a changes notes **without** a retirement reason. The mutant still refuses that UPDATE in the subsequent “only change … retirement” branch. The battery fails because the error is not “write-once,” and the runner counts the named FAIL. Test changing notes **together with a valid retirement** to show the behavioral hole directly.
- M16 removes the already-retired branch. K3d tries to clear reason/time. The mutant still refuses because the reason is NULL. Again a different diagnostic produces the counted failure. Test rewriting a retired row's reason/by/stamp with a non-NULL reason; that is what the removed branch permits. It does not actually permit revival because UPDATE still stamps `retired_at := now()`.

Probe 05 runs those stronger cases against the unmodified frozen patch; both should refuse with 23001. It does not install or run mutations. The reported 44/44 may be accurate under the runner's definition, but is not equivalent to 44 independently demonstrated admissions of invalid state.

**S3 — predicted: broaden the label-lock deadlock and operational-cost documentation.**

The exception in the header is not limited to two deletions of the *same* label. Example: A deletes unused label K1 and obtains SHARE(customers); B deletes different unused K2 and obtains a compatible SHARE(customers); A and B subsequently both update customers and each waits to upgrade against the other's SHARE. Both labels can even belong to different tenants. Cross-table ordering creates further cycles. Retrying the whole transaction on 40P01 is appropriate, but the current “cannot deadlock, except … same label” statement is too strong.

SHARE blocks every INSERT/UPDATE/DELETE/COPY writer on the entity relation, across tenants and irrespective of the label/key involved, until transaction end. It also conflicts with maintenance/DDL lock modes such as SHARE UPDATE EXCLUSIVE. Reads and ordinary row-locking SELECTs are not generally stopped by SHARE itself. A waiting SHARE request can also queue later conflicting writers behind it. Thus a label delete in a long administrative transaction can interrupt ordinary posting/payment/customer work well beyond that label. Explain this table-wide scope and keep these transactions short; rarity alone is not a bound on latency.

**S4 — predicted: document and test the Cognito superuser exception as an explicit requirement qualification.**

U1 says once set the binding never changes or clears. The implementation deliberately exempts superusers, and its function COMMENT mentions repair. The ordinary app path is correctly fenced, but the inventory/decision summary does not mention this exception, unlike G6. Reconcile the wording and add the repair-path positive case if this exception is intentional. This is not a request to redesign the accepted Cognito/session trust model.

## Notes and requirement coverage

**N1 — predicted: retention D and retirement K substantially match the inventory.** The list has sixteen entries. Each gets unconditional row DELETE and statement TRUNCATE guards, ENABLE ALWAYS; the app loses both privileges. A definer or FK cascade that actually deletes a retained row still fires the row guard. A rewrite that suppresses DELETE removes no row; no new deleting rule or definer escape is introduced here. The claim is under the installed catalog, not against a superuser deliberately dropping/replacing guards. The invariant pins trigger definitions and effective app privileges, not function bodies, arbitrary rule behavior, every other role's ACL, or future DDL.

K's frozen-column tuple covers the preexisting dependency columns. Birth is live-only, retirement is server-stamped, reason is nonblank, retired rows reject all updates, the partial unique index and cycle walk count live rows, and retirement still takes the schedule mutex. `retired_by` remains optional and is not stamped from the session or tenant-bound; K1 does not require either. R3's lack of effective dating remains the declared limitation.

**N2 — predicted; probe 03: label locking implements a deletion-time check, not referential integrity.** At READ COMMITTED the volatile trigger's query after obtaining SHARE can see committed writers it waited for; COPY and writable CTE writers acquire the same table writer lock as ordinary DML. RR and SERIALIZABLE are rejected by the explicit equality test. The predicate checks the label's tenant as well as its key, including for a platform admin. A caller without a valid active user cannot reach a tenant label to DELETE; an active platform admin sees all tenants, with the guard's explicit tenant filter still selecting the right uses. Entities with no metadata are intentionally exempt.

The deleting transaction does not conflict with its own SHARE lock. It can DELETE an unused label and then add a use, including in a single dependent writable CTE (probe 03). A different writer admitted after deletion commits can likewise create a dangling key: LR2 explicitly expects this to succeed. This is consistent with the inventory's explicit no-writer-side-code/deletion-time design, but not with a stronger promise that a committed key always has a surviving definition. Treat probe 03 as a scope clarification, not another blocker under the stated L3 design. Renaming a definition is also outside this DELETE-only guard.

**N3 — predicted: ordinary arithmetic gates are otherwise sensible, but the battery isolates them more than its headline implies.** A1's code skips draft/held edits, already-issued transitions, and UPDATE-to-void discards; it checks INSERT into issued states. A2/A3 implement presence and all-or-none coverage, A4 includes gas data for gas per-unit/tiered surcharges, and A5/A6 intentionally do not check multiplication or equality of the two rates. No positive/negative numeric policy is added.

An ordinary same-transaction line INSERT/UPDATE/DELETE after issuance sees the issued parent and is rejected by the existing line immutability trigger; moving a line onto an issued invoice is checked too. SET CONSTRAINTS IMMEDIATE does not remove that guard, and switching back to DEFERRED does not cancel future trigger events. The new FOR SHARE follows the siblings' existing-row locking model. It should not be advertised as a predicate lock against every possible concurrent new line; this review does not establish a new concurrency proof for that inherited model.

`pg_temp.issue()` runs only `enforce_invoice_line_arithmetic`, then deliberately rolls its subtransaction back. Its successes do not demonstrate successful complete issuance. This is good unit isolation, but needs integrated cases such as probes 01/02. The issued→issued gate and lines' FOR SHARE mutation gaps are acknowledged in the brief. Missing-version and correction-coordinate coverage are additional gaps.

**N4 — predicted: lineage G is implemented, with the stated limits.** G1's CHECK forces the correction pointer even on drafts, while the existing snapshot gate checks the predecessor is same-tenant, void, and previously issued; another duplicate guard is unnecessary. G2 uses `coalesce(..., false)`, so NULL reasons cannot exploit CHECK's three-valued logic. G3's tenant-composite FK prevents cross-tenant reversal pointers without imposing the explicitly undecided same-customer restriction. G4 requires exactly one refund source, preserves negative-refund semantics, binds a credit to the same tenant/customer, and freezes the new pointer after pending. G5 remains optional; G6 has the specified superuser history-load exception. The five partial indexes are created, though G7's battery checks names only, not actual indexed columns or predicates.

**N5 — predicted: the void changes follow V1–V4; the stamp means issuance history, not proof of a ledger post.** For an ordinary app lifecycle, draft/held→issued-other-than-void stamps `first_issued_at`; it cannot be cleared by the app, and an issued bill cannot return to draft/held. A born-issued app bill gets no stamp, but cannot establish the required snapshot after birth because snapshots require a draft/held parent; the final snapshot gate prevents that normal path from completing. A stamp can exist without a charge: issuance does not insert one, which is exactly why V1 must refuse the void when the lookup fails. Conversely the app's ledger INSERT privilege does not structurally prohibit attaching an invoice charge to a held bill. Thus “posted iff stamped” is the accepted lifecycle convention, not a bidirectional ledger invariant. Superuser history loads can also create stamp/status combinations outside that convention.

The charge query is under `tally_void` RLS, has an explicit invoice tenant filter, reference type/id and charge type, and a deterministic `(created_at, id)` order. Ledger rows are append-only, so the chosen row cannot ordinarily disappear after lookup. The query does not bind the charge's customer to the invoice's customer or verify its amount; those remain posting correctness responsibilities, not newly inferred requirements. The refusal precedes the release/update/insert steps, and held discards leave reversal payload/event fields NULL. CREATE OR REPLACE preserves the function's sealed owner/ACL, and the added ledger columns require no new privilege beyond its existing INSERT. The -20 invoice-first lock and isolation pin remain. This is a source conclusion, not a rerun of the -20 race suite or the seal invariant.

**N6 — predicted: identity U and notes N otherwise match.** Both canonical RLS helpers now require `is_active`, with unchanged signatures, definer mode and empty search_path. The canonical tenant policies use those two helpers; no new helper grants an inactive identity tenant access. This does not revoke access to deliberately shared, non-tenant vocabulary tables. Cognito uniqueness/format and app write-once behavior are correctly expressed; a NULL service-user subject is allowed. N1 uses quoted current_database(); N2's wording and N3's PostgreSQL-16 rendering caveat are present. The marker is inside the atomic patch transaction, so a normal failed first application does not leave the skip marker committed. A second invocation's skip is not a schema-drift validation.

**N7 — predicted: older-test edits preserve their broad purposes, with narrower assertions acknowledged.** The -10/-11 base rates and -13 gas figures supply the new mandatory fixture fields without changing their coordinate/isolation/backbilling targets. Planting charge ledger entries before posted voids supplies V1's prerequisite. RC5b's superuser stamp on H3 is a synthetic posted fixture and preserves its one-reversal race assertion; it is not a test of normal issuance. F11a now tests the earlier lineage CHECK rather than reaching the snapshot branch. Q4d tests write-once refusal rather than the cycle walk on an editable edge; Q4f/Q4h now exercise retire/re-add and live-edge semantics. C8 now proves privilege refusal, with trigger enforcement separately covered by the new suite. These shifts should remain explicit in labels/comments.

The -21 race harness verifies B was blocked by A, which is stronger than timing-only evidence. LR2 intentionally tests waiting, not rejection of a dangling use; LR3 tests RR, not a separate SERIALIZABLE leg. D1's TRUNCATE CASCADE failures can originate from another cascaded retained table; the exact catalog invariant supplies the per-table structural evidence. The mutations runner uses merged stdout/stderr and the first named failure, but accepts some label suffix variants and counts diagnostic failures as described in S2. The frozen mutation file is a review copy whose path-derived ROOT would differ if executed in the review directory; I did not run it, as instructed.

**N8 — predicted: residuals R1–R5 do not independently block this agreed scope.** R1's `-amount_due` and earliest-charge policy, R2's merely tenant-bound reversal link, R3's transaction-time retirement, R4's presence-only arithmetic, and R5's deferred tu.sql mirror decision are all explicitly disclosed. B1/B2 are not any of those residuals: they concern whether required arithmetic is present and which version determines that requirement. R1/R2 still require correct posting behavior from the core and should not be described as reconciliation guarantees.

## Probe handoff

Run each file independently with psql as superuser `tally` against a disposable clone with the frozen patch already applied. The files do not create/drop a database or change roles; all fixtures and catalog changes are inside BEGIN/ROLLBACK. App operations use SET ROLE and transaction-local `app.user_id`. Setup errors stop execution; caught target outcomes are printed as `PROBE` notices, not converted into claims of success.

| File under `codex-r1-probes/` | Predicted result / interpretation |
|---|---|
| `01-missing-rate-version.sql` | NULL gap and complete issuance accepted: B1 reproduced |
| `02-classification-coordinate.sql` | Different gaps at the two dates; complete correction accepted: B2 reproduced |
| `03-label-writable-cte.sql` | Deleted label plus a surviving use: N2's deliberately narrow guarantee |
| `04-label-truncate-invariant.sql` | Invariant accepts disabled label truncate guards: S1 reproduced |
| `05-dependency-edit-with-retirement.sql` | Both stronger negative cases refuse with 23001: stronger S2 baselines |

Append actual outputs below and keep unexpected refusal details: a fixture failure is not evidence that the target rule is safe. The supplied probes have been inspected as source only. Strict apply twice, the full CI pass, LR1–LR5, and 44/44 mutation results remain the author's reported evidence, not independently reproduced results of this review.

## Probe outputs (run by the author, 2026-10-14, on a clone of tally with patch-21-frozen-r1.sql strict-applied; psql -X -q -At, NOTICE lines kept)

```
==== 01-missing-rate-version.sql
cd210000-0000-4000-8000-000000000002

psql:/tmp/probe.sql:59: NOTICE:  PROBE 01 helper gap for absent version = <NULL> (NULL means admitted)
psql:/tmp/probe.sql:59: NOTICE:  PROBE 01 ISSUE ACCEPTED after ALL deferred checks; first_issued_at=2026-10-15 00:41:59.592959+00
==== 02-classification-coordinate.sql
cd210000-0000-4000-8000-000000000002
2
psql:/tmp/probe.sql:59: NOTICE:  PROBE 02 same amount-only line: period_end gap=<NULL>, correction valid_at gap=usage_quantity, usage_unit, rate, gas_meter_factor, gas_ccf_used, gas_therms_billed, gas_commodity_rate
psql:/tmp/probe.sql:59: NOTICE:  PROBE 02 January classification=fixed_monthly, February classification=per_unit_usage

{"invoice_id": "cd210000-0000-4000-8000-000000000006", "had_payment": false, "credit_balance": 0.00, "invoice_number": "CODEX-ORIGINAL", "reads_released": 0, "ledger_entry_id": "3fe43ff1-721d-4194-a991-dd311b8e7e99", "rebill_expected": true, "reversal_amount": -10.00, "void_reason_code": "wrong_rate", "charges_auto_reverted": 0, "charges_pending_review": 0, "reverses_ledger_entry_id": "a0f2db68-46fd-4fb5-a9b8-5d79f3404405", "duplicate_no_match_warning": false}

psql:/tmp/probe.sql:87: NOTICE:  PROBE 02 CORRECTION ACCEPTED after ALL checks: bound February per-unit version, no arithmetic
==== 03-label-writable-cte.sql
cd210000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:33: NOTICE:  PROBE 03 delete-then-write CTE accepted: inserted=1 label_exists=f key_in_use=t
==== 04-label-truncate-invariant.sql
psql:/tmp/probe.sql:8: NOTICE:  PROBE 04 baseline invariant accepted
psql:/tmp/probe.sql:18: NOTICE:  PROBE 04 invariant ACCEPTED with both label no_truncate triggers disabled
==== 05-dependency-edit-with-retirement.sql
cd210000-0000-4000-8000-000000000002
psql:/tmp/probe.sql:30: NOTICE:  PROBE 05 simultaneous edit/retire REFUSED [23001] rate_item_dependencies: dependency cd210000-0000-4000-8000-000000000007 is write-once — retire it and add a new one (CI-014, v5.4.2-21)
psql:/tmp/probe.sql:41: NOTICE:  PROBE 05 retirement rewrite REFUSED [23001] rate_item_dependencies: dependency cd210000-0000-4000-8000-000000000007 is retired, and a retirement is permanent — add the dependency again (CI-014, v5.4.2-21)
```
