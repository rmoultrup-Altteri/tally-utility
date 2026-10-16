# Codex review — v5.4.2-22, round 2

**Verdict: not yet.** Source only. All review conclusions and database outcomes below are **predicted**, not executed by this reviewer. B1 and B2 remain blocking. The author's appended r1 executions are historical evidence, not r2 executions.

## Scope and evidence

Before reading the implementation I checked all four frozen files. Their MD5s match:

| File | MD5 |
|---|---|
| patch-22-frozen-r2.sql | `0d91882c1f3fb4b58c8594b69018e51d` |
| battery-22-frozen-r2.sql | `4049de7b97362cf08760250f2824bb79` |
| close-22-frozen-r2.sh | `2b7149d76c6e57e3e1c0a769bb710ef6` |
| mutations-22-frozen-r2.py | `7af6f68adecefdc45e3a27b470bd8dd6` |

Read the brief, my r1 report including all appended author outputs, the consolidated r1 dispositions, the r1–r2 diff, the frozen implementation/test sources, and relevant final definitions in `sql/tu.sql`. Read D-2/D-3 in `../gas-billing-memory/application/kyle-decisions-2026-08-18-coda-items.md` and R-02/K-05/K-07 in `kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md`. No `opus-*.md` or `fable-*.md` was read. No Docker, psql, CI, race or mutation execution was performed.

**Scope limitation:** `../gas-billing-memory/application/wave2-build-2026-10-15/source-inventory-wave2.md` and `../gas-billing-memory/application/DECISION-LOG.md` are absent from this checkout; a filename search of the sibling repository found no replacement. Consequently, inventory coverage below uses the requirement mapping in the supplied brief, patch and battery, plus the available original rulings. It is not an independent certification of the missing inventory or seven drafting calls.

Every database outcome asserted below has a source probe in `codex-r2-probes/`. Each file is standalone owner/superuser psql input for a fresh clone with the frozen r2 patch already applied, uses a transaction ending in `ROLLBACK`, requires no commit or cluster-role change, and reports caught errors with `RAISE NOTICE`, SQLSTATE and message. Ordinary-role cases use `SET ROLE`. **None has been executed.** Unexpected setup failures stop the probe; their output must not be counted as confirmation of the claimed guard.

## Blocking items

### B1 — A forward reference bypasses the new write-off recovery restriction

**Predicted.** Patch lines 492–502 and 521–524, `enforce_write_off_recovery()`; W3/R-02. Probe: [b1-forward-writeoff.sql](codex-r2-probes/b1-forward-writeoff.sql).

As `tally_app`, insert two rows in this order in one VALUES statement:

1. Adjustment `+100`, naming UUID W as `reverses_ledger_entry_id`.
2. Write-off W, `-50`, with no parent.

The BEFORE trigger checks whether the adjustment's target is already a visible write-off. W is not yet inserted, so that branch returns NEW. W's own trigger returns immediately because it names nothing. The statement-end composite FK finds W; the AFTER lineage walk sees an acyclic adjustment → write-off chain and has no type/cap check. Predicted result: both rows are accepted.

The probe next inserts a properly typed recovery `+50` naming W. The sum used for the cap includes only `write_off_recovery`, so this is also predicted to succeed: all named reversals total **150 against a 50 write-off**, while the typed-only sum is 50. The first statement already violates the rule even without that follow-up.

This is a path around r1 disposition #3, not a request to implement -23's general reversal policy. It uses no disabled guard, elevated role, concurrent session or invalid FK. Validate the target-type rule after all statement rows are visible, or reject unresolved forward references before admission. Preserve serialization for the aggregate cap; add this ordering to the regression cases.

### B2 — The lineage walk admits cycles longer than 10,000 entries

**Predicted.** Patch lines 548–554, `enforce_ledger_lineage_acyclic()`; W1, S1/S2 and r1 disposition #1. Probe: [b2-long-cycle.sql](codex-r2-probes/b2-long-cycle.sql).

The recursive walk stops at `u.depth < 10000`, and rejects only if a visited id equals NEW.id. It neither rejects exhaustion of that bound nor proves that a root was reached.

Insert a ring of **10,001 adjustments**, all in one tenant/customer, with row i naming i+1 and the last naming the first. Every row's first return to itself occurs at depth 10,001, outside the walk. All targets exist by the FK checks, and each new row's walk terminates without a match. Predicted result: the complete cycle is accepted with all guards enabled.

The new aging coverage check is a useful improvement: it is predicted to raise `22000` for these rows instead of silently losing their amounts. The close calls that helper and is predicted to fail atomically, leaving the period open and without a snapshot. This is still blocking: an ordinary accepted write can leave append-only ledger history that cannot be aged or closed through its dates. Offsetting amounts does not supply the missing root. R8 explicitly promises loop rejection and does not defer this case.

Use complete cycle detection, or fail closed when a supported maximum depth is exceeded. The probe is deliberately expensive (approximately 100 million recursive steps); it has no reduced-depth replacement or disabled trigger. A timeout/cancellation would be inconclusive, not a successful cycle rejection.

## Should-fix items

### S1 — Correct the remaining three-argument snapshot reproduction instructions

**Predicted.** Patch `COMMENT ON TABLE accounting_period_snapshots` still says `receivables_aging_as_of(tenant, period_end, recorded_at)` reproduces its aging lines. That contradicts r2's corrected header and four-argument function comment. Battery C12 also uses the three-argument form, although CR7 correctly supplies the stored edges.

Probe: [n5-snapshot-edges.sql](codex-r2-probes/n5-snapshot-edges.sql). Predicted outcome: a tenant-setting change and valid manually backdated history leave reproduction using captured edges unchanged, while the three-argument result changes at the same timestamp. Fix the table comment and make the snapshot-specific battery assertion use stored edges. The underlying r1 B1 defect is addressed by the explicit-edge contract; this stale instruction tells consumers to invoke the wrong contract.

### S2 — Narrow or complete the invariant's “every -22 constraint” claim

**Predicted.** `assert_periods_guard_invariants()` now pins the important recovery/type checks, period/GL checks and exclusions, bucket checks, threshold check and immutability triggers. It does not include `tenant_configuration_history_key_known_check`, although -22 drops and reissues that CHECK to add both setting keys. Nor is its list a general enumeration of PK/FK/UNIQUE constraints.

Probe: [s2-invariant-scope.sql](codex-r2-probes/s2-invariant-scope.sql) drops only the history known-key CHECK inside a rollback transaction; the periods invariant is predicted to accept it. Add that CHECK to the intended list, or describe precisely which constraints are covered. This is a drift-detection omission, not an application-user DDL exploit. The explicit disclaimer that called function bodies are not checked remains correct.

### S3 — The expanded tests still omit the statement-order and depth boundaries

**Predicted, source assessment.** R7 targets an already-existing write-off; R8 is a two-row loop. They do not cover B1's absent-at-BEFORE-time target or B2's cutoff. Add those cases, plus writable-CTE and COPY loop coverage. The probes supply all four concrete cases.

CR10 performs close then withdrawal in successive committed transactions; it is not a withdrawal-versus-close race. There is no two-tenant movement-versus-close race, or withdrawal-versus-append race. CR3/CR4 exercise REPEATABLE READ, not SERIALIZABLE. CR3 remains sleep-orchestrated, so the header's “every race leg” observed-blocking claim is broader than that case. These are coverage limitations, not assertions that those races corrupt data.

Mutation attribution is better than accepting any failure: the runner requires the named first failing check or an apply-error phrase. However, `[a-z]?` permits a suffix when the expected label has none, so “exact named check” is slightly broader than literal equality. I found no specific additional wrong-reason mutation result established by source inspection. The author's 52/52 remains author-reported; it does not prove the omitted shapes.

## Notes and disposition of r1 findings

### N1 — R1 closure assessment

**Predicted.** The following table distinguishes repaired paths from broader promises still incomplete. `n1-battery-regression.sql` is the frozen r2 battery copied into a standalone probe, with full caught-error notices; it has not been run.

| r1 disposition | r2 source assessment | Probe |
|---|---|---|
| #1 cycles | Original two-row loop rejected; longer rings remain B2 | n1 R8/W16; n6-cycle-shapes; n7-copy-cycle; b2 |
| #2 captured/validated edges | Explicit captured-edge reproduction addresses the original defect; stale guidance is S1 | n1 W1d/W10/W12b; n5 |
| #3 write-off target restriction | Existing-target rejection added; forward target remains B1 | n1 R1–R8; b1 |
| #4 future-recorded ledger | Close explicitly checks all dated rows through period end for created_at beyond its instant | n1 C19 |
| #5 cross-tenant payment move | Both old/new heads now selected and locked; old/new dates checked against their respective heads | n1 F2e |
| #6 GL precedence | Weights 8/4/2/1 explicitly prioritize charge/class/territory/tax | n1 G5/G6 |
| #7 GL recorded clock | Both birth and closure now use clock_timestamp | n1 G1d/G7d; n3-gl-coordinate |
| #8 invariant strength | Exact definitions replace name-only recovery checks; ledger immutability added; S2 qualifies breadth | n1 I1; n4-invariant-definition |
| #9 correction of latest open period | Status withdrawal preserves retained row and frees dates; nonlatest/closed withdrawals guarded | n1 P9/C17 |
| #10 W3 threshold | Typed nullable positive threshold and history recorder/backfill added | n1 W15/W15b |
| #11 test gaps | Earlier-instant status, chain/early-dated reversal, UTC-12 end and GL race sources added; I4 relabelled; S3 remains | n1 C5/W4b/W14/I4; race source CR9 |
| #12 close customer grant | customers.tenant_id removed from close grants and exact allowlist | n1 I1/I2 and successful-close cases |

My original four blocking examples are addressed at their original sizes/shapes. The new B1 and B2 mean the broader r1 findings are not fully closed. The author's r1 probe outputs substantiate the old defects; they do not establish the r2 results in this table.

### N2 — Freeze, withdrawal and lock-order assessment

**Predicted, source assessment.** The freeze remains on ledger INSERT and payment/credit INSERT or UPDATE of date/tenant. Ledger immutability supplies the other half of its INSERT-only protection. The head is locked before comparison, with no superuser exemption. On a tenant move, the sorted two-head FOR SHARE query precedes the old-head read and destination check. This addresses the concrete old-tenant omission.

Withdrawal is an UPDATE guarded by open → withdrawn, unchanged non-withdrawal fields, the chain advisory lock and a latest-active-period query. Both the no-gap query and overlap exclusion disregard withdrawn rows. Close retains head → period locking, rereads status after locking, and ignores withdrawn periods in its first-close ordering check. I found no additional concrete single-operation corruption path in these sources. This is **not** a proof of deadlock freedom across arbitrary transactions: the period UPDATE acquires its target tuple before its BEFORE trigger takes the chain advisory lock; sorting heads within one trigger also does not order all locks acquired by preceding statements. No multi-session outcome is claimed or reproducible under this review's single-session/no-commit probe constraints. The missing schedules are identified in S3.

Single-session predictions are covered by n1 H/P/C/F and [n2-statement-regression.sql](codex-r2-probes/n2-statement-regression.sql): contiguous multi-row periods, multi-row typed recovery overflow rejection, a consumed writable ledger CTE followed by close (snapshot and ledger 75), and rejection of a subsequent write into that closed period. The period guards, close's UTC-12/order checks, snapshot guards, and head guard reveal no further ordinary-role edit/reopen/delete/born-closed or direct-snapshot/head-write route in this source review. That conclusion is bounded by these probes and the two blockers, not a universal safety proof.

### N3 — Seal comparison and least privilege

**Predicted, source assessment; catalog/functional probe: n1 I1–I5 and C/H cases.** A source diff against the final -21 `assert_seal_role_invariants()` shows the old executable checks preserved, with the third role's ownership/grant entry, the two new tally_void head grants, the extended role loop and new close-table reachability checks. It is not literally unchanged text: comments and the new checks differ. No old seal guard was removed.

The patch creates tally_close NOLOGIN, NOSUPERUSER and NOBYPASSRLS, assigns only the pinned SECURITY DEFINER close, and compares its explicit grants. The invariant checks memberships in both directions, default privileges, code-creation capability, ownership and PUBLIC relation privileges. The four-argument invoker aging helper's validator/head reads have corresponding grants. The removed customer tenant-id column is unnecessary to the query's own selected columns. Existing runtime role/catalog state was not inspected.

`tally_void` needs an UPDATE privilege to take the head row lock, and `updated_at` is a suitable lock column whose actual unauthorized update is rejected by the guard. Table SELECT is sufficient but not literally column-minimal: the freeze reads tenant_id and closed_through, not updated_at. This extra timestamp visibility is not a blocking write capability.

The seal invariant's comment still says only tally_close writes period status, whereas tally_app now holds status UPDATE for withdrawal. The function's check was intentionally changed to app closed_at UPDATE. Describe controlled closing versus withdrawal accurately.

### N4 — Snapshot figures, aging, coordinates and RLS

**Predicted; probes n1 C9–C12/C17/C18, W1–W16; n5; n8-aging-rls.** Opening is the sum before period_start, activity is inclusive of both endpoints, and closing is opening plus activity. Entry count is in-period ledger count. Activity lines group by ledger type; aging lines aggregate customer buckets and count distinct customers in each bucket, with credit balances separate. Unbilled revenue/basis are supplied because the database lacks the core's estimate inputs; the monetary ledger figures are computed. No accrual ledger type or posting was introduced. Existing tenant/date ledger indexes support arbitrary date windows, consistent with D-2.

For an acyclic visible same-customer forest, transitive netting, newest-first allocation of remaining positive debt and separate negative balances implement the documented balance-forward model. Roots whose parents are outside the date/recorded window or belong to another customer stand independently. The chain and early-dated reversal fixtures exercise that behavior. Status comes from state-event history at the recorded instant; location is the latest located ledger entry. Snapshot lines aggregate amounts, so live customer-number presentation is not itself a changed snapshot figure.

The overloads are invoker-rights, require explicit coordinates, and have no live-setting fallback. The four-argument version validates the supplied edges and checks visibility through the head. The three-argument version uses configuration history and raises when it has no value. n8 predicts tenant-one sum 100, refusal of that tenant user's request for tenant two with P0002, and platform-admin requests returning only the requested tenant's 100 or 200. RLS is not replaced by mere caller-provided UUID filtering.

With stored edges and the new future-recorded-row rejection, the original reproduction defects are addressed. B2 prevents a universal successful-close conclusion. Generic historical configuration lookup remains different from snapshot reproduction, as S1 explains.

### N5 — Inventory/rulings and residuals R1–R9

**Predicted, source assessment.** Against the available D-2/D-3/R-02 rulings and brief mapping, the patch supplies the intended periods/freeze, computed close snapshot, tenant GL configuration, aging with status, recorded threshold and recovery type. W3/R-02 remains incomplete because of B1; the unconditional no-loop promise remains incomplete because of B2. Exact missing-inventory certification is unavailable for the reason stated above.

R1/R2 are explicit staged limits on other money-event/status coupling; R2's sentence that a status change writes its own ledger row describes the intended -23 workflow, not an enforced -22 property. R3 defers per-bill allocation, while this patch implements customer-level balance-forward aging. R4 transaction-time status and R5 last-located-entry approximation are disclosed. R6 duplicated vocabulary needs maintenance. **R7 has changed since r1:** it now defers GL place-kind validation; the old equal-specificity tie residual is gone. The 8/4/2/1 source algorithm distinguishes matching key masks; the EXCLUDE constraint covers overlapping identical keys. G2's unmapped-line export refusal still belongs to the core, not a GL posting subsystem here.

R8 may defer general reversal sign/cap rules but cannot excuse either a reversal of a write-off escaping its explicit cap or admitted cycles. R9's history boundary is explicit in the three-argument API; captured edges are a separate caller-supplied reporting coordinate. No other listed residual independently warrants blocking within the brief's staged scope.

## Probe index and execution boundary

All files are under `tests/v5.4.2-22/review/codex-r2-probes/`:

| ID | Purpose / predicted outcome |
|---|---|
| b1-forward-writeoff.sql | Forward adjustment accepted; named reversal total 150 against write-off 50 |
| b2-long-cycle.sql | 10,001-node cycle accepted; aging and close raise 22000 |
| n1-battery-regression.sql | Frozen battery scenarios, with SQLSTATE/message notices; expected to pass its existing checks |
| n2-statement-regression.sql | Original r1 statement-shape and typed-cap regressions |
| n3-gl-coordinate.sql | Same-transaction mapping closure no longer changes an earlier lookup |
| n4-invariant-definition.sql | Vacuous recovery CHECK now refused by periods invariant |
| n5-snapshot-edges.sql | Stored edges reproduce; mutable history is not the reproduction contract |
| n6-cycle-shapes.sql | Two-row VALUES and writable-CTE cycles refused with 23514 |
| n7-copy-cycle.sql | Owner/superuser COPY two-row cycle refused with 23514 |
| n8-aging-rls.sql | Tenant isolation and explicit platform-admin tenant selection |
| s2-invariant-scope.sql | Missing history known-key CHECK not detected by periods invariant |

n7 uses psql error variables and a savepoint to report the COPY error via RAISE NOTICE after restoring transaction usability. COPY is deliberately tested as owner/superuser because ordinary COPY FROM into an RLS table is not the supported application INSERT path. n4 and s2 contain only rollback-local schema perturbations to test the stated invariants; no role DDL. No probe commits, invokes Docker/CI/race runners, or changes any frozen source. The author must append actual outputs before treating these predictions as executed evidence.

---

## Appendix (author): executed probe outputs, 2026-10-15

Run by the author on `rv22main2`, a fresh `CREATE DATABASE … TEMPLATE tally` clone with TEMP revoked from PUBLIC, `tally_app` and `tally_core`, and `patch-22-frozen-r2.sql` (md5 `0d91882c…`) strictly applied (`search_path=''`, `check_function_bodies=on`). Each probe was run with `psql -U tally -v ON_ERROR_STOP=1 -f`.

| Probe | Executed result |
|---|---|
| b1-forward-writeoff | **Reproduced.** The forward adjustment was accepted. Named reversals total 150.00 against a 50.00 write-off; typed-only 50.00. |
| b2-long-cycle | **Reproduced.** A 10,001-row ring was accepted. Aging and the close both raise 22000; the period stays open with no snapshot. |
| n1-battery-regression | 135 PASS, no FAIL. |
| n2-statement-regression | As predicted: 3 contiguous periods; cap overflow refused (23514); CTE close snapshot 75 = ledger 75; the later write refused. |
| n3-gl-coordinate | As predicted: the lookup is unchanged after a same-transaction closure. |
| n4-invariant-definition | As predicted: refused (0LP01). |
| n5-snapshot-edges | As predicted: stored edges reproduce; the three-argument result changes after a manual backdated row. |
| n6-cycle-shapes | As predicted: VALUES and writable-CTE loops refused (23514). |
| n7-copy-cycle | **COPY refused, as predicted.** The trigger raised `its reversal chain returns to itself` (line 17). The probe's own summary line then said `SQLSTATE=00000 … COPY accepted cycle`. That is a defect in the probe's `\if :ERROR` capture, not the patch. |
| n8-aging-rls | As predicted: tenant sees 100; cross-tenant P0002; platform admin gets 100 and 200 per requested tenant. |
| s2-invariant-scope | **Reproduced.** The invariant accepted the dropped history known-key CHECK. |

The scope note is correct: the inventory and DECISION-LOG are not in gas-billing-memory. They are in this repository, at `application/wave2-build-2026-10-15/source-inventory-wave2.md` and `application/DECISION-LOG.md`. The brief listed them under the gas-billing-memory rulings, which misled the search. The r3 brief must give full paths.

### Raw output

```
=== b1-forward-writeoff.sql
BEGIN
SET
SET
DO
SET
psql:/tmp/cx2/b1-forward-writeoff.sql:54: NOTICE:  B1 forward adjustment accepted; target=c7bd299f-dbc4-45ee-a278-971848c48728 reversal=ea801ad2-fc74-4dba-9160-72c88602dc88
psql:/tmp/cx2/b1-forward-writeoff.sql:54: NOTICE:  B1 typed recovery accepted; all named reversals=150.00; typed-only=50.00; original=-50.00
DO
RESET
ROLLBACK
--- exit 0
=== b2-long-cycle.sql
BEGIN
SET
SET
DO
SET
psql:/tmp/cx2/b2-long-cycle.sql:65: NOTICE:  B2 inserted cycle rows=10001 sum=10001.00
psql:/tmp/cx2/b2-long-cycle.sql:65: NOTICE:  B2 aging SQLSTATE=22000 message=receivables_aging_as_of: 10001 ledger entries of tenant aefd75eb-2124-4fda-8b03-a0bad3df974a reach no original (a reversal loop); aging would omit them (v5.4.2-22)
psql:/tmp/cx2/b2-long-cycle.sql:65: NOTICE:  B2 close SQLSTATE=22000 message=receivables_aging_as_of: 10001 ledger entries of tenant aefd75eb-2124-4fda-8b03-a0bad3df974a reach no original (a reversal loop); aging would omit them (v5.4.2-22)
psql:/tmp/cx2/b2-long-cycle.sql:65: NOTICE:  B2 after failed close status=open head=<NULL> snapshot count=0
DO
RESET
ROLLBACK
--- exit 0
=== n1-battery-regression.sql
BEGIN
SET
SET
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
GRANT
INSERT 0 2
INSERT 0 4
INSERT 0 4
INSERT 0 1
INSERT 0 6
INSERT 0 1
psql:/tmp/cx2/n1-battery-regression.sql:107: NOTICE:  PASS H1 every tenant, a new one included, has a close head with nothing closed
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:110: NOTICE:  CAUGHT SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: a close head is born with nothing closed; only close_accounting_period() moves it (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:110: NOTICE:  PASS H2 a head is born with nothing closed: refused by born with nothing closed (tenant 00000000-0000-4000-8000-0000000022a1: a close head is born with nothing closed; only close_accounting_period() mo)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:113: NOTICE:  CAUGHT SQLSTATE=23001 message=tenant 00000000-0000-4000-8000-0000000022a1: the closed-through date moves only forward, and only through close_accounting_period() (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:113: NOTICE:  PASS H3 the owner cannot move the head: refused by only through close_accounting_period() (tenant 00000000-0000-4000-8000-0000000022a1: the closed-through date moves only forward, and only through close_accounti)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:116: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting_close_heads rows are never deleted: the closed-through date is the freeze every money write reads (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:116: NOTICE:  PASS H4 the owner cannot delete a head: refused by never deleted (accounting_close_heads rows are never deleted: the closed-through date is the freeze every money write reads (v5.4.2-22))
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:118: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting_close_heads rows are never deleted: the closed-through date is the freeze every money write reads (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:118: NOTICE:  PASS H4b nor truncate the heads: refused by never deleted (accounting_close_heads rows are never deleted: the closed-through date is the freeze every money write reads (v5.4.2-22))
 refuses_at 
------------
 
(1 row)

SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:123: NOTICE:  CAUGHT SQLSTATE=42501 message=permission denied for table accounting_close_heads
psql:/tmp/cx2/n1-battery-regression.sql:123: NOTICE:  PASS H5 the application holds no UPDATE on closed_through: refused by permission denied (permission denied for table accounting_close_heads)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:126: NOTICE:  CAUGHT SQLSTATE=23001 message=tenant 00000000-0000-4000-8000-0000000022a1: the closed-through date moves only forward, and only through close_accounting_period() (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:126: NOTICE:  PASS H5b the lock column it holds does not move the head either: refused by only through close_accounting_period() (tenant 00000000-0000-4000-8000-0000000022a1: the closed-through date moves only forward, and only through close_accounti)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:128: NOTICE:  PASS H6 the application sees only its own tenant's head
 ok 
----
 
(1 row)

RESET
SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:137: NOTICE:  PASS P1 the application opens January
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:140: NOTICE:  PASS P1b born open, created_by the session's user, created_at the database's
 ok 
----
 
(1 row)

 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:144: NOTICE:  CAUGHT SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: the next accounting period starts on 2026-02-01, the day after the latest ends — not 2026-01-15 (no gaps, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:144: NOTICE:  PASS P2 no overlap (the no-gap rule meets it first; EXCLUDE stands behind): refused by no gaps (tenant 00000000-0000-4000-8000-0000000022a1: the next accounting period starts on 2026-02-01, the day after the latest e)
psql:/tmp/cx2/n1-battery-regression.sql:148: NOTICE:  CAUGHT SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: the next accounting period starts on 2026-02-01, the day after the latest ends — not 2026-02-02 (no gaps, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:148: NOTICE:  PASS P3 no gap: the next starts the day after the latest: refused by no gaps (tenant 00000000-0000-4000-8000-0000000022a1: the next accounting period starts on 2026-02-01, the day after the latest e)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:152: NOTICE:  CAUGHT SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: an accounting period is born open; only close_accounting_period() closes it (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:152: NOTICE:  PASS P4 a period is born open: refused by born open (tenant 00000000-0000-4000-8000-0000000022a1: an accounting period is born open; only close_accounting_period() closes it)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:156: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "accounting_periods" violates check constraint "accounting_periods_range_check"
psql:/tmp/cx2/n1-battery-regression.sql:156: NOTICE:  PASS P5 the last day is on or after the first: refused by accounting_periods_range_check (new row for relation "accounting_periods" violates check constraint "accounting_periods_range_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:159: NOTICE:  PASS P6 February follows
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:162: NOTICE:  PASS P6b and March
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:165: NOTICE:  CAUGHT SQLSTATE=42501 message=permission denied for table accounting_periods
psql:/tmp/cx2/n1-battery-regression.sql:165: NOTICE:  PASS P7 the application cannot close a period by UPDATE: refused by permission denied (permission denied for table accounting_periods)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:168: NOTICE:  CAUGHT SQLSTATE=42501 message=permission denied for table accounting_periods
psql:/tmp/cx2/n1-battery-regression.sql:168: NOTICE:  PASS P7b nor delete one: refused by permission denied (permission denied for table accounting_periods)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:171: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002212: only the tenant's latest period, while open, may be withdrawn (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:171: NOTICE:  PASS P9a only the latest period is withdrawn: refused by only the tenant's latest period (accounting period 00000000-0000-4000-8000-000000002212: only the tenant's latest period, while open, may be withdrawn (v)
 refuses_at 
------------
 
(1 row)

 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:173: NOTICE:  PASS P9 the latest period, while open, is withdrawn (a mistyped one)
psql:/tmp/cx2/n1-battery-regression.sql:176: NOTICE:  PASS P9b it stays on record, stamped
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:179: NOTICE:  PASS P9c and its dates are free again
 admits 
--------
 
(1 row)

 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:182: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002213: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withdrawn (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:182: NOTICE:  PASS P9d a withdrawn period is not reopened: refused by never edited (accounting period 00000000-0000-4000-8000-000000002213: a period is never edited; it closes only through close_accountin)
RESET
psql:/tmp/cx2/n1-battery-regression.sql:186: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002211: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withdrawn (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:186: NOTICE:  PASS P8 the owner cannot edit a period: refused by never edited (accounting period 00000000-0000-4000-8000-000000002211: a period is never edited; it closes only through close_accountin)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:189: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002211: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withdrawn (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:189: NOTICE:  PASS P8b nor close one by UPDATE: refused by never edited (accounting period 00000000-0000-4000-8000-000000002211: a period is never edited; it closes only through close_accountin)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:192: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting_periods rows are never deleted: a snapshot and the freeze stand on them; a mistyped open period is withdrawn (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:192: NOTICE:  PASS P8c nor delete one: refused by never deleted (accounting_periods rows are never deleted: a snapshot and the freeze stand on them; a mistyped open period is withdrawn )
 refuses_at 
------------
 
(1 row)

INSERT 0 1
SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:205: NOTICE:  CAUGHT SQLSTATE=42501 message=close_accounting_period(): closing a period is irreversible and is a supervisor's act (app.user_id must name a tenant administrator or a platform administrator) (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:205: NOTICE:  PASS C1 an operator cannot close a period: refused by supervisor (close_accounting_period(): closing a period is irreversible and is a supervisor's act (app.user_id must name a tenant ad)
 refuses_at 
------------
 
(1 row)

              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b4
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:209: NOTICE:  CAUGHT SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002212 starts on 2026-02-01; the books are closed through nothing — periods close in order, the earlier first (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:209: NOTICE:  PASS C2 periods close in order: refused by close in order (accounting period 00000000-0000-4000-8000-000000002212 starts on 2026-02-01; the books are closed through nothing — peri)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:212: NOTICE:  CAUGHT SQLSTATE=22023 message=close_accounting_period(): an unbilled-revenue figure is reported with its basis, or neither is given (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:212: NOTICE:  PASS C3 an unbilled figure comes with its basis: refused by with its basis (close_accounting_period(): an unbilled-revenue figure is reported with its basis, or neither is given (D-2, v5.4.2-22))
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:215: NOTICE:  CAUGHT SQLSTATE=22023 message=close_accounting_period(): an unbilled-revenue figure is reported with its basis, or neither is given (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:215: NOTICE:  PASS C3b a blank basis is no basis: refused by with its basis (close_accounting_period(): an unbilled-revenue figure is reported with its basis, or neither is given (D-2, v5.4.2-22))
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:218: NOTICE:  CAUGHT SQLSTATE=P0002 message=Accounting period 00000000-0000-4000-8000-000000002219 not found
psql:/tmp/cx2/n1-battery-regression.sql:218: NOTICE:  PASS C4 another tenant's period is not found: refused by not found (Accounting period 00000000-0000-4000-8000-000000002219 not found)
 refuses_at 
------------
 
(1 row)

              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b2
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:222: NOTICE:  CAUGHT SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002219 ends on 2026-10-15, which has not ended everywhere yet; a period closes after its last day (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:222: NOTICE:  PASS C5 a period whose last day has not ended does not close: refused by has not ended (accounting period 00000000-0000-4000-8000-000000002219 ends on 2026-10-15, which has not ended everywhere yet; a period )
 refuses_at 
------------
 
(1 row)

RESET
SET
psql:/tmp/cx2/n1-battery-regression.sql:227: NOTICE:  CAUGHT SQLSTATE=42501 message=permission denied for function close_accounting_period
psql:/tmp/cx2/n1-battery-regression.sql:227: NOTICE:  PASS C6 the core cannot close: refused by permission denied (permission denied for function close_accounting_period)
 refuses_at 
------------
 
(1 row)

RESET
SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

INSERT 0 1
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b4
(1 row)

          set_config          
------------------------------
 2026-10-16 03:03:59.16852+00
(1 row)

RESET
psql:/tmp/cx2/n1-battery-regression.sql:241: NOTICE:  PASS C7 the close returns its instant: the period is closed at it, by the supervisor
 ok 
----
 
(1 row)

 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:243: NOTICE:  PASS C8 the head moves to the period's last day
psql:/tmp/cx2/n1-battery-regression.sql:249: NOTICE:  PASS C9 the snapshot: opening (before January 1) 80, January 1 + 100 - 60 - 50 + 5, closing 76, five entries, the unbilled figure and basis
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:253: NOTICE:  PASS C10 activity lines by ledger type sum to closing minus opening
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:259: NOTICE:  PASS C11 aging lines: the tenant's buckets on the last day, credit balances apart
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:265: NOTICE:  PASS C12 the aging lines are what receivables_aging_as_of() says at the snapshot's coordinate
 ok 
----
 
(1 row)

SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b4
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:270: NOTICE:  CAUGHT SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002211 (2026-01-01 to 2026-01-31) is already closed; a closed period never reopens (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:270: NOTICE:  PASS C13 a closed period never reopens, nor closes twice: refused by already closed (accounting period 00000000-0000-4000-8000-000000002211 (2026-01-01 to 2026-01-31) is already closed; a closed period nev)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:274: NOTICE:  CAUGHT SQLSTATE=42501 message=permission denied for table accounting_period_snapshots
psql:/tmp/cx2/n1-battery-regression.sql:274: NOTICE:  PASS C14 the application cannot write a snapshot: refused by permission denied (permission denied for table accounting_period_snapshots)
psql:/tmp/cx2/n1-battery-regression.sql:277: NOTICE:  CAUGHT SQLSTATE=42501 message=permission denied for table accounting_period_snapshot_lines
psql:/tmp/cx2/n1-battery-regression.sql:277: NOTICE:  PASS C14b nor edit a line: refused by permission denied (permission denied for table accounting_period_snapshot_lines)
 refuses_at 
------------
 
(1 row)

 refuses_at 
------------
 
(1 row)

RESET
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:281: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting_period_snapshots is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:281: NOTICE:  PASS C15 the owner cannot edit a snapshot: refused by written only by close_accounting_period() (accounting_period_snapshots is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2)
psql:/tmp/cx2/n1-battery-regression.sql:284: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting_period_snapshot_lines is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:284: NOTICE:  PASS C15b nor delete a line: refused by written only by close_accounting_period() (accounting_period_snapshot_lines is written only by close_accounting_period(), once, and never edited or deleted (D-2, v)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:288: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting_period_snapshot_lines is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:288: NOTICE:  PASS C15c nor write one: refused by written only by close_accounting_period() (accounting_period_snapshot_lines is written only by close_accounting_period(), once, and never edited or deleted (D-2, v)
 refuses_at 
------------
 
(1 row)

SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:297: NOTICE:  CAUGHT SQLSTATE=23514 message=account_ledger: dated 2026-01-15, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:297: NOTICE:  PASS F1 a ledger row dated in the closed period: refused by a closed period is frozen (account_ledger: dated 2026-01-15, on or before 2026-01-31, the end of the tenant's last closed accounting period — a clo)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:301: NOTICE:  CAUGHT SQLSTATE=23514 message=account_ledger: dated 2025-06-30, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:301: NOTICE:  PASS F1b and one dated before the first period, once it is closed: refused by a closed period is frozen (account_ledger: dated 2025-06-30, on or before 2026-01-31, the end of the tenant's last closed accounting period — a clo)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:304: NOTICE:  PASS F1c a row dated the day after posts
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:308: NOTICE:  CAUGHT SQLSTATE=23514 message=payments: dated 2026-01-30, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:308: NOTICE:  PASS F2 a payment dated in the closed period: refused by a closed period is frozen (payments: dated 2026-01-30, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed pe)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:311: NOTICE:  PASS F2b a payment dated after posts
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:314: NOTICE:  CAUGHT SQLSTATE=23514 message=payments: dated 2026-01-28, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:314: NOTICE:  PASS F2c a payment is not moved out of the closed period: refused by a closed period is frozen (payments: dated 2026-01-28, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed pe)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:317: NOTICE:  CAUGHT SQLSTATE=23514 message=payments: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:317: NOTICE:  PASS F2d nor into it: refused by a closed period is frozen (payments: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed pe)
 refuses_at 
------------
 
(1 row)

              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b9
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:322: NOTICE:  CAUGHT SQLSTATE=23514 message=payments: dated 2026-01-28, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:322: NOTICE:  PASS F2e a payment moved to another tenant leaves the closed books it was in: refused by a closed period is frozen (payments: dated 2026-01-28, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed pe)
 refuses_at 
------------
 
(1 row)

              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:327: NOTICE:  CAUGHT SQLSTATE=23514 message=customer_credits: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:327: NOTICE:  PASS F3 a customer credit issued in the closed period: refused by a closed period is frozen (customer_credits: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a c)
 refuses_at 
------------
 
(1 row)

 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:330: NOTICE:  PASS F3b and one issued after
RESET
psql:/tmp/cx2/n1-battery-regression.sql:335: NOTICE:  CAUGHT SQLSTATE=23514 message=account_ledger: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:335: NOTICE:  PASS F4 the owner is frozen out too: refused by a closed period is frozen (account_ledger: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a clo)
 refuses_at 
------------
 
(1 row)

SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b2
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:340: NOTICE:  PASS F5 another tenant's books are its own: T2 still posts in January
 admits 
--------
 
(1 row)

RESET
SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:350: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "account_ledger" violates check constraint "account_ledger_recovery_lineage_check"
psql:/tmp/cx2/n1-battery-regression.sql:350: NOTICE:  PASS R1 a recovery names its write-off, with a reason: refused by account_ledger_recovery_lineage_check (new row for relation "account_ledger" violates check constraint "account_ledger_recovery_lineage_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:354: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "account_ledger" violates check constraint "account_ledger_recovery_lineage_check"
psql:/tmp/cx2/n1-battery-regression.sql:354: NOTICE:  PASS R1b the reason is not blank: refused by account_ledger_recovery_lineage_check (new row for relation "account_ledger" violates check constraint "account_ledger_recovery_lineage_check")
 refuses_at 
------------
 
(1 row)

 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:358: NOTICE:  CAUGHT SQLSTATE=23503 message=a write-off recovery names a write_off entry of its own customer; 00000000-0000-4000-8000-0000000022e2 is not one (R-02, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:358: NOTICE:  PASS R2 it names a write_off, not a charge: refused by names a write_off entry (a write-off recovery names a write_off entry of its own customer; 00000000-0000-4000-8000-0000000022e2 is not one (R-02,)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:362: NOTICE:  CAUGHT SQLSTATE=23503 message=a write-off recovery names a write_off entry of its own customer; 00000000-0000-4000-8000-0000000022e4 is not one (R-02, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:362: NOTICE:  PASS R3 of its own customer: refused by names a write_off entry (a write-off recovery names a write_off entry of its own customer; 00000000-0000-4000-8000-0000000022e4 is not one (R-02,)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:366: NOTICE:  CAUGHT SQLSTATE=23514 message=a write-off recovery has the opposite sign of its write-off: -10.00 against -50.00 (R-02, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:366: NOTICE:  PASS R4 with the opposite sign: refused by opposite sign (a write-off recovery has the opposite sign of its write-off: -10.00 against -50.00 (R-02, v5.4.2-22))
psql:/tmp/cx2/n1-battery-regression.sql:369: NOTICE:  PASS R5 a recovery of 30 of the 50
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:373: NOTICE:  CAUGHT SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-0000000022e4: recoveries of 50.01 would exceed the 50.00 written off (R-02 cap, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:373: NOTICE:  PASS R6 recoveries never exceed the write-off: refused by R-02 cap (write-off 00000000-0000-4000-8000-0000000022e4: recoveries of 50.01 would exceed the 50.00 written off (R-02 cap, v5.4.2)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:376: NOTICE:  PASS R6b up to the whole of it
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:380: NOTICE:  CAUGHT SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-0000000022e4: recoveries of 50.01 would exceed the 50.00 written off (R-02 cap, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:380: NOTICE:  PASS R6c and not a cent more: refused by R-02 cap (write-off 00000000-0000-4000-8000-0000000022e4: recoveries of 50.01 would exceed the 50.00 written off (R-02 cap, v5.4.2)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:384: NOTICE:  CAUGHT SQLSTATE=23514 message=a adjustment names write-off 00000000-0000-4000-8000-0000000022e4: only a write_off_recovery names a write-off, so the cap counts it (R-02, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:384: NOTICE:  PASS R7 a row that names a write-off is its recovery: an adjustment cannot reinstate it outside the cap: refused by only a write_off_recovery names a write-off (a adjustment names write-off 00000000-0000-4000-8000-0000000022e4: only a write_off_recovery names a write-off, so the c)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:389: NOTICE:  CAUGHT SQLSTATE=23514 message=account_ledger 00000000-0000-4000-8000-0000000022ea: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:389: NOTICE:  PASS R8 a reversal chain never loops (two rows of one statement naming each other): refused by returns to itself (account_ledger 00000000-0000-4000-8000-0000000022ea: its reversal chain returns to itself; a reversal names an earlier e)
 refuses_at 
------------
 
(1 row)

RESET
SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:398: NOTICE:  CAUGHT SQLSTATE=22004 message=receivables_aging_as_of: tenant, date and recorded-at coordinate are all required; never default to today (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:398: NOTICE:  PASS W1 every coordinate is required: refused by all required (receivables_aging_as_of: tenant, date and recorded-at coordinate are all required; never default to today (v5.4.2-22))
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:401: NOTICE:  CAUGHT SQLSTATE=P0002 message=receivables_aging_as_of: tenant 00000000-0000-4000-8000-0000000022a2 has no aging bucket setting recorded at 2026-10-16 03:03:59.18409+00, or is not visible in this session (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:401: NOTICE:  PASS W1b another tenant is not visible: refused by not visible (receivables_aging_as_of: tenant 00000000-0000-4000-8000-0000000022a2 has no aging bucket setting recorded at 2026-10-16 )
 refuses_at 
------------
 
(1 row)

 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:404: NOTICE:  CAUGHT SQLSTATE=22023 message=receivables_aging_as_of: [0:1]={90,30} is not a list of bucket edges (one-based, 1 to 12 positive days, increasing) (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:404: NOTICE:  PASS W1d explicit edges are a valid list: refused by not a list of bucket edges (receivables_aging_as_of: [0:1]={90,30} is not a list of bucket edges (one-based, 1 to 12 positive days, increasing) (v5.)
psql:/tmp/cx2/n1-battery-regression.sql:407: NOTICE:  CAUGHT SQLSTATE=P0002 message=receivables_aging_as_of: tenant 00000000-0000-4000-8000-0000000022a1 has no aging bucket setting recorded at 2026-10-16 03:03:58.144556+00, or is not visible in this session (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:407: NOTICE:  PASS W1c before the setting's history there is no aging: refused by no aging bucket setting (receivables_aging_as_of: tenant 00000000-0000-4000-8000-0000000022a1 has no aging bucket setting recorded at 2026-10-16 )
 refuses_at 
------------
 
(1 row)

INSERT 0 1
INSERT 0 1
INSERT 0 2
RESET
          set_config           
-------------------------------
 2026-10-16 03:03:59.185515+00
(1 row)

UPDATE 1
SELECT 3
psql:/tmp/cx2/n1-battery-regression.sql:427: NOTICE:  PASS W2 the balance is aged newest first: C1's 21 is the February charge (49 days, 31-60)
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:430: NOTICE:  PASS W3 an entry is netted with the reversal that names it: C2 owes December's 80 (120 days) and the 5 late fee (59 days)
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:433: NOTICE:  PASS W4 the customer's status is on the row (D-3): C2 is final-billed
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:437: NOTICE:  PASS W4b at an instant before the change, C2 was active
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:439: NOTICE:  PASS W5 the last located entry gives the location
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:441: NOTICE:  PASS W6 a zero balance is omitted: C3 (written off 50, recovered 50)
 ok 
----
 
(1 row)

INSERT 0 1
INSERT 0 1
psql:/tmp/cx2/n1-battery-regression.sql:450: NOTICE:  PASS W7 a credit balance is one row with no bucket
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:455: NOTICE:  PASS W8 the recorded coordinate: a row recorded after it is not seen, then is
 ok 
----
 
(1 row)

 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:459: NOTICE:  PASS W9 the date coordinate: on February 15, C1 owes 41 of January 5 (41 days) and 50 of February 10 (5 days)
psql:/tmp/cx2/n1-battery-regression.sql:462: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:462: NOTICE:  PASS W10 bucket edges increase: refused by tenants_receivables_aging_bucket_days_check (new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:464: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:464: NOTICE:  PASS W10b are positive: refused by tenants_receivables_aging_bucket_days_check (new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:466: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:466: NOTICE:  PASS W10c are not empty: refused by tenants_receivables_aging_bucket_days_check (new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:468: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:468: NOTICE:  PASS W10d hold no NULL: refused by tenants_receivables_aging_bucket_days_check (new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:470: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:470: NOTICE:  PASS W10e are one-based (a [0:1] array hides a decreasing pair): refused by tenants_receivables_aging_bucket_days_check (new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check")
 refuses_at 
------------
 
(1 row)

SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b4
(1 row)

 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:476: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenant_configuration_history" violates check constraint "tenant_configuration_history_aging_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:476: NOTICE:  PASS W10f a recorded value is a valid list, a direct history row included: refused by tenant_configuration_history_aging_days_check (new row for relation "tenant_configuration_history" violates check constraint "tenant_configuration_history_aging_days_c)
psql:/tmp/cx2/n1-battery-regression.sql:480: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenant_configuration_history" violates check constraint "tenant_configuration_history_aging_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:480: NOTICE:  PASS W10g nor a decreasing one: refused by tenant_configuration_history_aging_days_check (new row for relation "tenant_configuration_history" violates check constraint "tenant_configuration_history_aging_days_c)
 refuses_at 
------------
 
(1 row)

RESET
UPDATE 1
psql:/tmp/cx2/n1-battery-regression.sql:486: NOTICE:  PASS W11 a change is recorded in the configuration history
 ok 
----
 
(1 row)

 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:493: NOTICE:  PASS W12 aging reads the edges as recorded: C2's 80 (120 days) and 5 (59 days) are both over 45
psql:/tmp/cx2/n1-battery-regression.sql:497: NOTICE:  PASS W12b explicit edges age by those edges, whatever is recorded
 ok 
----
 
(1 row)

INSERT 0 1
psql:/tmp/cx2/n1-battery-regression.sql:508: NOTICE:  PASS W13 a reversal is netted only within its customer: C2 still owes December's 80, C1's 10 credit is aged balance-forward
 ok 
----
 
(1 row)

INSERT 0 1
INSERT 0 5
psql:/tmp/cx2/n1-battery-regression.sql:525: NOTICE:  PASS W14 a chain nets into its original, and a reversal dated before its original stands alone until the original is in the window
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:534: NOTICE:  CAUGHT SQLSTATE=22000 message=receivables_aging_as_of: 2 ledger entries of tenant 00000000-0000-4000-8000-0000000022a1 reach no original (a reversal loop); aging would omit them (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:534: NOTICE:  PASS W16 should a loop ever be in the ledger (the loop guard disabled by the owner), aging raises rather than drop it: refused by reach no original (receivables_aging_as_of: 2 ledger entries of tenant 00000000-0000-4000-8000-0000000022a1 reach no original (a reversal l)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:537: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_write_off_threshold_days_check"
psql:/tmp/cx2/n1-battery-regression.sql:537: NOTICE:  PASS W15 the write-off threshold is a positive number of days, or unset: refused by tenants_write_off_threshold_days_check (new row for relation "tenants" violates check constraint "tenants_write_off_threshold_days_check")
 refuses_at 
------------
 
(1 row)

UPDATE 1
psql:/tmp/cx2/n1-battery-regression.sql:541: NOTICE:  PASS W15b born unset, and recorded when set
 ok 
----
 
(1 row)

INSERT 0 1
SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b1
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:552: NOTICE:  PASS G1 a default account (every key a wildcard)
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:555: NOTICE:  PASS G1b usage charges
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:558: NOTICE:  PASS G1c residential usage charges
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:561: NOTICE:  PASS G1d created_by and created_at are the database's, closed_* empty
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:565: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_charge_check"
psql:/tmp/cx2/n1-battery-regression.sql:565: NOTICE:  PASS G2 a code from its source's vocabulary: refused by gl_account_mappings_charge_check (new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_charge_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:569: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_charge_pair_check"
psql:/tmp/cx2/n1-battery-regression.sql:569: NOTICE:  PASS G2b a source with a code: refused by gl_account_mappings_charge_pair_check (new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_charge_pair_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:573: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_customer_class_check"
psql:/tmp/cx2/n1-battery-regression.sql:573: NOTICE:  PASS G2c a known customer class: refused by gl_account_mappings_customer_class_check (new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_customer_class_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:577: NOTICE:  CAUGHT SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_account_check"
psql:/tmp/cx2/n1-battery-regression.sql:577: NOTICE:  PASS G2d an account that is not blank: refused by gl_account_mappings_account_check (new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_account_check")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:581: NOTICE:  CAUGHT SQLSTATE=23P01 message=conflicting key value violates exclusion constraint "gl_account_mappings_no_overlap"
psql:/tmp/cx2/n1-battery-regression.sql:581: NOTICE:  PASS G3 one key, one mapping at a time (wildcards compare equal): refused by gl_account_mappings_no_overlap (conflicting key value violates exclusion constraint "gl_account_mappings_no_overlap")
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:585: NOTICE:  CAUGHT SQLSTATE=23514 message=gl_account_mappings: a mapping in force on or before 2026-01-31, the end of the last closed period, would change a closed period's export (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:585: NOTICE:  PASS G4 no mapping in force in a closed period: refused by closed period's export (gl_account_mappings: a mapping in force on or before 2026-01-31, the end of the last closed period, would change a close)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:588: NOTICE:  PASS G5 the most specific row wins: residential usage
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:591: NOTICE:  PASS G5b commercial usage takes the usage row
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:594: NOTICE:  PASS G5c a base charge takes the default
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:596: NOTICE:  PASS G5d before any mapping is in force: none (the export refuses the line)
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:599: NOTICE:  PASS G6 usage in Battery City (a key of the same size as residential usage)
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:604: NOTICE:  PASS G6b the stated precedence: the customer class outranks the territory
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:607: NOTICE:  PASS G6c a line with no territory matches only wildcards on it
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:610: NOTICE:  CAUGHT SQLSTATE=23001 message=gl_account_mappings 00000000-0000-4000-8000-000000002232 is never edited: a change is a close (effective_to, once) and a successor row (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:610: NOTICE:  PASS G7 a mapping is never edited: refused by never edited (gl_account_mappings 00000000-0000-4000-8000-000000002232 is never edited: a change is a close (effective_to, once) and a)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:613: NOTICE:  CAUGHT SQLSTATE=23514 message=gl_account_mappings 00000000-0000-4000-8000-000000002232: a close on 2026-01-31 would end the mapping inside a closed period (closed through 2026-01-31) (D-2, v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:613: NOTICE:  PASS G7b a close does not reach into a closed period: refused by inside a closed period (gl_account_mappings 00000000-0000-4000-8000-000000002232: a close on 2026-01-31 would end the mapping inside a closed pe)
 refuses_at 
------------
 
(1 row)

 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:615: NOTICE:  PASS G7c a close
psql:/tmp/cx2/n1-battery-regression.sql:618: NOTICE:  PASS G7d the close is stamped
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:621: NOTICE:  CAUGHT SQLSTATE=23001 message=gl_account_mappings 00000000-0000-4000-8000-000000002232 is never edited: a change is a close (effective_to, once) and a successor row (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:621: NOTICE:  PASS G7e and happens once: refused by never edited (gl_account_mappings 00000000-0000-4000-8000-000000002232 is never edited: a change is a close (effective_to, once) and a)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:624: NOTICE:  PASS G7f the successor carries the new account
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:629: NOTICE:  PASS G7g each date takes its own row
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:632: NOTICE:  CAUGHT SQLSTATE=42501 message=permission denied for table gl_account_mappings
psql:/tmp/cx2/n1-battery-regression.sql:632: NOTICE:  PASS G8 the application cannot delete a mapping: refused by permission denied (permission denied for table gl_account_mappings)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:635: NOTICE:  CAUGHT SQLSTATE=22004 message=gl_mapping_as_of: tenant, charge source and code, date and recorded-at coordinate are required; never default to today (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:635: NOTICE:  PASS G9 the lookup's coordinates are required: refused by never default to today (gl_mapping_as_of: tenant, charge source and code, date and recorded-at coordinate are required; never default to today ()
 refuses_at 
------------
 
(1 row)

              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b2
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:639: NOTICE:  PASS G10 another tenant sees none of it
 ok 
----
 
(1 row)

RESET
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:643: NOTICE:  CAUGHT SQLSTATE=23001 message=gl_account_mappings rows are never deleted: a past export must stay answerable (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:643: NOTICE:  PASS G8b nor can the owner: refused by never deleted (gl_account_mappings rows are never deleted: a past export must stay answerable (v5.4.2-22))
SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b4
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:652: NOTICE:  CAUGHT SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002214 starts on 2026-03-01; the books are closed through 2026-01-31 — periods close in order, the earlier first (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:652: NOTICE:  PASS C15d after a close, the next period is the next to close: not March before February: refused by close in order (accounting period 00000000-0000-4000-8000-000000002214 starts on 2026-03-01; the books are closed through 2026-01-31 — p)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:653: NOTICE:  PASS C16 February closes next
 admits 
--------
 
(1 row)

RESET
psql:/tmp/cx2/n1-battery-regression.sql:659: NOTICE:  PASS C17 February opens at January's closing balance, and the head moves on
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:662: NOTICE:  PASS C18 February's closing balance is the ledger's through February 28
 ok 
----
 
(1 row)

SET
              set_config              
--------------------------------------
 00000000-0000-4000-8000-0000000022b4
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:667: NOTICE:  CAUGHT SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002214: ledger rows dated on or before 2026-03-31 are recorded after the close's instant 2026-10-16 03:03:59.207103+00; a close counts everything it freezes (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:667: NOTICE:  PASS C19 a close refuses while a row it would freeze is recorded after its instant (W8's "later" row, March 10): refused by recorded after the close's instant (accounting period 00000000-0000-4000-8000-000000002214: ledger rows dated on or before 2026-03-31 are recorded after the)
 refuses_at 
------------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:670: NOTICE:  CAUGHT SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002212: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withdrawn (v5.4.2-22)
psql:/tmp/cx2/n1-battery-regression.sql:670: NOTICE:  PASS P9e a closed period is not withdrawn: refused by never edited (accounting period 00000000-0000-4000-8000-000000002212: a period is never edited; it closes only through close_accountin)
 refuses_at 
------------
 
(1 row)

RESET
 admits 
--------
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:676: NOTICE:  PASS I1 the -22 guards and the seal roles are as defined
psql:/tmp/cx2/n1-battery-regression.sql:679: NOTICE:  PASS I2 close_accounting_period() is a definer owned by tally_close, pinned
 ok 
----
 
(1 row)

 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:683: NOTICE:  PASS I3 the application executes the close; the core and PUBLIC do not
 ok 
----
 
(1 row)

psql:/tmp/cx2/n1-battery-regression.sql:687: NOTICE:  PASS I4 the new tables are under forced row security (their policies: I5)
psql:/tmp/cx2/n1-battery-regression.sql:689: NOTICE:  PASS I5 tenant isolation and the core's invariants hold
 admits 
--------
 
(1 row)

ROLLBACK
--- exit 0
=== n2-statement-regression.sql
BEGIN
SET
SET
DO
SET
psql:/tmp/cx2/n2-statement-regression.sql:69: NOTICE:  OBSERVED N2 contiguous periods in multi-row statement=3
psql:/tmp/cx2/n2-statement-regression.sql:69: NOTICE:  OBSERVED N2 recovery statement refused: 23514 write-off 9a30c1b5-9ad7-4c36-ac38-8070b49a8324: recoveries of 60.00 would exceed the 50.00 written off (R-02 cap, v5.4.2-22)
psql:/tmp/cx2/n2-statement-regression.sql:69: NOTICE:  OBSERVED N2 cap SQLSTATE=23514 surviving recovery count=0
psql:/tmp/cx2/n2-statement-regression.sql:69: NOTICE:  OBSERVED N2 CTE close at=2026-10-16 03:03:59.317413+00 snapshot closing=75.00 ledger=75.00
psql:/tmp/cx2/n2-statement-regression.sql:69: NOTICE:  OBSERVED N2 after-close write refused: 23514 account_ledger: dated 2020-01-07, on or before 2020-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
DO
RESET
ROLLBACK
--- exit 0
=== n3-gl-coordinate.sql
BEGIN
SET
SET
DO
SET
psql:/tmp/cx2/n3-gl-coordinate.sql:42: NOTICE:  OBSERVED N3 at=2026-10-16 03:03:59.39328+00 before=330fdb53-9253-490e-bf54-a4641acd2f39 after=330fdb53-9253-490e-bf54-a4641acd2f39 close stamp=2026-10-16 03:03:59.393838+00
DO
RESET
ROLLBACK
--- exit 0
=== n4-invariant-definition.sql
BEGIN
SET
SET
ALTER TABLE
ALTER TABLE
DO
RESET
psql:/tmp/cx2/n4-invariant-definition.sql:20: NOTICE:  OBSERVED N4 invariant refused: 0LP01 a v5.4.2-22 constraint is missing, changed or not validated:
  account_ledger account_ledger_recovery_lineage_check CHECK (((transaction_type <> 'write_off_recovery'::text) OR ((reverses_ledger_entry_id IS NOT NULL) AND COALESCE((reversal_reason ~ '[[:alnum:]]'::text), false))))
ROLLBACK
--- exit 0
=== n5-snapshot-edges.sql
BEGIN
SET
SET
DO
SET
psql:/tmp/cx2/n5-snapshot-edges.sql:57: NOTICE:  OBSERVED N5 before=[{"amount": 100.00, "balance": 100.00, "customer_id": "8b6d87c7-d1ed-4937-b670-5564fc51052d", "bucket_index": 0, "bucket_to_days": 30, "customer_number": "CX-1", "customer_status": "active", "bucket_from_days": 0, "last_location_id": null}] after=[{"amount": 100.00, "balance": 100.00, "customer_id": "8b6d87c7-d1ed-4937-b670-5564fc51052d", "bucket_index": 0, "bucket_to_days": 30, "customer_number": "CX-1", "customer_status": "active", "bucket_from_days": 0, "last_location_id": null}] changed=f
psql:/tmp/cx2/n5-snapshot-edges.sql:57: NOTICE:  OBSERVED N5 snapshot edges={30,60,90,120}; as-of edges={15,45}
psql:/tmp/cx2/n5-snapshot-edges.sql:57: NOTICE:  OBSERVED N5 manual backdate accepted; same-coordinate edges now={10,20}
psql:/tmp/cx2/n5-snapshot-edges.sql:57: NOTICE:  R2 explicit edges unchanged after manual history=t
psql:/tmp/cx2/n5-snapshot-edges.sql:57: NOTICE:  R2 three-argument result changed=t
DO
RESET
ROLLBACK
--- exit 0
=== n6-cycle-shapes.sql
BEGIN
SET
SET
DO
SET
psql:/tmp/cx2/n6-cycle-shapes.sql:51: NOTICE:  multi-row cycle SQLSTATE=23514 message=account_ledger 59af7a94-477a-492f-8b8b-b2341ad2f42a: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
psql:/tmp/cx2/n6-cycle-shapes.sql:51: NOTICE:  writable CTE cycle SQLSTATE=23514 message=account_ledger 0859e2c6-0f19-480f-8a23-ca215f085b6a: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
DO
RESET
ROLLBACK
--- exit 0
=== n7-copy-cycle.sql
BEGIN
SET
SET
INSERT 0 1
INSERT 0 1
SAVEPOINT
psql:/tmp/cx2/n7-copy-cycle.sql:17: ERROR:  account_ledger c0220002-0000-4000-8000-000000000003: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
CONTEXT:  PL/pgSQL function enforce_ledger_lineage_acyclic() line 12 at RAISE
ROLLBACK
 set_config |     set_config      
------------+---------------------
 00000      | COPY accepted cycle
(1 row)

DO
psql:/tmp/cx2/n7-copy-cycle.sql:30: NOTICE:  COPY cycle SQLSTATE=00000 message=COPY accepted cycle
ROLLBACK
--- exit 0
=== n8-aging-rls.sql
BEGIN
SET
SET
DO
INSERT 0 2
SET
psql:/tmp/cx2/n8-aging-rls.sql:47: NOTICE:  tenant own aging rows=1 sum=100.00
psql:/tmp/cx2/n8-aging-rls.sql:47: NOTICE:  tenant cross-tenant SQLSTATE=P0002 message=receivables_aging_as_of: tenant d8fa9b73-d3b0-4559-bd5a-58a3e48b705b is not visible in this session (v5.4.2-22)
psql:/tmp/cx2/n8-aging-rls.sql:47: NOTICE:  platform requested tenant one rows=1 sum=100.00
psql:/tmp/cx2/n8-aging-rls.sql:47: NOTICE:  platform requested tenant two rows=1 sum=200.00
DO
RESET
ROLLBACK
--- exit 0
=== s2-invariant-scope.sql
BEGIN
SET
SET
DO
psql:/tmp/cx2/s2-invariant-scope.sql:39: NOTICE:  S2 periods invariant accepted missing history known-key CHECK
DO
ROLLBACK
--- exit 0
```
