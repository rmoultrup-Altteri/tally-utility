# Codex — v5.4.2-26, round 1

**Verdict: not yet.** Source-only review. No database, Docker, psql, CI, race harness or mutation runner was executed. Database outcomes below are **predicted**, not reproduced. The author's reported 202/11/P0–P7/127 results are not independent verification by this reviewer.

## N1 — executed: freeze and review scope

Checked the brief's checksum first, then all five frozen files, before reviewing source. All match:

| File | md5 |
|---|---|
| review-brief-26-r1.md | 43019dc4a3826fef1fac7b34d18b2e90 |
| patch-26-frozen-r1.sql | 5d4dd3e54b26131a76e6cfbe68b3566f |
| battery-26-frozen-r1.sql | 803c2aaf68585031259cbd824c4d3087 |
| collections-26-frozen-r1.sh | e8b3e9aad3c269b5f852c9743e8360b1 |
| mutations-26-frozen-r1.py | 1342f5e7a20ae1982991154909f2186c |
| migration-26-frozen-r1.py | ccfd94a00976a35c4976394e6d058459 |

Read the design, inventory E/F, relevant DECISION-LOG rulings, GBM rulings and PATCH-LESSONS index/relevant sections. No `opus-*.md` or `fable-*.md` was read. Only this review and `codex-r1-probes/` were written by me.

Probe files are independent owner-session scripts for fresh clones with frozen r1 applied. Each ends in ROLLBACK. Helpers and fixtures are extracted from the frozen battery; they do not execute its checks. Caught errors print SQLSTATE and message through RAISE NOTICE. The stdin COPY test prints its own verbose server error and deliberately does not inspect LAST_ERROR_SQLSTATE. Probe 06 is explicitly catalog inspection plus a two-session reproduction schedule, not an automated concurrent execution. None of these files has been run against PostgreSQL.

## B1 — predicted: an executed visit does not bind the decision to the order's customer

**Evidence:** patch lines 594–596 and `enforce_field_visit`, especially the `collections_act_check` call at 978–979. The visit's order and decision FKs bind tenant, but neither binds customer. `collections_act_check` compares the location and optional meter; it takes no customer parameter. Its comment says the citing row's composite FK handles customer, but that is not true for visits.

Create an order for C1 at L1. Record C1's execute decision as blocked by a medical hold. Transfer L1 to C2, then record C2's eligible execute decision for L1. The existing order remains C1's, while the executing visit can cite C2's decision, match the physical meter and location, and supply a photo. It therefore bypasses the blocked decision belonging to the order's actual customer. F2 expressly requires the execute decision for the order's customer.

**Probe:** [01-subject-and-approval.sql](codex-r1-probes/01-subject-and-approval.sql), `B1 execute C1 order with C2 decision`; read back both customer IDs. All steps, including the transfer, use tally_app after owner fixture setup. A setup refusal must be reported as such, not counted as evidence that the final guard works.

**Required correction:** compare the returned decision's customer with the locked order's customer, or make the customer part of both visit links. Keep the tenant keys. Add the transfer/old-order case, including a blocked decision for the old customer, to the battery and mutation coverage.

## B2 — predicted: multi-row dunning events freeze incorrect previous stages

**Evidence:** patch 762 reads `invoices.dunning_stage` in the BEFORE ROW trigger; 777 copies it into the event. The projection is updated only by the AFTER ROW trigger, 790–805. The row lock serializes different transactions, but does not make a queued AFTER trigger run before the next BEFORE ROW invocation in the same INSERT.

Insert a reminder and then a payment-plan event for one current bill in a single VALUES statement. Both BEFORE invocations are predicted to record `previous_stage = current`; the second should record `reminder_sent`. The final invoice projection can still look correct, so checking only the invoice misses the immutable history corruption. This is the exact class covered by PATCH-LESSONS `projection-checks-lag-in-one-statement`.

**Probe:** [02-stage-statements.sql](codex-r1-probes/02-stage-statements.sql). It prints both events and the projection, and separately exercises a dependent writable CTE. The CTE's actual outcome should be read from the output, not inferred from textual statement order.

**Required correction:** derive the predecessor from authoritative ordered events, or serialize the stage/history update in a way that is correct within a statement. Measure the proposed fix with VALUES, INSERT SELECT, writable CTE and multi-row COPY; do not fix this by trusting caller-supplied stages. The frozen E2 checks use separate statements; CR6 tests separate sessions and cannot cover this case.

## B3 — predicted: status updates are not pinned against stale execution snapshots

**Evidence:** patch 918 reads whether an execution exists. Only paths that call `collections_subject_lock` enforce READ COMMITTED. The order UPDATE branch never calls it or independently checks isolation. A visit takes `FOR SHARE` on the order (987), but does not update its row version.

Predicted schedule: A starts REPEATABLE READ and establishes a snapshot of an open order. B, at READ COMMITTED, records its executed visit and commits. A cancels the order. A's execution lookup sees its old snapshot; B's share lock did not create an updated order tuple that would force a serialization failure. The result can be an executed order marked cancelled, contrary to F4d. A READ COMMITTED-only execution path is insufficient when the competing status writer is unrestricted. SERIALIZABLE mixed with a READ COMMITTED execution writer is not a blanket cure either.

**Probe/evidence recipe:** [06-lock-and-isolation-inspection.sql](codex-r1-probes/06-lock-and-isolation-inspection.sql) prints the actual functions/triggers and tests the subject helper's isolation rejection. Its header gives the precise concurrent schedule for the author's harness. **Limitation:** this is not an executable two-session reproduction; the race remains unmeasured. Confirm it before accepting a specific fix, but the unrestricted stale read is visible in source.

**Required correction:** pin the relevant order status writes to READ COMMITTED too, or use a shared row-version protocol for execution and status transitions. Add old-snapshot cancellation tests, not just CR8/CR8b at their default isolation. Do not acquire the advisory lock after already taking the order update lock without revisiting lock order.

## S1 — predicted: surplus approval links escape order/kind checks

**Evidence:** patch 1017–1038 validates `mismatch_approval_id` only when the visit mismatches; 1039–1054 validates `no_evidence_approval_id` only when evidence is empty. A matched visit with evidence can name another order's no-evidence approval in *both* fields. The tenant-only FKs accept the links; the guard never checks them. Consequently the assertion that each approval belongs to the executing order and is used once is broader than the implementation.

This does not let an unmatched/no-photo visit proceed without its required approval: those branches still check. It does corrupt the audit linkage and allows an approval to be cited on unrelated executions.

**Probe:** 01, `S1 wrong-order/wrong-kind surplus approval`, followed by the order/kind readback. Validate every non-NULL approval reference, whether needed or surplus; alternatively refuse surplus references explicitly.

## S2 — predicted: new actor links and platform approval retain the pre-November model

**Evidence:** patch 267, 596 and 625 add single-column user FKs for decision creator, visit creator and approver. The new RLS policies admit platform administrators across tenants; `enforce_field_approval` uses the existing `session_is_supervisor`, which returns true for a platform administrator without an impersonation record.

**Probe:** [04-tenancy-and-catalog.sql](codex-r1-probes/04-tenancy-and-catalog.sql) prints the constraints and attempts a T2 platform user's approval/decision on T1 records. Expected: accepted, with the stored actor belonging to T2.

This fits the October F3 design but not the November 5 R-12 ruling and November 7 Tally User ruling. DECISION-LOG explicitly says that the shared impersonation machinery is not built and assigns the broad FK sweep later; this is a known cross-cutting dependency, not evidence that an ordinary operator can promote itself. Nevertheless, the patch cannot be described as fully implementing the newer rulings. Tie the new actor links to tenant and reconcile supervisor authorization with that shared work, or explicitly carry a tracked release dependency. Do not silently add these three links to the old untied backlog.

## S3 — executed: race mutation classification accepts infrastructure failures

**Evidence:** frozen race `verdict()` prints the same `FAIL CRn` prefix for a failed session A, no observed lock wait, an unrelated B failure, and actual invariant damage. Frozen mutation runner's final classification accepts the first line matching `FAIL <named check>[:\s]`, without validating the reason.

I evaluated only that regex against literal strings, without importing or running either runner. These all classified as caught:

- `FAIL CR1: session A itself failed: connection lost`
- `FAIL CR1: session B was never seen waiting on a lock`
- `FAIL CR2: expected B refused with [A4], got: statement timeout`

Thus the 127/127 result does not by itself prove every race mutation failed for its intended reason. I am **not** asserting that any particular historical run encountered these failures. Distinguish BROKEN and SEQUENTIAL from detected damage, and self-test the classifier with literal outputs as PATCH-LESSONS requires.

## S4 — predicted: history-load projection contract is incomplete

**Evidence:** the patch makes the customer projection fence ALWAYS, but does not change the ordinary `enrollment_recompute_dnd` trigger in `tu.sql:11879`. In replica mode, loading an active protective enrollment is predicted to leave the customer flag false because its recompute trigger does not run. A subsequent direct repair is barred by E4. The -24/-25 enrollment refusal triggers being ALWAYS does not make the recompute ALWAYS.

**Probe:** [03-repeat-fees-and-fences.sql](codex-r1-probes/03-repeat-fees-and-fences.sql), owner replica enrollment and expected-versus-actual flag. This is a history-loader limitation, not an application privilege bypass. Make the recomputation run on the supported load path, or specify and test a supported transactional reconciliation procedure. R5's no-TEMP assumption does not answer this case.

## N2 — predicted: recurring late fees fit; the stage moves backwards by design

**Probe:** 03 creates three decisions on different dates, three fees on the same bill and their three log events, with a payment-plan event between the first and second fees. Expected: all three fees are recorded; the second log moves `payment_plan` back to `late_fee_assessed`. Uniqueness is per decision, not per bill. The projection is the latest stage-moving event's mapping, not a monotone collections progression.

This satisfies the November 22 ability to penalize the same unpaid principal monthly. It does not decide whether the city permits recurrence, compute the per-line penalty base, or exclude earlier penalties: those remain the core/rule layer's responsibilities. Preserve that distinction in the application contract, and add this recurring-fee case so a later consumer does not mistake stage for highest stage reached. I found no executable mirrored SQL read of the dropped invoice fee columns; 04 also searches installed function bodies. Mentions of the stage value `late_fee_assessed` and old descriptive comments are not dependencies on the removed column.

## N3 — predicted: broader design, earlier patches and residual assessment

**Probes:** 03, 04, [05-gates-and-earlier-writer.sql](codex-r1-probes/05-gates-and-earlier-writer.sql), and 06 support the following bounded conclusions. They do not substitute for the author's complete regression suite.

- The vocabulary and outcome-shape guards express fail-toward-protection: a recorded unevaluable result cannot authorize an act. Probe 05 exercises no-decision, blocked, unevaluable, expired, other-bill, superseded and eligible late-fee cases, plus two first decisions in one INSERT. The shared act checker serves the other act paths; the frozen battery covers their individual mappings, but it is not a full cross-product of every act and refusal.
- `dispute`, `agency_pledge`, `aged_suspense` and `non_disconnectable_debt` are vocabulary, not evaluations. -26 does not call the -25 shelter readers or -24 pledge/suspense readers to compute the decision. That follows C3/R4, rather than proving the newer business rules are enforced in SQL. The core must use amount/line shelter, the silent-city default's three blocked acts (not notices), current pledge/suspense data, the gas-first partial-payment order, and the meter-error non-disconnectable amount. The cut-off settings remain onboarding requirements; an inability to evaluate stays blocking. AC-47's one recorded run instant belongs in this core contract as well.
- The consolidated-notice NULL branch is **not a finding**: design C3 says “when the bill names one,” and frozen C3d2 expressly allows another customer-owned location. Probe 01 preserves this positive case. The brief/header shorthand is narrower than the actual design.
- The -26 late-fee UPDATE branch relies on -23's fixed charge identity for type and effective date. Probe 03 checks those edits rather than treating the early return as a standalone bypass. The two retired enrollment checks remain separate from the DND recompute; 03 exercises the protective and retired paths.
- No new permission regression in an earlier owner path was established by source inspection. The new invoice/customer projection triggers inspect NEW/OLD without reading the new tables, and the charge UPDATE branch does not call the collections helper. Probe 04 inventories all six named roles, attempts direct projection writes, and runs installed zero-argument invariant functions, including the -24/-25 invariants omitted from -26's final block. Probe 05 exercises `void_invoice` through its definer. These probes are pending, so this is **not** a certification that all -23/-24/-25 properties still hold.
- Subject advisory locks precede the explicit invoice/order row locks in the principal decision/act paths. Multi-subject statements can acquire multiple locks and require the documented 40P01 retry. B3 is a separate snapshot problem. Location ownership and meter-deployment reads do not participate in that mutex; a catalog inspection alone cannot certify their concurrent freshness. No deployment-change race was executed or claimed here.
- **R1:** UTC dating is an explicit convention, not a newly discovered blocker. **R2:** deferred typed rule citations are accepted design scope; inputs/fingerprint still need meaningful core content. **R3:** reconnection/broken-plan no-move behavior is explicitly designed and covered by frozen E2. **R4:** evaluation remains core-owned; the patch is not an autonomous collections engine. **R5:** no demonstrated ordinary app depth bypass under revoked TEMP/CREATE; it is conditional, not a role-independent proof that only a particular trigger can write. S4 is an uncovered load path, and B2 is a statement-shape failure outside that assumption. None of R1–R5 excuses B1–B3.

## N4 — executed source review: migration and test coverage limits

The migration source names an offending row for each of its six stop conditions and wraps the changes in one transaction. Its marker is existence of `collections_decisions`, not a schema/version validation. P1 compares object counts; that is weaker than proving all definitions and contents unchanged. P4 sets both old fee columns together and does not isolate their individual predicates. The migration does not establish a go-live collections-rule configuration, consistently with the November 25 onboarding decision. No migration result was executed or independently affirmed here; this is a statement about the reviewed source and the author's reported results.

Missing regression cases that matter for this round: the B1 transfer/customer mismatch, B2 VALUES/CTE/COPY history, B3 old-snapshot cancellation, S1 surplus approvals, S2 foreign-tenant actor stamps/platform session, S4 replica recompute, and N2 second/third monthly fees. The frozen battery's H checks cover a subset of invariants and never exercise the earlier owner-role operations. Add the affected probes to the normal tests after the author measures their outcomes, then validate fixes and re-run the relevant invariants/earlier-writer batteries. Keep actual infrastructure failures separate from evidence that a mutation damaged the intended rule.
