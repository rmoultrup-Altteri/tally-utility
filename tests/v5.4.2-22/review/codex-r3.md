# Codex — v5.4.2-22 review round 3

**Verdict: not yet.** One predicted blocker: B1, the new live bucket read is not synchronized with the timestamp it claims to describe. The round-2 cap and lineage blockers are addressed in the source. No database experiment was executed by Codex.

## Evidence and execution boundary

**Executed — filesystem verification.** Checked the four hashes before reviewing implementation. All match the brief:

| Frozen file | MD5 |
|---|---|
| patch-22-frozen-r3.sql | ae35e901b3c0fa0b40804316965eee14 |
| battery-22-frozen-r3.sql | 36edebe0613f3ccf11f4f70d9988a0dc |
| close-22-frozen-r3.sh | de7a2f6902bb5b7b51a9bdd46b30fd25 |
| mutations-22-frozen-r3.py | 61104fe10b51e3a8e9ca320dfc6636db |

**Executed — source inspection; predicted — all database conclusions below.** Read my r2 report and the author's appended outcomes, the consolidated r2 dispositions, frozen r3 sources, relevant base-schema definitions, TU's `application/wave2-build-2026-10-15/source-inventory-wave2.md` and October 15 DECISION-LOG entries, and the original GBM D-2/D-3/R-02 rulings. The inventory is available in TU; r2's missing-inventory qualification no longer applies. No `opus-*.md` or `fable-*.md` was read. No Docker, psql, CI, race, or mutation runner was executed.

The author's r2 executions substantiate the old forward-reference and 10,001-ring defects. Their COPY output substantiates rejection, but its subsequent “accepted” summary was faulty. The brief's r3 pass counts remain author-reported, not independently reproduced here.

All database predictions have probe material in `codex-r3-probes/`. Run each SQL file separately as the owner/superuser on a fresh clone with frozen r3 strictly applied and the specified TEMP revocations already performed. Every file ends in ROLLBACK. Errors caught by the probes are reported with RAISE NOTICE, SQLSTATE and message. Setup failures are not successful guard tests. **B1's probe is explicitly instrumented; S1's probe is catalog/plan inspection, not a race.** Neither should be described as an executed unmodified concurrency reproduction.

## Blocking items

### B1 — The close can capture bucket edges newer than its recorded instant

**Predicted.** `patch-22-frozen-r3.sql:1121–1125`, `close_accounting_period()`. Requirement: DECISION-LOG's r2 ruling that the close uses the tenant's setting **at its instant**, and the corresponding snapshot promise. Probe: [b1-edge-clock-interleaving.sql](codex-r3-probes/b1-edge-clock-interleaving.sql).

The function assigns `v_at := clock_timestamp()` and then, in a separate READ COMMITTED query, reads `tenants.receivables_aging_bucket_days`. It holds the close-head and period locks, but no lock on the tenant setting; changing that setting does not take the close head. Thus this schedule is not excluded by the source:

1. Close locks head and period and assigns instant T, while the tenant holds `{30,60,90,120}`.
2. Another transaction updates the tenant's edges to `{10,20}` and commits after T.
3. The close's subsequent SELECT obtains a new snapshot and reads `{10,20}`.
4. It stores `recorded_at = T` together with the newer edges and uses them to bucket the snapshot.

The switch from history to the live tenant row fixes the manual-history substitution path, but leaves this separate clock/read gap. Stored-edge reproduction still works: this finding does **not** assert that the resulting stored snapshot becomes unreproducible or that ledger totals change. It asserts that the new explicit “tenant's setting at its instant” contract is not enforced. For example, a 26-day receivable switches from 0–30 to 21+ under the illustrated settings.

**Probe limitation:** the rollback-only probe inserts a scheduling hook immediately after the clock assignment in a transactional replacement of the close function. The hook changes the setting, then the otherwise unchanged close reads it. It asserts that the captured edges are newer than the captured instant. This is a deterministic simulation of the source-level interleaving, not proof from two sessions against the untouched function. It temporarily adds a helper grant to `tally_close`; it does not test the seal while instrumented. All instrumentation rolls back. The author should confirm the actual two-session schedule before reporting it as reproduced.

Synchronize the tenant setting with the instant, for example by obtaining an appropriate tenant-row lock before taking T and retaining it through capture, with the necessary least-privilege grant and lock-order review. Alternatively, explicitly revise the product contract to “the setting read during close” if that weaker temporal promise is intended. Merely moving the two statements closer together does not establish the current contract. Add a coordinated setting-update/close regression; C16b checks a preexisting setting and does not cover this gap.

## Should-fix items

### S1 — Qualify the lock-order and index-plan promises

**Predicted source assessment.** Patch lines 145–159, 558–595; [s1-lock-and-plan-scope.sql](codex-r3-probes/s1-lock-and-plan-scope.sql).

The ancestor write-offs are ordered within **one row-trigger invocation**. There is no statement-wide collection/sort of all affected write-offs and no ordering of locks retained by preceding statements. Two batches visiting independent write-offs in opposite row orders therefore are not covered by this ordering argument. The header documents withdrawal-plus-money versus close, but should also describe the scope of recovery lock ordering and require transaction retry handling rather than suggest global deadlock freedom. This is a liveness/documentation concern, not an identified committed over-cap result. No new race was executed; the probe provides the source checks and follow-up schedule, not a deadlock certification.

The link-only joins make id/reversal indexes usable and avoid the specific customer-predicate plan problem. They do not force an index scan under all sizes/statistics/planner settings. `idx_account_ledger_reverses` exists in the base; id is keyed. R10g's 300-deep/30-second test is useful performance coverage, not proof that “no step can still scan a ledger.” Retain the observed performance claim with its fixture and environment; narrow the universal wording. The probe supplies EXPLAIN queries without ANALYZE.

### S2 — Complete the focused regression coverage and correct test descriptions

**Predicted source assessment.** Probes n7, n9 and n10 below.

R9/R9b/R9c cover forward references and R10 covers transitive netting, released capacity and the floor. R11 covers bound exhaustion by a ring. Still add the nested-write-off case required by this brief, both its inner and outer caps; an A→B→A customer boundary; a valid chain exactly at the limit and an acyclic one just past it; and corrected COPY capture to the maintained suite.

R9b's two writable CTEs are not ordered by the final SELECT's textual order; its “adjustment first” label overstates that fixture's ordering guarantee. R9's ordered VALUES is the direct forward-order regression. R10f tests excluding a foreign-customer row; n9 extends it to descendants returning to the first customer.

CR12 adds a real withdrawal/close wait and CR11 a transitive-cap wait. CR3 is still sleep-orchestrated, so the race header's “every race leg” observed-blocking claim is too broad. There is still no explicit SERIALIZABLE case, multiple-write-off lock schedule, setting-update/close case, or withdrawal/append schedule in these files.

The mutation label regex now requires a literal label followed by colon/whitespace, fixing the r2 suffix defect. M53 is caught by the trigger-definition invariant at apply, so its result establishes structural detection, not behavioral execution of R9. M48's closed-period attempt can be caught by the surviving closed-stamp CHECK; that proves the act remains guarded, not that the altered trigger predicate is itself tested. M63's runtime/performance attribution is environment-sensitive. No additional concrete wrong-reason mutation success is established by this source review; 63/63 is the author's report.

## Notes

### N1 — Round-2 dispositions

**Predicted.** Functional coverage: n1, n6–n10.

| r2 item/disposition | r3 assessment |
|---|---|
| Codex B1 / consolidated #1 | AFTER INSERT sees statement siblings; direct-target type, recovery customer and sign checks move together. Forward-reference path addressed. |
| Consolidated #2–3 | Net includes all same-customer descendants, not only typed/direct recoveries. Reversing an erroneous recovery releases capacity. Both upper and lower limits checked. |
| Codex B2 / #4 | Bound exhaustion now raises. A 10,001 ring cannot silently escape the walk; R11 uses the cheaper 1,001 ring. |
| #5 | Manual history no longer chooses close edges; exact-instant concurrency qualification is B1. |
| #6 | Withdrawal requires app.user_id; operator eligibility matches the recorded decision. |
| Codex S1 / #7 | Table comment and C12 now use stored edges and the four-argument function. |
| Codex S2 / #8 | History known-key CHECK, not-self CHECK and reversal FK pinned; invariant comment explicitly excludes unnamed keys/FKs. |
| Codex S3 / #9–10 | Major missing cases added and exact label matching repaired; S2 records remaining coverage limits. |
| #11–13 | Withdrawal/close deadlock disclosed; withdrawn message fixed; closed_by grant refusal and seal comment updated. |

The lineage trigger sorts before the recovery trigger by name for the same row event. This is not a claim that *every* row's lineage check executes before *any* row's cap check. The downward cap walk uses UNION to deduplicate, so its termination does not depend on such a statement-wide ordering claim.

### N2 — Cap shapes and the 1,000-entry bound

**Predicted.** Probes n1 R1–R11, n6, n7, n9, n10.

The upward walk follows id alone, stops propagating on a customer/tenant boundary, and selects matching write-off ancestors. The downward walk marks nonmatching children, excludes their amounts and does not expand through them. These preserve the same connected, same-customer component as customer-constrained joins. A later row returning to customer A through customer B is not reunited with A's earlier tree; aging also treats that return as a new root.

For a write-off nested under another's recovery, the inserted descendants must satisfy both the inner write-off's capacity and the outer write-off's capacity. n9 supplies a forward-listed nested write-off, valid later recovery, separate inner/outer overflow attempts, and the A→B→A boundary. Its expected total aging is 981, including the separate customer's 500 and the returning root's 500.

The cap sums descendants, excluding the write-off itself, between zero and the negation of that write-off's amount. Thus the entire component retains between the original negative write-off and zero. The READ COMMITTED pin and advisory lock remain inside every matching ancestor iteration; moving validation AFTER loses no direct recovery requirement found in the previous BEFORE rule. Statement-final netting intentionally permits offsetting sibling rows whose final net is valid.

The limit admits a chain of 1,000 total entries including its root and rejects adding the 1,001st (n10). It fails closed for longer chains and loops. Nothing in the supplied inventory requires an unbounded number of corrections; no specific legitimate product operation needing more than 1,000 entries was identified. The bound is nevertheless a new explicit admission limit, not evidence that every conceivable import will fit it.

### N3 — Freeze, periods, head, snapshot and GL paths

**Predicted.** Probes n1 H/P/C/F/G, n2, n3, n5.

The source places the freeze on ledger INSERT and payment/credit INSERT or date/tenant UPDATE; ledger immutability covers changes to an already-recorded ledger row. Tenant moves inspect both heads. There is no owner exemption in these guards. Period creation/withdrawal serialize the active chain; overlap exclusion ignores withdrawn rows. Close locks head then period, checks open status, UTC-12 completion and next-period ordering. Withdrawal stamps the named user and does not delete history.

No additional concrete ordinary-role route to a born-closed/reopened/edited/deleted period, backward head, direct snapshot write, or mapping change inside frozen dates was identified. This is bounded source review, not an exhaustive concurrency proof. The battery probe includes negative cases for these paths, while n2 extends statement shape coverage.

Opening balance uses dates before period_start; activity is inclusive through period_end; closing is opening plus activity. Activity lines group ledger types, aging lines sum bucket amounts and count distinct customers. Future-recorded dated rows are refused before close can freeze them uncounted. The explicit-edge reproduction contract survives subsequent settings/history changes (n5). Unbilled revenue remains a supplied estimate with a basis, not a ledger row. B1 concerns only correspondence between live bucket capture and the stamped instant.

GL mapping changes remain a stamped one-time effective-end closure plus successor; precedence uses 8/4/2/1. Explicit date and recorded coordinates separate effective coverage from when a closure became known. G2's unmapped-export refusal is correctly left to the core, since this patch supplies configuration rather than a GL posting subsystem.

### N4 — Seal and invariants

**Predicted.** Probes n1 I/C/H, n4, n10.

The changed close grants match the changed data path: tenant id/bucket column SELECT replaces history-table SELECT and history-lookup EXECUTE. The invoker aging helper, validator, supervisor check and RLS helpers remain reachable. No new membership, code-creation or ledger-write grant is introduced for tally_close. The existing -20 role restrictions, ownership identity checks, exact explicit privilege comparison, default-privilege checks and seal guard definitions remain represented. The app closed_by UPDATE prohibition is now included.

This is a least-authority seal, not literally minimum column visibility throughout: table-wide SELECT on account_ledger/customer_state_events exposes columns beyond those this close selects. Some other table-wide privileges are also broader than the fields used. No surplus write capability from the r3 grant change was found. A B1 row-lock fix will need to revisit both grants and the exact allowlist.

The periods invariant now accurately scopes itself to its enumerated triggers/constraints and head coverage. It checks exact definitions and enabled/validated state, not function bodies or every PK/FK. n10 independently drops each newly pinned constraint inside an exception subtransaction and adds the closed_by grant, expecting 0LP01. n4 exercises replacement with a vacuous CHECK. These are rollback-local drift tests, not application-user DDL exploits.

### N5 — Aging, RLS, requirements and residuals

**Predicted.** Probes n1 W, n5, n8, n9; B1 for the outstanding temporal contract.

Aging filters the ledger by tenant/date/recorded coordinate, nets same-customer connected trees, allocates remaining positive balance newest-first, reports credit balances separately and omits zero balances. Status comes from state-event history at the recorded coordinate. It carries customer identity/status for D-3 without pretending that occupancy tables have been built. The three-argument history lookup and explicit-edge overload both validate required inputs; invoker rights and visible-head checks preserve the RLS boundary. n8 checks ordinary-tenant isolation and explicitly selected platform-admin tenant results.

P/S/G/W and D-2/D-3 are substantially implemented: periods are freeze boundaries; arbitrary date reporting retains the tenant/date index; the snapshot is computed; GL codes are tenant configuration; aging includes status; W3 records the threshold and guards recoveries. R-02's general rules remain deliberately staged to -23; the write-off-specific net cap now follows the October 15 decision. B1 leaves the newly strengthened bucket-at-instant requirement incomplete.

R1–R2 stage other money-event/status binding to -23; they are not a claim that -22 freezes every mutable money-source field. R3 stages per-bill allocation. R4 specifies transaction-time status; R5 discloses last-located-ledger-entry approximation. R6 duplicates vocabulary maintenance; R7 defers place-kind validation. R8 defers general reversal rules but now supplies a fail-closed lineage limit and write-off tree cap. R9 makes pre-history settings unavailable. R10 admits that manual/backfill history changes three-argument historical aging; stored-edge snapshot reproduction is a separate contract. None of these residuals independently blocks the scoped patch; none excuses B1's live-row clock gap.

## Probe index

All are **predicted / not executed** by Codex.

| File | Purpose |
|---|---|
| b1-edge-clock-interleaving.sql | Explicitly instrumented scheduling simulation; not an unmodified race |
| n1-battery.sql | Frozen r3 battery with full caught-error notices added |
| n2-statement-regression.sql | Multi-row periods/recovery cap, writable-CTE posting then close, subsequent freeze |
| n3-gl-coordinate.sql | Same-transaction recorded-coordinate GL regression |
| n4-invariant-definition.sql | Vacuous recovery constraint drift |
| n5-snapshot-edges.sql | Stored edges versus later live/history changes |
| n6-cycle-shapes.sql | VALUES and writable-CTE loops |
| n7-copy-cycle.sql | COPY capture self-test (22P02), then cycle-specific 23514; does not trust :ERROR |
| n8-aging-rls.sql | Tenant isolation and explicit platform-admin selection |
| n9-nested-trees.sql | Nested write-offs, both caps, cross-customer return path |
| n10-bound-and-invariants.sql | Valid 1,000-entry chain, invalid 1,001st; new constraint/grant checks |
| s1-lock-and-plan-scope.sql | Catalog ordering/index inspection and non-ANALYZE EXPLAIN; no race |

The COPY probe captures LAST_ERROR_SQLSTATE/LAST_ERROR_MESSAGE immediately and unconditionally after each COPY. The deliberate invalid integer must produce 22P02. The loop must then produce its own 23514 with the lineage message; stale control output cannot pass. As with every supplied probe, this capture design itself still needs the author's execution before claiming success.

---

## Author's execution of the probes (2026-10-16)

Each probe was run as the owner on its own fresh clone of `tally` with frozen r3 (md5 `ae35e901…`) strictly applied and TEMP revoked, with a 300 s statement timeout. No setup failures.

- **n1** (battery with notices): 149 PASS, no FAIL.
- **b1** (instrumented simulation, as Codex states, not a two-session race): `recorded_at` precedes the update, and the captured edges are `{10,20}` against prior `{30,60,90,120}`. The window is real in the source. A plain two-session schedule cannot hit it reliably, because the read does not block on an uncommitted update; the window is the time between `clock_timestamp()` and the SELECT.
- **n7**: the probe's own control failed. After a failed COPY, psql left `LAST_ERROR_SQLSTATE` at `00000`, so the self-test raised and the cycle leg never ran. The same capture defect explains r2 n7. Run directly, the COPY cycle is refused: `23514 … its reversal chain returns to itself`.
- Every other probe printed what Codex predicted:

```
== n10-bound-and-invariants
NOTICE:  1000 entries including root admitted
NOTICE:  bound SQLSTATE=23514 message=account_ledger 4402e276-fc92-4a48-8ccb-da1dc1e85463: its reversal chain does not reach an original within 1000 entries (too long, or a loop); a reversal names an earlier entry (R-02,
NOTICE:  constraint tenant_configuration_history_key_known_check SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
NOTICE:  constraint account_ledger_reversal_not_self_check SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
NOTICE:  constraint account_ledger_reverses_ledger_entry_fkey SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
NOTICE:  closed_by SQLSTATE=0LP01 message=the close's tables are writable outside close_accounting_period() (closed_through or status) (v5.4.2-22)
== n2-statement-regression
NOTICE:  OBSERVED N2 contiguous periods in multi-row statement=3
NOTICE:  OBSERVED N2 recovery statement refused: 23514 write-off 61d9db64-1b09-45d0-bc0f-6ec8297f59c1: the rows netted against it would come to 60.00, outside 0 to the 50.00 written off (R-02 cap, v5.4.2-22)
NOTICE:  OBSERVED N2 cap SQLSTATE=23514 surviving recovery count=0
NOTICE:  OBSERVED N2 CTE close at=2026-10-16 16:09:10.331198+00 snapshot closing=75.00 ledger=75.00
NOTICE:  OBSERVED N2 after-close write refused: 23514 account_ledger: dated 2020-01-07, on or before 2020-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into
== n3-gl-coordinate
NOTICE:  OBSERVED N3 at=2026-10-16 16:09:10.5978+00 before=0ab4a5cc-ad29-4677-81fe-8e7db2370027 after=0ab4a5cc-ad29-4677-81fe-8e7db2370027 close stamp=2026-10-16 16:09:10.598357+00
== n4-invariant-definition
NOTICE:  OBSERVED N4 invariant refused: 0LP01 a v5.4.2-22 constraint is missing, changed or not validated:
== n5-snapshot-edges
NOTICE:  OBSERVED N5 before=[{"amount": 100.00, "balance": 100.00, "customer_id": "cc69d1c4-6c1f-40df-931f-1acdaa695ee0", "bucket_index": 0, "bucket_to_days": 30, "customer_number": "CX-1", "customer_status": "active", "
NOTICE:  OBSERVED N5 snapshot edges={30,60,90,120}; as-of edges={15,45}
NOTICE:  OBSERVED N5 manual backdate accepted; same-coordinate edges now={10,20}
NOTICE:  R2 explicit edges unchanged after manual history=t
NOTICE:  R2 three-argument result changed=t
== n6-cycle-shapes
NOTICE:  multi-row cycle SQLSTATE=23514 message=account_ledger 74f44502-e836-48b7-b9dd-f24ff484c8ad: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
NOTICE:  writable CTE cycle SQLSTATE=23514 message=account_ledger 225618e1-a88e-4dcc-b2e7-f59399d23476: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
== n8-aging-rls
NOTICE:  tenant own aging rows=1 sum=100.00
NOTICE:  tenant cross-tenant SQLSTATE=P0002 message=receivables_aging_as_of: tenant 92d62239-eaff-4352-8f4a-de87e5bd420a is not visible in this session (v5.4.2-22)
NOTICE:  platform requested tenant one rows=1 sum=100.00
NOTICE:  platform requested tenant two rows=1 sum=200.00
== n9-nested-trees
NOTICE:  nested valid tree admitted; expected outer net=80 inner net=30
NOTICE:  inner overflow SQLSTATE=23514 message=write-off e71a611d-61d2-4285-bedb-16df0439f61c: the rows netted against it would come to 31.00, outside 0 to the 30.00 written off (R-02 cap, v5.4.2-22)
NOTICE:  outer overflow SQLSTATE=23514 message=write-off 3ec2fb07-446c-47fa-b1ad-41dcfea81219: the rows netted against it would come to 101.00, outside 0 to the 100.00 written off (R-02 cap, v5.4.2-22)
NOTICE:  cross-customer boundary respected; total aging=981.00
== s1-lock-and-plan-scope
NOTICE:  SOURCE: per-row ordered ancestor query=t; transaction advisory lock=t
NOTICE:  SOURCE: recovery trigger definition=CREATE TRIGGER enforce_write_off_recovery AFTER INSERT ON public.account_ledger FOR EACH ROW WHEN ((new.reverses_ledger_entry_id IS NOT NULL)) EXECUTE FUNCTION enforce_write_o
NOTICE:  SOURCE: reversal-link index=CREATE INDEX idx_account_ledger_reverses ON public.account_ledger USING btree (reverses_ledger_entry_id) WHERE (reverses_ledger_entry_id IS NOT NULL)
 Index Scan using idx_account_ledger_reverses on account_ledger
   Index Cond: (reverses_ledger_entry_id = 'c0330000-0000-4000-8000-000000000001'::uuid)
 Index Scan using account_ledger_id_tenant_id_key on account_ledger
   Index Cond: (id = 'c0330000-0000-4000-8000-000000000001'::uuid)
```
