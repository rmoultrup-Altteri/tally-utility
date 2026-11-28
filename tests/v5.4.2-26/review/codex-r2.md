# Codex — v5.4.2-26, review round 2

**Verdict: not yet.** Source-only review. The principal round-1 integrity fixes are present, but plan items 9, 11 and 15 are only partly fixed. Address S1–S3 and measure the probes before freezing again.

**B items:** no new blocking application bypass independently established in this source-only round. This does not certify the patch: the remaining should-fix items undermine a stated execution guard and the evidence used to accept the patch.

## N1 — executed: freeze verification and scope

Checked the brief against its sidecar first, then all seven frozen inputs before inspecting their implementation. All matched:

| File | MD5 |
|---|---|
| review-brief-26-r2.md | 206906fbd83e9b51edadf959afc2bb05 |
| patch-26-frozen-r2.sql | af02fd6311471b8bef4822f7b6d124a0 |
| battery-26-frozen-r2.sql | 2ff3ca08f94321b433fcc658ee9ec66c |
| collections-26-frozen-r2.sh | 43e8fda4bd163d17bdea6763a60516a4 |
| mutations-26-frozen-r2.py | 2610f21cfaa2fd0814c8d3569e5ac23a |
| migration-26-frozen-r2.py | 607a7f540c80a24dc6cb76f4a6871152 |
| fill-manifest-26-frozen-r2.py | 0f10a4d77046059b4effdb9e049bc8eb |
| battery-21-for-26-frozen-r2.sql | 0b1fc800443eecee12e184eac9eab5d4 |

Read the r2 plan first after verification; then the r1 brief, my r1 review, frozen source/diffs, design, inventory E/F, relevant DECISION-LOG entries, GBM rulings and PATCH-LESSONS. No Opus or Fable round-2 review was read. No Docker, psql, database, CI, race, mutation runner or manifest generator was run. The author's reported apply/battery/race/migration/mutation/CI results remain **author-reported**, not reproduced here.

Only this report and `codex-r2-probes/` were written. All database outcomes below are **predicted**. The one executed behavioral check was a standalone Python evaluation of the classifier on literal strings; it neither imported nor invoked a runner.

Probe inventory (each starts as owner on a fresh clone with frozen r2 applied, and ends in ROLLBACK):

- [01-frozen-regressions.sql](codex-r2-probes/01-frozen-regressions.sql): frozen battery assertions with added SQLSTATE/message notices in caught-error helpers. This is an explicit reproduction probe, not a claim that I ran 249 checks.
- [02-order-timestamps.sql](codex-r2-probes/02-order-timestamps.sql): editable order creation bound, with an owner-created older decision fixture and application-role attack statements.
- [03-manifest-drift.sql](codex-r2-probes/03-manifest-drift.sql): isolated, undone changes to trigger mode, policy, nullability, column privileges and function volatility.
- [04-additional-boundaries.sql](codex-r2-probes/04-additional-boundaries.sql): broad notice over a blocked meter, execution under a broad block, off-ladder stage mapping, and two dependent writing statements in a CTE.
- [05-catalog-and-lock-protocol.sql](codex-r2-probes/05-catalog-and-lock-protocol.sql): installed functions, writer privileges, earlier invariants, UTC/local dates, and precise additional race schedules. **Catalog inspection and schedules only; not an executable concurrent reproduction.**

No COPY probe is supplied, and no COPY outcome is claimed. Owner fixture failures must be treated as setup failures, not guard confirmations. The intentional subtransaction undo in probe 03 prints its own SQLSTATE/message too.

## S1 — predicted: the order's execution lower bound remains caller-controlled

**Evidence:** frozen patch `enforce_disconnect_order`, lines 1021–1087, and `enforce_field_visit`, lines 1137–1145; mirrored `service_orders` definition at `sql/tu.sql:4484` and its update trigger at 8469. `created_at` has a default and NOT NULL, but no insert stamp or immutability fence. F4a freezes type/customer/location/meter/tenant/decision, not creation time. F2f trusts that mutable time, before acquiring the order's share lock.

A caller can supply `created_at` when creating an order and change it afterwards. With an older eligible execute decision, lowering the order's timestamp permits an arrival previously rejected as before the order. Raising it after an execution leaves a stored execution preceding the order's recorded creation. A concurrent creation-time edit is also outside the fields treated as immutable before the visit locks/re-reads the order; F2f is not repeated after that re-read.

**Probe:** 02 isolates this from the decision bound: its owner fixture stamps the decision one hour earlier, while every order edit and execution attempt runs as tally_app. It first offers an arrival before the order but after the decision, then lowers the order bound and repeats the same arrival, then moves creation past the accepted execution and prints both timestamps. This is a prediction of the writable-bound defect, not a measured concurrent attack. Run away from UTC midnight so the one-second-old arrival stays on the decision's day.

**Fix:** give disconnect orders a database-controlled, write-once recorded creation coordinate (or a separate immutable authorization/record coordinate if external source creation must remain caller-supplied). Validate the bound against the locked order. Specify the owner history-import exception deliberately. Do not globally change the established transaction-time convention to wall-clock timestamps as an incidental fix.

**Test weakness:** R9a puts the arrival before *both* creation times. M147 removes *both* lower comparisons. Thus their reported catch does not prove either comparison independently. Test an arrival between the two timestamps in each direction, and timestamp INSERT/UPDATE tampering.

**Late field sync:** an already-recorded order and execute decision can legitimately precede an arrival reported later. The lower bound is fair for that workflow. If the external tool uploads the order/decision for the first time after the physical act, the rule refuses it; that requires an explicit import/authorization contract, not arbitrary backdating. An otherwise valid delayed report can also be refused if its decision was superseded before upload: existing live-at-recording behavior, not a new F2f property. `now()` is transaction start, so a long-running ingestion transaction should be retried rather than treated as the physical clock.

## S2 — executed: item 15 still counts unrelated session-B failures as mutation catches

**Evidence:** frozen race `verdict()`, lines 174–190; frozen mutation classifier, lines 498–502. The classifier excludes only `session A itself failed` and `never seen waiting`. The race still labels an unexpected B error as FAIL for the named check, including when no wait was observed, sometimes calling the error “damage.” No successful readback or allowed SQLSTATE is required.

I evaluated the exact `fails`/`infra`/named-check predicates on these literal first lines:

| Literal output | Classifier result |
|---|---|
| `FAIL CR2 a late fee: expected B refused with '[A4]', got (3): ERROR: 57014: canceling statement due to statement timeout` | CAUGHT |
| `FAIL CR2 a late fee: no lock wait, and B was not refused with '[A4]' (damage: (3) ERROR: 42501: permission denied for table adhoc_charges)` | CAUGHT |
| `FAIL CR3 a supersession: expected B to pass, got: FATAL: connection to server was lost` | CAUGHT |
| `FAIL CR2: session A itself failed: connection lost` | MISSED |
| `FAIL CR2: session B was never seen waiting on a lock (outcome as expected; inconclusive)` | MISSED |

The last two are improvements. The first three are the original defect's remaining branches. This is **not** evidence that a particular reported mutation run actually encountered them.

**Fix:** separate infrastructure/inconclusive results from demonstrated invariant damage. Require each race mutation's concrete wrong success/readback or specific expected erroneous result, and self-test the classifier with literal timeout, connection loss, permission error, correct sequential outcome and genuine damage cases. A `damage:` prefix around arbitrary stderr is not that evidence.

## S3 — predicted: the manifest pins selected metadata, not the complete security/guard contract

**Evidence:** frozen patch lines 1339–1490 and frozen manifest generator's five catalog queries. The checker verifies trigger definitions/modes, listed validated constraints, listed valid unique indexes, relation ACLs and RLS enable/force flags, and selected function metadata/body hashes. It does not inspect policy definitions, column ACLs, column NOT NULL flags, or function volatility. The generator cannot fill properties its queries never collect.

**Probe:** 03 predicts that disabling the field guard is caught, but making the decisions policy allow-all, dropping `evidence_refs` NOT NULL, granting SELECT on a column, and changing the live-decision helper's volatility all pass **this checker**. Each edit is undone before the next. This is a drift-detection finding, not a claim that tally_app can perform this DDL today. Other invariant functions may catch some drift; this probe deliberately measures the collections check's own advertised coverage.

Nullability and policy changes matter: the guard code relies on non-null arrays for cardinality branches, and RLS flags alone say nothing about which tenants a policy exposes. Pin at least policy definitions and the load-bearing nullability, and distinguish table grants from effective/column grants. Either pin the remaining function attributes/dependencies required for correctness or state the narrower coverage. Existing shared helper bodies such as recompute/stamping are dependencies rather than automatically included “-26 functions.”

The generator's current list-marker substitutions each assert exactly one match, so I found no silent wrong-list overwrite in this frozen file. The trigger/constraint/index lists nevertheless depend on hand-maintained object-name selections; “every object” is stronger than the enumeration proves. The frozen generator and other frozen Python runners also retain their original `parents[2]` path calculation: running the relocated review copy directly is not equivalent to running the live script at its original path. Do not treat these review copies as turnkey execution commands.

## N2 — predicted except item 15's executed classifier check: disposition of plan items 1–15

“Fixed” here means the source addresses the finding, with database verification delegated to the linked probes. It does not mean independently executed.

| Plan item | Disposition | Evidence and remaining boundary |
|---|---|---|
| 1 — wrong customer's execute decision | Fixed | Visit explicitly compares decision.customer_id to order.customer_id before execution; probe 01 R1c. The visit FK remains tenant-only: the implementation uses the guard alternative, not the plan's suggested customer-bearing visit key. |
| 2 — broad/narrow decision conflict | Fixed in source; additional race verification needed | A10 reads latest decision per meter under the shared meter-free lock. Probe 01 R2b–g and probe 04 cover orders, notices and execution; probe 05 gives both concurrent orderings. |
| 3 — stale-snapshot cancellation | Fixed | F4f refuses status changes outside READ COMMITTED. Frozen CR8c is RR; SERIALIZABLE is implied by the predicate, not separately exercised by that race. Probe 05 records that missing schedule. |
| 4 — multi-row previous_stage | Fixed | Read latest stage-moving event under the bill lock; allocate sequence afterwards. Probe 01 R4 and probe 04's two-writing-statement CTE. |
| 5 — actor utility and approver | Fixed for these new links | Composite actor FKs and active same-tenant tenant_admin check. Probe 01 R5/H/F3. Shared impersonation remains a separate dependency. |
| 6 — recurring fees regress stage | Fixed | Ordered ladder preserves a later stage; off-ladder escalation resumes at the new step. Probe 01 R6/E2 and probe 04 mapping matrix. |
| 7 — penalty/bare line bypass | Fixed for the named representations | Both charge labels gated; fee/penalty lines require a same-customer gated charge; charge category cannot change. Probe 01 R7; probe 05 inventories writers. |
| 8 — surplus approvals | Fixed | A matched visit rejects a mismatch approval; evidence-bearing visit rejects no-evidence approval. Required links retain order/kind/value checks. Probe 01 R8/F3. |
| 9 — execution dating | Partly fixed | Comparisons exist, but order timestamp remains caller-controlled; S1/probe 02. |
| 10 — replica recompute | Fixed for parent-first enrollment load | ENABLE ALWAYS now covers recompute as well as fence; probe 01 R10. No claim of arbitrary-order history loading. |
| 11 — invariant function/calls | Partly fixed | Function and earlier invariant calls added, but coverage narrower than claimed; S3/probes 01 R11, 03 and 05. |
| 12 — void bill | Fixed for checked current-state paths | Both new decisions and live bill acts reject status void; probe 01 R12 uses void_invoice. Logs of existing acts remain exempt from live-act checks by design. This does not establish a void/act concurrent lock handshake. |
| 13 — blank captures | Fixed | Coalesced alphanumeric test on both captured fields; probe 01 R13/F2. |
| 14 — one log per bill | Fixed | Uniqueness is decision+invoice; customer binding remains. Probe 01 R14 and A5. Logging across a customer's bills follows the accepted plan, not a new service-location test. |
| 15 — mutation/race verdict | Partly fixed, executed source check | Session-A failure and correct outcome without observed wait excluded; session-B infrastructure failures still counted. S2. |

My own round-1 disposition: **B1 → fixed (1); B2 → fixed (4); B3 → fixed (3); S1 → fixed (8); S2 → fixed for new actors (5), impersonation still outside this patch; S3 → partly fixed (15); S4 → fixed for tested load (10).** N2's monthly-fee observation is addressed by (6); N3's evaluation/role/residual cautions remain bounded as below; N4's migration measurement limitations remain.

## N3 — predicted: requested concurrency, role and residual judgments

**Subject coverage and concurrency — probes 01, 04, 05.** The actual lock grain is tenant+act+customer+bill+location, not literally every subject at the location across different acts/customers/bills. That matches A10's query grain. Removing the meter closes the broad/narrow race: a blocked decision committed before the act obtains the mutex is visible to the subsequent READ COMMITTED query; if the act obtains it first, the later decision waits and does not retrospectively invalidate the completed act. An order with no meter checks all meter blocks. A notice with a meter uses its decision's meter; a broad notice checks every meter. Executions pass the order meter, or check all meters when neither cited subject nor order narrows it. A log of an already-performed act is intentionally outside A10. No newly discovered escape in this protocol; concurrent results remain unmeasured. This mutex does not serialize unrelated bill voids or deployment/ownership edits.

**Stage order — probes 01, 04, 05.** For two writers on one bill, the sequence assignment is after the bill lock and predecessor read. Sequence allocation before the wait would be wrong; this code does not do that. Gaps and interleaving other bills do not affect per-bill ordering. R6 means recorded order, not event-date order. The ladder is current → reminder → late fee → warning → scheduled → disconnected → collections. From payment_plan/resolved/written_off, an escalation moves to its own stage, as the plan explicitly settles. That is coherent with “collections resumed,” but does not prove a resolved debt became collectible: core evaluation remains responsible. Reconnected/payment_plan_broken do not move the stage. No new business-policy blocker inferred from that accepted choice.

**Mirrored writers and late-fee lines — probes 01 R7/R12 and 05.** Source grants identify tally_app and owner as line writers; tally_core is a reader, and the dedicated seal/close/void/dispute roles do not acquire line INSERT/UPDATE grants in the reviewed mirrored definitions. I found no mirrored SQL routine creating a fee/penalty invoice line. The application billing writer does, and already reads charges/bills. Consequently no specific earlier-owner permission regression is established. The new IF expression contains a subquery and should not be assumed to avoid permission checks just because charge_type is ordinary; re-evaluate permissions if a new role is ever allowed to write lines. Probe 05 prints the actual installed privilege matrix and routine inventory for confirmation.

The battery-21 dependency is acceptable for the integrated schema suite after all pending patches apply. Its revised A5 preserves the arithmetic case with a legitimately gated charge. It is no longer a standalone test of a database at patch -21; update invocation prerequisites accordingly. It does not justify claiming compatibility with a pre-26 database.

**Approver — probe 01 F3/H/R5.** Excluding platform administrators acting as themselves follows the newer Tally User ruling and is intentional. Other gates still call session_is_supervisor unchanged. No mirrored dependency on inserting these newly introduced approvals was found. A real impersonation record/Tally User provisioning implementation is not supplied by -26; setting app.user_id in a test is not proof that the eventual support workflow exists. The stale table COMMENT still says tenant_admin or platform admin/session_is_supervisor and should be corrected.

**Replica load — probes 01 R10 and 05.** ALWAYS recomputation fixes the concrete enrollment-after-customer case. It requires its customer and program vocabulary to exist, and executes an UPDATE rather than a deferred whole-load reconciliation. Arbitrary-order replica loading, concurrent enrollment projection correctness and the existing enrollment lifecycle are not established by R10. No new ordinary parent-first load regression identified. Never claim ENABLE ALWAYS alone makes a complete dump/restore protocol.

**Residuals — probes 01, 04, 05 for the relevant database behavior.** R1 is a meaningful integration dependency: a Texas-evening decision and the next morning can share a UTC day. The new local-day/weather contract is necessary and is not enforced by this schema. I accept that explicitly scoped residual for this patch, not as permission to deploy a stale-weather execution workflow. R6 accurately describes record-order stage semantics and the core's unsupported-by-facts terminal events; accepted scope, not a new blocker. R7 likewise explicitly defers enrollment termination controls, condition evaluation, window selection and credit-reporting storage. These are release dependencies for the relevant workflows, not reasons to pretend this patch independently enforces those protections. R2–R5 remain as previously assessed; no new blocker established from them alone.

## N4 — executed source assessment; database expectations predicted in probes: tests and acceptance limits

- R4c is an INSERT SELECT wrapped in a writable CTE with an outer count, not two interacting data-modifying statements. Probe 04 supplies the latter. Neither supplied probe claims COPY coverage.
- R9a/M147 combine two lower bounds (S1); R9b tests the future bound. Add independent lower-bound removals and timestamp tampering mutations.
- R2g tests a meter notice under a broad block, but no broad notice under a meter block or execution A10 case is added there; probe 04 supplies them. No new frozen race directly tests a broad blocked decision versus a meter eligible act. CR8c tests RR, not SERIALIZABLE.
- Removing only the collections invariant's apply-time call for behavioral mutations is reasonable: otherwise the body hash catches everything before behavior is exercised. R11a still checks it later, and the classifier requires the named first failure; an R11a-only catch should not satisfy a mutation named for R7, for example. Keep APPLY mutations separately. This technique does not fill S3's missing manifest dimensions or cure S2's race false positives.
- M124's coalesce mutation is faithful to accepting caller-approved_by and can be distinguished by F3c. M147 is weaker than its single-bound label; S2 shows how race mutations can pass for the wrong reason. I do not assert an actual historical false catch without runner output.
- Migration P1 counts objects, which is weaker than “changes nothing.” P4 changes both old fee columns together. P5c plants a late_fee line, not a penalty line. These are coverage limits visible in source, not independently reproduced migration failures. Strict second apply skips by table existence rather than re-verifying the existing installation.
- I agree with the plan's decision not to impose a creation-timestamp bound on every history-dated charge/log event. Their date/window contract differs from physical execution. That agreement does not relax the need for an authentic order timestamp in the new execution-specific guard. Do not describe a historical date inside a decision window as proof that the decision existed at the physical instant of every act.

Before the next freeze: close S1–S3; have the author run the probes, treating setup/infrastructure errors separately; add the isolated boundary cases to the maintained tests; then report fresh results against the newly frozen hashes. No reported suite count substitutes for those missing properties.
