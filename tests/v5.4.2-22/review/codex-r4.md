# Codex — v5.4.2-22, review round 4

**Verdict: not yet.** One predicted blocker, B1: an admitted owner history timestamp can make the new recorded-order retry permanent. The r3 date-prefix and aging-edge blockers are addressed in the source. No database experiment was executed by Codex.

## Scope and evidence

**Executed — filesystem checks.** Read the brief and checked these four MD5s before reviewing implementation. All match:

| Frozen file | MD5 |
|---|---|
| patch-22-frozen-r4.sql | 5228060d7d0479cd2d60636dee9a7256 |
| battery-22-frozen-r4.sql | e01f02aa2349dabea4890784ec102128 |
| close-22-frozen-r4.sh | 8e49101d4cf5919fcc42b81db81daefb |
| mutations-22-frozen-r4.py | 4349c1e288c082b7ead19eebcfed3924 |

**Executed — source review.** Read `codex-r3.md`, including the author's appended outputs, `review-findings-22-r3.md`, the r3–r4 diff, frozen sources, relevant base-schema definitions, TU's source inventory and October 15 DECISION-LOG entries, and GBM's D-2/D-3/R-02 rulings. No `opus-*.md` or `fable-*.md` was read. No Docker, psql, CI, race, mutation runner, or database connection was run. The brief's strict-apply, 154-check, CR1–CR15 and 68/68 results are **author-reported**, not independently reproduced.

**Predicted — every database conclusion below.** Probe files are in `codex-r4-probes/`. Run each separately as the owner/superuser on a fresh clone with frozen r4 strictly applied and TEMP revoked from PUBLIC, tally_app and tally_core. Each ends in ROLLBACK. Caught errors print their SQLSTATE and message. Some probes deliberately assume the current defect remains: their successful completion confirms the defect, not readiness. Source/catalog inspection and single-session probes do not establish concurrency or performance results.

## Blocking items

### B1 — A retained future timestamp can make “retry it” permanent

**Predicted.** Patch lines 654–668, `enforce_write_off_recovery()`; base `sql/tu.sql:37336` and `:37423`, `stamp_log_created_at()` and its ledger trigger. Probe: [b1-future-recorded-poison.sql](codex-r4-probes/b1-future-recorded-poison.sql).

The owner-history exception preserves a superuser's supplied `created_at`. R4 checks that no existing row in the write-off tree is recorded later than the new row, but does not limit an admitted timestamp to a finite time already reached. Concrete path with all guards enabled:

1. Owner inserts a write-off of 100, recorded normally.
2. Owner inserts a valid recovery of 20 with `created_at = 'infinity'`. Its date follows the write-off. Its net is within the cap, and no existing timestamp is greater than infinity, so the source admits it.
3. An ordinary operator inserts another recovery of 1. There is 80 of unused capacity, but its database-stamped finite transaction start is less than infinity. The trigger raises **40001, “retry it.”**
4. Every fresh ordinary transaction still has a finite start. Retrying cannot resolve the refusal. Supplying infinity as tally_app also cannot resolve it: the base stamp replaces that input with `now()`.

A far-future finite timestamp produces the same outage until that time. This is a liveness defect, **not a demonstrated over-cap commit or an ordinary-role timestamp-spoofing exploit**. It matters here because preserving owner timestamps for history loads is an explicit supported path, and the brief specifically requires examining that path and indefinite retry. No disabled trigger, role alteration, or schema tampering is needed. The existing immutable ledger makes an ordinary correction of the timestamp unavailable.

The probe tests the admitted infinity row, three finite owner timestamps through year 9000, and an ordinary-role attempt. These are rollback-local attempts, **not separate transaction retries**; the permanent-retry conclusion follows from infinity exceeding every finite transaction start. The author should not report them as a two-session reproduction.

Reject nonfinite/future recorded coordinates on relevant write-off-tree admissions, including a root write-off, while retaining legitimate past history. Check existing imported rows as part of introducing that rule. Alternatively, provide a specified nonretry recovery path; merely returning 40001 and instructing clients to retry is insufficient. Add a regression that asserts the poison row is refused before ordinary work can be stranded.

## Should-fix items

### S1 — A valid historical batch is refused solely because its siblings have different recorded times

**Predicted.** Same recorded-order query, patch lines 657–667. Probe: [s1-history-batch.sql](codex-r4-probes/s1-history-batch.sql).

With a write-off recorded February 1, load a recovery of 50 recorded February 2 and its partial bounce of -20 recorded February 3 in one INSERT. Their effective dates are January 2 and January 3. Every date/recorded prefix is within [0,100]. Nevertheless, the recovery's AFTER trigger sees the later-recorded bounce among the statement's siblings and raises 40001. Repeating the same import is futile. The identical rows are admitted as two chronological INSERT statements.

The guard's “already in its tree” includes not only prior committed writes but all current statement siblings. This conservatism keeps the temporal cap safe, but narrows the supported owner history-load shape. Document chronological statement partitioning and use a diagnostic that distinguishes an immutable import timestamp from a stale ordinary transaction, or validate all recorded prefixes for an atomic import. Do not fix this by simply ignoring statement siblings: that would require proving the remaining recorded prefixes are safe.

This is nonblocking separately because the chronological-statement workaround preserves the historical data. Ordinary application rows in one transaction share their database timestamp and do not encounter this particular heterogeneous-timestamp case.

### S2 — Finish promoting regression coverage and narrow test/plan descriptions

**Predicted source assessment.** Probes n1, n7, n9–n13, B1 and S1.

The maintained suite now covers the date defect and a real older-writer retry, but not B1 or S1. Nested write-offs, A→B→A customer boundaries and the exact 1,000-entry limit remain review probes rather than maintained battery checks. The author's r3 execution of those probes is useful evidence; it does not make them recurring r4 regressions. R9b still says “the adjustment first,” although the textual order of the two writable CTEs does not guarantee their execution order.

CR13/CR14 add both directions of the edge/close handshake. CR15's old-versus-young ordering uses sleeps, not a readiness barrier, and its refusal check matches “retry it,” not the SQLSTATE. It can fail under scheduling delays even when the implementation is correct. The race header's “every race leg” observed-blocking statement still overstates CR3 and explicitly nonblocking CR15. Use barriers for transaction-start ordering and assert 40001 separately from the message.

The new planner settings are function-local planner controls, not exact plan enforcement. They affect all statements planned in the trigger's scope, including the tree timestamp lookup and date-window aggregation; they do not prove those operations are cheap for arbitrarily wide trees. R11 appropriately limits the measured evidence. Keep that qualification in the internal comments that still promise every step uses a particular lookup. n11 offers catalog inspection and representative EXPLAINs, without ANALYZE or a runtime claim.

## Notes and answers to the brief

### N1 — R3 dispositions and the temporal cap

**Predicted.** Probes n1 (R9–R12e), n6, n9, n10, n12 and n13; B1/S1 qualify recorded-time admission.

| R3 finding | R4 source assessment |
|---|---|
| Date-prefix cap and pre-parent dates | Addressed: cumulative net at each effective date, plus nondecreasing parent/child dates. R12–R12d exercise the reported paths. |
| Author's older-transaction recorded-time counterexample | Addressed for ordinary finite transaction timestamps by the 40001 comparison; B1 is the separate retained-owner-time liveness defect. |
| Codex bucket-at-instant gap | Addressed by the close-head SHARE lock on changed tenant edges; see N2. |
| Upward final join/per-step plan regressions | Upward walk carries type/customer and selects write-offs directly. Both walk functions have the three settings. Measurements remain author-reported. |
| Cross-write-off deadlock | Header now explicitly limits ordering to one row and requires transaction retries. |
| Missing shape/bound tests | Author executed r3 probes successfully; carried forward here, but still not maintained battery tests. |
| Mutation of upward step | M56 targets the new recursive step; M68 targets the recovery function's settings. |

For accepted ordinary writes, the recorded-order rule makes each recorded-time prefix correspond to a previously checked tree state; the date-window sum checks every effective-date prefix of that state. Equal timestamps belong to one recorded-time group. AFTER triggers inspect statement-final rows, so same-timestamp offsetting siblings are judged together. Nondecreasing dates prevent the date filter from removing a same-customer ancestor while retaining its descendant under a write-off.

Nested write-offs are checked against every same-customer write-off ancestor. A customer boundary ends the component in both walks and aging; a later return to the first customer is a separate root. The downward UNION deduplicates rows rather than relying on all rows' lineage triggers having already fired. The lineage bound fails closed on loops and chains longer than 1,000 entries. Direct recoveries still require the correct type, tenant, customer, sign and named parent. No additional committed upper-cap or below-zero bypass was identified in these shapes.

A bounced recovery and a correction of its bounce are admitted when dated in order; n12 checks the ledger/aging result at 36 date/recorded coordinate pairs. This is finite fixture coverage, not an exhaustive proof for every possible tree. SERIALIZABLE admission refusals have a separate probe, n13; no SERIALIZABLE race was executed.

### N2 — Edge timing, snapshots and locks

**Predicted.** Probes n1 (C/W), n2, n5, n11 and n12. Concurrency assessment is source reasoning; CR13/CR14 executions are author-reported.

The new BEFORE UPDATE guard takes the same head FOR SHARE that close takes FOR UPDATE. An in-flight edge update therefore finishes before close acquires its head and takes its instant; a later updater waits. Close reads the live row under READ COMMITTED after that instant. The former independent-writer gap is closed without granting tally_close tenant UPDATE privileges. No-op edge updates need no handshake because they do not change the value.

For the isolated edge-update and close operations, the tenant-row lock acquired by UPDATE has no opposing tenant-row lock in the close function, so this change supplies no new two-operation lock cycle. This is not a global deadlock-freedom claim for transactions that combine arbitrary additional writes. Existing withdrawal-plus-post and multiple-write-off lock cycles remain documented retry cases. Finite ordinary timestamp retries can also starve under continual competing activity; the source supplies no fairness bound. B1 is stronger: it persists even after competing writers stop.

Opening balance sums dates before the period; activity includes both endpoints; closing is their sum. Activity lines group transaction types, and aging lines sum amounts and count distinct customers. The close rejects future-recorded ledger rows it would otherwise freeze uncounted. Its unbilled estimate requires a basis and is stored in the snapshot, not posted to the ledger. Stored edges reproduce snapshot aging after later settings or history edits. R10 correctly distinguishes that contract from three-argument historical aging, whose history timestamps can precede a waiting setting change's commit.

### N3 — Freeze, period lifecycle, GL mapping and requirements

**Predicted.** Probes n1 (H/P/C/F/G/W), n2, n3, n5 and n13.

P/S/G/W and the scoped D-2/D-3/R-02 requirements are represented: periods are freeze boundaries; the date-range index is retained; close computes the snapshot; GL mappings are dated tenant configuration; aging carries customer identity/status and the last-located-entry approximation; the write-off threshold setting is stored. G2's unmapped-export refusal remains the core's responsibility, as the inventory explicitly says. B1 qualifies operational readiness of W3 rather than identifying an absent table or column.

The freeze applies at ledger INSERT and payment/credit INSERT or date/tenant UPDATE, with both tenants checked on a move. Ledger immutability protects existing recorded money. Period creation/withdrawal serialize the active chain; the exclusion constraint prevents active overlaps, while withdrawal frees the latest open period's dates. Creation is open-only, withdrawal requires a user, and close checks supervisor, next-period order and completion at UTC-12. Head and snapshot writes are role-gated. No additional ordinary DML route to reopening, direct closing, deleting, born-closed periods, backward heads or changed snapshots was identified.

GL values cannot be edited in place. The permitted one-time effective-end closure is stamped, and a successor carries changed values. Effective dates respect the closed-through boundary; lookup uses both effective and recorded coordinates with 8/4/2/1 precedence. n3 specifically checks the same-transaction recorded coordinate.

### N4 — Seal, grants and invariants

**Predicted.** Probes n1 (I/H/C), n4, n10 and n11.

The close retains the -20 seal pattern: NOLOGIN/no membership or elevated role attributes, pinned SECURITY DEFINER ownership/search path, no code creation, exact explicit privilege comparison, RLS, default-privilege checks and protected write paths. R4 adds no close-role grant. The edge guard uses the application's existing head-lock privilege. The earlier replacement of history access with tenant id/edge SELECT matches the close's current data path.

The grants are constrained but not literally the smallest possible column-read set: account_ledger and customer_state_events still have table-wide SELECT. No new surplus write capability was identified. The new edge trigger is omitted from the explicit trigger-function REVOKE loop; it remains an invoker trigger function, not an ordinary callable data-writing API. This is consistency cleanup, not an identified seal bypass.

The periods invariant includes the exact new edge-trigger definition and ALWAYS state. It pins the enumerated trigger/constraint definitions and head coverage, not function bodies, planner settings, or every PK/FK. n11 tests disabling the edge trigger; n4/n10 test constraint/grant drift. A changed body or removed planner setting is not established as caught by this invariant. R11's performance qualification must not be mistaken for an invariant over executable plans.

### N5 — Aging/RLS and residuals R1–R11

**Predicted.** Probes n1 (W), n5, n8–n12; B1/S1 for recorded-time caveats.

Aging filters explicit tenant/date/recorded coordinates, nets connected same-customer trees, allocates positive open amounts newest-first, reports credit balances separately, omits zero balances and reads status history at the recorded coordinate. Invoker rights and visible-head validation retain the RLS boundary. The explicit-edge overload validates the supplied array; the three-argument form fails when no history setting exists. Platform-admin probes request a tenant explicitly.

R1/R2 defer other money-event/lifecycle work to -23; R3 defers per-bill allocation. R4's recorded-time status and R5's last-located-ledger approximation are declared scope choices. R6 duplicates mapping vocabulary and R7 defers place-kind validation. R8 stages general reversal rules while documenting this patch's write-off cap/date order/lineage limit. R9 disallows unknowable pre-setting history. R10 documents history mutability and waiting-setting timestamp semantics without weakening stored-edge reproduction. R11 states measured workloads rather than universal performance. None independently adds a blocker; none documents or resolves B1's permanent recovery refusal.

### N6 — Mutation interpretation and COPY capture

**Predicted source assessment.** n1/n7/n11 provide behavioral or catalog probes; the mutation runner was read, not executed.

M64–M66 target the new date-order, prefix-sum and recorded-order predicates. M67 removes the edge SHARE lock and names CR13. M68 removes the recovery function's planner settings and names the time-bounded R10g workload; it does not independently test removing only the lineage function's settings. M53 remains an apply-time trigger-definition detection, not an execution of its altered timing. M48 can still refuse withdrawal via the closed-stamp CHECK, with the changed diagnostic failing the named battery assertion; “caught” does not mean an invalid withdrawal committed. M63/M68 performance catches depend on the workload, statistics and timeout. The exact-label matcher retains the r3 fix. No additional concrete wrong-reason catch is established here.

The prior n7 capture was invalid, as the author's appended output shows. The replacement uses **server-side COPY FROM PROGRAM with fixed printf input**, catches errors inside PL/pgSQL, and prints the actual SQLSTATE/message. A successful integer COPY and deliberate invalid-integer 22P02 must both pass before the cycle COPY is attempted. The cycle must then produce its own 23514 lineage error and leave no partial rows. It never reads psql LAST_ERROR_SQLSTATE. This tests the server COPY path, not psql's STDIN error-variable behavior; its own capture remains predicted until the author executes it.

## Probe index

All database probes are **predicted / not executed by Codex**. All changes are rollback-local.

| File | Purpose |
|---|---|
| b1-future-recorded-poison.sql | Admitted infinity timestamp, finite and ordinary-role 40001 refusals |
| s1-history-batch.sql | Valid historical batch rejected; chronological statements admitted |
| n1-battery.sql | Frozen r4 battery, with full caught-error notices added |
| n2-statement-regression.sql | Multi-row cap/period shapes, writable CTE then close and freeze |
| n3-gl-coordinate.sql | Same-transaction GL recorded coordinate |
| n4-invariant-definition.sql | Vacuous constraint drift |
| n5-snapshot-edges.sql | Stored-edge reproduction versus live/history changes |
| n6-cycle-shapes.sql | VALUES and writable-CTE cycles |
| n7-copy-cycle.sql | COPY transport/capture controls, then cycle rejection |
| n8-aging-rls.sql | Ordinary-tenant and platform-admin explicit tenant isolation |
| n9-nested-trees.sql | Inner/outer caps, A→B→A boundary |
| n10-bound-and-invariants.sql | 1,000 admitted, 1,001 refused; constraint/grant drift |
| n11-settings-and-edge-invariant.sql | Catalog settings/grants, edge-trigger drift, representative EXPLAINs |
| n12-date-recorded-grid.sql | Bounce/correction and 36 coordinate intersections |
| n13-serializable-admission.sql | SERIALIZABLE refusal for period creation, close and recovery |

---

## Author's execution of the probes (2026-10-16)

Each probe was run as the owner on its own fresh clone of `tally` with frozen r4 (md5 `5228060d…`) strictly applied and TEMP revoked, with a 300 s statement timeout. There were no setup failures, and every probe printed what Codex predicted.

- **B1 reproduced:** after an owner recovery recorded at `infinity`, every later posting under the write-off is refused with 40001: a finite owner time, 2200, 9000, and an ordinary writer (whose `infinity` is restamped). These are single-session, rollback-local attempts, as Codex states.
- **S1 reproduced:** the mixed-instant batch is refused with 40001, and the same rows in two statements are admitted.
- **n1:** 154 PASS.
- **n7:** the corrected capture self-test passes (22P02), and the COPY cycle is refused with 23514.

```
== b1-future-recorded-poison
Owner recovery with created_at=infinity admitted, net=20 of 100
finite timestamp 2026-10-16 17:09:39.851423+00 SQLSTATE=40001 message=write-off 9e1044b0-a3bd-49fb-a04e-8fe430cadf81: da5d3528-7a62-4a0b-8d00-0a4b0916b217 is recorded at 2026-10-16 17:09:39.851423+00, before 2aee38bc-f08
finite timestamp 2200-01-01 00:00:00+00 SQLSTATE=40001 message=write-off 9e1044b0-a3bd-49fb-a04e-8fe430cadf81: 6d397197-0818-4510-96b8-cd0880ae444a is recorded at 2200-01-01 00:00:00+00, before 2aee38bc-f08a-49f8-908c-ee
finite timestamp 9000-01-01 00:00:00+00 SQLSTATE=40001 message=write-off 9e1044b0-a3bd-49fb-a04e-8fe430cadf81: 172d7628-9a9a-4f0e-bfd9-45208f48d9cc is recorded at 9000-01-01 00:00:00+00, before 2aee38bc-f08a-49f8-908c-ee
ordinary writer, even supplying infinity: SQLSTATE=40001 message=write-off 9e1044b0-a3bd-49fb-a04e-8fe430cadf81: 935ba7a8-c870-4508-8c19-a8eb482d0f5c is recorded at 2026-10-16 17:09:39.843613+00, before 2aee38bc-f08a-49f
== s1-history-batch
valid multi-instant batch SQLSTATE=40001 message=write-off 1de19d83-0ba9-417f-9bcb-42d8af3713e1: cb58bf59-6914-4d7f-baba-a8a6472a2d99 is recorded at 2020-02-02 00:00:00+00, before d0d89acd-596a-4e66-a711-4a267c6364a2 (re
Same historical rows admitted as two statements: all date/recorded prefixes net 0, 50 or 30
== n2-statement-regression
OBSERVED N2 contiguous periods in multi-row statement=3
OBSERVED N2 recovery statement refused: 23514 write-off c77b8a5c-07d6-4a55-98bd-c1ad12b515d5: on 2020-01-03 the rows netted against it would come to 60.00, outside 0 to the 50.00 written off (R-02 cap, v5.4.2-22)
OBSERVED N2 cap SQLSTATE=23514 surviving recovery count=0
OBSERVED N2 CTE close at=2026-10-16 17:09:43.441544+00 snapshot closing=75.00 ledger=75.00
OBSERVED N2 after-close write refused: 23514 account_ledger: dated 2020-01-07, on or before 2020-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open 
== n3-gl-coordinate
OBSERVED N3 at=2026-10-16 17:09:43.683591+00 before=693c66d3-7e49-472e-8de4-2f20a2afa8f4 after=693c66d3-7e49-472e-8de4-2f20a2afa8f4 close stamp=2026-10-16 17:09:43.684094+00
== n4-invariant-definition
OBSERVED N4 invariant refused: 0LP01 a v5.4.2-22 constraint is missing, changed or not validated:
== n5-snapshot-edges
OBSERVED N5 before=[{"amount": 100.00, "balance": 100.00, "customer_id": "d84cc749-487e-47f2-acd4-47b696576672", "bucket_index": 0, "bucket_to_days": 30, "customer_number": "CX-1", "customer_status": "active", "bucket_fr
OBSERVED N5 snapshot edges={30,60,90,120}; as-of edges={15,45}
OBSERVED N5 manual backdate accepted; same-coordinate edges now={10,20}
R2 explicit edges unchanged after manual history=t
R2 three-argument result changed=t
== n6-cycle-shapes
multi-row cycle SQLSTATE=23514 message=account_ledger ad9a752f-4b17-4a71-b6ba-d00891d4b86c: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
writable CTE cycle SQLSTATE=23514 message=account_ledger 6ec5b9b4-d4e8-4d59-9e02-4405c868dede: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
== n7-copy-cycle
COPY capture control SQLSTATE=22P02 message=invalid input syntax for type integer: "not-an-integer"
COPY transport and error capture controls passed
COPY cycle SQLSTATE=23514 message=account_ledger c0440000-0000-4000-8000-000000000003: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
== n8-aging-rls
tenant own aging rows=1 sum=100.00
tenant cross-tenant SQLSTATE=P0002 message=receivables_aging_as_of: tenant caefc292-ba71-49a9-b383-0c327d3dc691 is not visible in this session (v5.4.2-22)
platform requested tenant one rows=1 sum=100.00
platform requested tenant two rows=1 sum=200.00
== n9-nested-trees
nested valid tree admitted; expected outer net=80 inner net=30
inner overflow SQLSTATE=23514 message=write-off b2c6930a-4f02-42cf-ae43-f8cadf8389b1: on 2020-01-01 the rows netted against it would come to 31.00, outside 0 to the 30.00 written off (R-02 cap, v5.4.2-22)
outer overflow SQLSTATE=23514 message=write-off 8ee55d5d-2583-4ddf-8367-a1c47cc13659: on 2020-01-01 the rows netted against it would come to 101.00, outside 0 to the 100.00 written off (R-02 cap, v5.4.2-22)
cross-customer boundary respected; total aging=981.00
== n10-bound-and-invariants
1000 entries including root admitted
bound SQLSTATE=23514 message=account_ledger 5799d5ef-d234-4897-bca1-d00d0f0111de: its reversal chain does not reach an original within 1000 entries (too long, or a loop); a reversal names an earlier entry (R-02, v5.4.2-2
constraint tenant_configuration_history_key_known_check SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
constraint account_ledger_reversal_not_self_check SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
constraint account_ledger_reverses_ledger_entry_fkey SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
closed_by SQLSTATE=0LP01 message=the close's tables are writable outside close_accounting_period() (closed_through or status) (v5.4.2-22)
== n11-settings-and-edge-invariant
enforce_write_off_recovery() function settings: {"search_path=public, pg_temp",enable_seqscan=off,enable_hashjoin=off,enable_mergejoin=off}
enforce_ledger_lineage_acyclic() function settings: {"search_path=public, pg_temp",enable_seqscan=off,enable_hashjoin=off,enable_mergejoin=off}
Edge guard body: CREATE OR REPLACE FUNCTION public.enforce_aging_edges_close_order()
Close role explicit privileges: {"column public.accounting_close_heads.closed_through UPDATE","column public.accounting_close_heads.updated_at UPDATE","column public.accounting_periods.closed_at UPDATE","column public.ac
disabled edge guard SQLSTATE=0LP01 message=a v5.4.2-22 guard is missing, changed, or not ENABLE ALWAYS:
== n12-date-recorded-grid
36 date/recorded coordinates: cap in [0,100], aging reconciles; correction of correction accepted
== n13-serializable-admission
SERIALIZABLE admission SQLSTATE=25000 message=an accounting period is created at READ COMMITTED (this transaction is serializable): the no-gap check must see the latest period committed while it waited (v5.4.2-22)
SERIALIZABLE admission SQLSTATE=25000 message=close_accounting_period() runs at READ COMMITTED (this transaction is serializable): the close must read what the writers it waited for committed (v5.4.2-22)
SERIALIZABLE admission SQLSTATE=25000 message=a row under write-off 4124b43d-5668-4ba7-a795-390dff3f64e6 is posted at READ COMMITTED (this transaction is serializable): the cap must see every row committed while it waite
```
