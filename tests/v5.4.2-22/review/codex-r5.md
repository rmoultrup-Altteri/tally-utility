# Codex — v5.4.2-22, review round 5

**Verdict: ready.** Source-review verdict; database behavior remains **predicted**, awaiting the author's probe runs. No blocking item identified for new admissions under frozen r5. The r4 B1 poison-timestamp path is closed. The lock documentation and recurring regression coverage still merit the nonblocking changes below.

## Evidence and limits

**Executed — filesystem verification.** Checked all four hashes before reviewing implementation; all matched:

| Frozen file | MD5 |
|---|---|
| patch-22-frozen-r5.sql | 7e914bdacf1d2b19c3e6fc34b325d17e |
| battery-22-frozen-r5.sql | a5369adf6c44f61932ba79a84bdd0aa7 |
| close-22-frozen-r5.sh | 59554ed29cf52aa87bbda0d7886a0b77 |
| mutations-22-frozen-r5.py | 8513d1d2168232a0ba477891cbc3b691 |

**Executed — source inspection.** Read the brief, my r4 report including the author's appended outputs, the r4 findings/dispositions, r4–r5 diff, frozen implementation and relevant test source, base timestamp stamping, TU's inventory and October 15 drafting decisions, and GBM's D-2/D-3/R-02 rulings. No other reviewer's report was read. No Docker, psql, CI, race, mutation runner or database connection was executed. Only this report and the r5 probe directory were written.

The author's r4 probe results corroborate the prior findings, including B1, the mixed-instant import refusal, and the corrected COPY capture. They are **author-executed r4 evidence**, not my execution and not r5 results. The brief's r5 strict-apply, 157 checks, CR1–CR15 and 72/72 mutation results remain author-reported.

**Predicted — all database conclusions below.** Corresponding SQL files are in [codex-r5-probes](codex-r5-probes/). Run each independently as owner/superuser on a fresh clone with frozen r5 strictly applied, with TEMP revoked from PUBLIC, tally_app and tally_core. Each ends in ROLLBACK. Caught errors print SQLSTATE and message. The two-session lock probe has explicit manual coordination instructions and no data writes. These files are proposed experiments, not executed tests.

## Blocking items

None identified. This is not a claim of exhaustive concurrency verification or of clean existing production data; see N1's pre-existing-data limitation.

## Should-fix items

### S1 — The listed lock cycles are not exhaustive

**Predicted.** Patch lock-order paragraph, lines 175–204; freeze's head FOR SHARE and close's head FOR UPDATE. Probe: [s1-head-upgrade.sql](codex-r5-probes/s1-head-upgrade.sql).

Two transactions can each post an ordinary ledger row for the same tenant, thereby holding compatible SHARE locks on its head, and then both call the close before committing. Each requests an UPDATE lock incompatible with the other's retained SHARE lock. This is a head-lock upgrade deadlock, requiring neither a withdrawal, an edge update nor two write-offs. Thus the answer to “are the stated deadlocks the only ones?” is **no**.

The probe reproduces those exact head lock modes in two owner sessions, with a prompt barrier after both SHARE acquisitions. It is deliberately a lock-protocol experiment, not a full ledger/close integration run. It needs an existing head in the cloned base and raises a setup error if there is none. Expected: one caught 40P01 and one successful upgrade after the victim rolls back.

Document posting-then-closing as another retry case, preferably make closing its own transaction, and avoid wording that implies the three listed cycles exhaust arbitrary transaction compositions. “Writers never wait for each other” should be limited to their initial compatible head SHARE locks; the later advisory locks already contradict the unqualified sentence. This does not establish an invalid committed snapshot or money write.

The r5 tenant-key deadlock correction is appropriate. My r4 N2 statement that close has no opposing tenant-row lock was incomplete: snapshot-line FK enforcement matters. Changing edges in a separate statement is useful only if the transaction is not already retaining a conflicting tenant-row lock; a statement boundary alone releases no such lock.

### S2 — Retain the remaining r4 test and wording follow-ups

**Executed — source findings; predicted for the database cases**, represented by n1, n9, n10, n11, n14 and n15.

CR15 now checks both 40001 and “retry it,” closing that part of r4 S2. Its start order still depends on sleeps rather than a readiness barrier. Repeated success does not establish the intended ordering on a delayed runner. The race header's “every race leg” observed-blocking claim still conflicts with CR15's explicitly nonblocking scenario.

Nested write-offs, A→B→A customer boundaries and the exact 1,000-entry acceptance boundary remain reviewer probes rather than maintained battery regressions. Their prior execution is useful evidence but does not make them recurring coverage. R9b's “adjustment first” wording still overstates what the textual ordering of writable CTEs guarantees.

R12f/g cover the principal root/descendant time failures. Add recurring coverage for negative infinity, a deeper descendant, preservation of past owner times, and an ordinary writer following rejected poison. n14 provides these cases. The function COMMENT still describes only rows naming another entry, although the r5 trigger also fires on root write-offs. Its nonfinite-negative-time diagnostic says “future”; rejection is correct, but “nonfinite or future” would be more accurate.

The planner settings are controls, not proof of an exact execution plan. The new invariant pins configuration, not a universal runtime bound. n15 tests removing each setting independently from each function, supplementing M68's recovery-function-only mutation.

## Notes and answers

### N1 — R4 B1 is closed for r5 admissions; history remains usable

**Predicted.** Patch lines 601–618, 665–670 and 727–729. Probes n14, s1-history-batch, n12, n13 and n16.

The trigger now fires for an unlinked write-off as well as every linked row. A root write-off is checked before the early return. A linked row is checked for every same-customer write-off ancestor reached by the walk. Nonfinite timestamps and timestamps later than the sampled wall clock raise 23514. Consequently neither the root nor a descendant can newly install the infinity/far-future timestamp that caused r4's indefinite 40001 retries.

Past timestamps are tested but not rewritten. Ordinary writers retain the base database stamp, now(), which normally precedes clock_timestamp(). Rejecting a poison attempt rolls its row back; n14 then posts an ordinary recovery successfully, even when the caller supplies infinity, and checks the actual stored stamp. Finite older transactions can still receive the intended 40001 after a younger transaction posts first; a fresh transaction can resolve that ordering conflict. This assumes normal clock progression, not a guarantee against arbitrary host clock rollback or unbounded competing work.

The new check does not reject a charge or adjustment component with no write-off ancestor. n14 deliberately retains future owner timestamps outside the scoped tree. The independent close guard still refuses future-recorded money it would otherwise freeze.

R4 S1 is **documented, not behaviorally removed**: R12 requires one chronological statement per recorded instant under a write-off. The carried-forward history probe expects the mixed-instant statement to fail with 40001 and the identical past rows in two statements to succeed. That is a viable import path and remains nonblocking; repeatedly retrying the unchanged mixed-instant statement is not a remedy.

**Existing-data limit:** adding an INSERT trigger does not inspect rows already present in the -21 base. Neither the new time guard nor the catalog invariant is a historical-data audit. n16 checks existing write-off components immediately after application and expects zero nonfinite/future coordinates. I have not established that count. If it is nonzero, resolve those rows before treating that database as deployment-ready; this verdict does not certify migration over poisoned pre-existing history. The already-applied marker also skips the whole patch, so applying r5 atop an r4 scratch database is not an upgrade test.

### N2 — Requirements, freeze and period lifecycle

**Predicted.** Probes n1 (H/P/C/F/G/W), n2, n3 and n13.

The scoped P/S/G/W inventory and D-2/D-3/R-02 rulings are represented. Periods are freeze boundaries; reporting keeps ledger date coordinates and the existing range index. The snapshot records the close; GL mappings are tenant data; aging carries customer/status/location coordinates; the write-off threshold setting is stored. G2's missing-mapping export refusal remains explicitly assigned to the core, not silently implemented as a GL.

The ledger INSERT freeze and payment/credit date-or-tenant UPDATE guards check the closed-through head. Moving tenants checks both books; immutable ledger identity protects already-recorded money. The source supplies no newly identified ordinary-DML bypass through reopening, editing, deleting, born-closed periods, direct snapshots or backward heads. Creation/withdrawal use the period-chain lock, active overlap is excluded, withdrawal requires its user, and close checks supervisor, order and the end of the last day at UTC-12.

These conclusions concern the patch's declared surfaces. R1/R2 intentionally leave other events and status-only transitions for the ledger integration/-23; the patch does not claim to have completed -23.

### N3 — Write-off trees and aging

**Predicted.** Probes n1 (R/W), n6–n10, n12–n14.

The existing same-customer ancestor/descendant walks, per-write-off advisory locks and READ COMMITTED restriction remain intact. Direct recoveries require their named write-off, matching tenant/customer and correct sign. The net is bounded at each effective date; the window's default peer grouping evaluates all rows on one date together. The recorded-order rule preserves checked recorded prefixes, subject to R12's import restriction.

Nested write-offs are checked against each applicable ancestor. A customer boundary stops the component; returning to the first customer does not reconnect it through the other customer's row. Lineage admission rejects cycles and chains beyond its bound before the cap. No additional committed over-cap or below-zero route was identified.

Aging uses explicit tenant/date/recorded coordinates, nets connected same-customer components, allocates positive balances to newest remaining debit portions, reports credit balances separately, and omits zero balances. Status is read at recorded time; the last located ledger entry remains the declared location approximation. Invoker rights and visible-head validation retain the RLS boundary, including explicit tenant requests by platform admins. The 36-coordinate probe is a finite regression fixture, not an exhaustive mathematical proof.

### N4 — Snapshot and locks

**Predicted.** Probes n1 (C/W), n2, n5, n11 and s1-head-upgrade.

Opening balance uses dates before the period; activity includes both endpoints; closing equals opening plus activity. Activity lines group ledger types. Aging lines sum bucket amounts and count distinct customers. The optional unbilled figure requires its basis and is stored in the snapshot, not inserted into the ledger.

The close takes the head before sampling its recorded instant, and an edge change takes the same head FOR SHARE. This orders changed tenant edges with the close's subsequent read under READ COMMITTED. The snapshot stores those edges; reproduction uses the four-argument aging function. History backdating or the timestamp of an edge transaction that waited for close can change the three-argument historical answer, as R10 states, without changing the snapshot's edges.

Concurrency conclusions here are source predictions. n5 tests stored-edge reproduction in one session; n11 inspects the guard and invariant. Neither reproduces CR13/CR14's two-session handshake, whose successful execution remains author-reported. S1 supplies a separate, previously unlisted cycle.

### N5 — GL mapping, seal and invariants

**Predicted.** Probes n1 (G/I/H/C), n3, n4, n10, n11 and n15.

GL values cannot be changed in place. One effective-end closure is allowed and timestamped; changed values require a successor. The freeze applies to mapping starts and closes, and lookup uses effective and recorded coordinates with the stated 8/4/2/1 precedence.

The close retains the -20 seal pattern: constrained NOLOGIN role without membership/elevated attributes, exact function ownership and explicit grant list, pinned definer search path, no code-creation privilege, RLS, and guarded writes. R5 adds no role grant. The write privileges match the close's operations. The SELECT list is **not literally the smallest column set**: account_ledger and customer_state_events remain table-wide reads. No new surplus write capability was identified.

The periods invariant now checks both walk functions' exact proconfig arrays, including search_path and the three planner settings, and pins the widened trigger definition. It still intentionally checks enumerated definitions/ALWAYS state/constraints/head coverage, not function bodies, every PK/FK, data correctness or execution plans. Exact array comparison can reject equivalent differently ordered configuration; that is conservative drift detection, not an admission gap.

### N6 — Tests, mutations and COPY

**Executed — source interpretation; predicted behavioral checks** in n1, n7, n14 and n15. No runner was executed.

M69/M70 target the descendant/root time checks; M72 targets trigger eligibility and is caught by the apply-time definition invariant. M68 now names an apply-time settings failure, so its result should no longer be presented as independent performance evidence. M71 names R10f rather than R12h because the earlier same-date fixture also exposes row-by-row accumulation. That is relevant earlier coverage, not an identified unrelated-error catch.

The runner retains exact named-failure matching; setup errors are not automatically counted as behavioral catches. M53's apply-time trigger detection and M48's alternative CHECK/diagnostic failure still require the interpretation described in r4: “caught” alone does not prove an invalid row would otherwise commit. No new concrete wrong-reason catch was established.

n1 is the frozen r5 battery with full SQLSTATE/message notices added to caught-error handlers, including sentinels and query cancellation. n7 retains the corrected server-side COPY control: successful integer COPY, deliberately invalid integer with caught 22P02, then the actual cycle COPY with its own caught 23514 and partial-row check. It never relies on LAST_ERROR_SQLSTATE. Its author-executed r4 result was valid; the r5 copy remains unexecuted.

### N7 — Residuals R1–R12

**Predicted scope assessment**, with behavioral probes referenced above.

R1/R2 defer remaining money-event/lifecycle binding; R3 defers per-bill allocation; R4/R5 declare status/location coordinates; R6/R7 leave vocabulary synchronization and place-kind validation; R8 scopes general reversals to -23 while retaining this patch's write-off cap and lineage rules; R9 fails on unknowable pre-setting history; R10 distinguishes mutable configuration history from stored snapshot edges; R11 limits performance evidence; R12 documents chronological import statements. None independently blocks this patch within the agreed inventory. R12 is an operational import constraint, and R11 must not be advertised as an exact-plan or arbitrary-scale guarantee.

## Probe index

All database probes are **predicted / not executed by Codex**.

| File | Purpose |
|---|---|
| n1-battery.sql | Frozen r5 battery with full caught-error diagnostics |
| n2-statement-regression.sql | Multi-row periods/cap, writable CTE close, own-close freeze |
| n3-gl-coordinate.sql | Same-transaction recorded GL lookup |
| n4-invariant-definition.sql | Vacuous recovery CHECK drift |
| n5-snapshot-edges.sql | Stored edges versus later live/history changes |
| n6-cycle-shapes.sql | VALUES and writable-CTE cycles |
| n7-copy-cycle.sql | COPY transport/error-capture controls and cycle |
| n8-aging-rls.sql | Tenant and platform-admin explicit-tenant reads |
| n9-nested-trees.sql | Nested caps and A→B→A boundary |
| n10-bound-and-invariants.sql | 1,000/1,001 boundary and constraint/grant drift |
| n11-settings-and-edge-invariant.sql | Settings/grants, edge-trigger drift, representative EXPLAIN |
| n12-date-recorded-grid.sql | Bounce/correction at 36 coordinate pairs |
| n13-serializable-admission.sql | Isolation admission refusals |
| n14-future-time.sql | Nonfinite/future root/recovery/deeper row, retained history, ordinary stamping, outside-tree scope |
| n15-plan-invariant.sql | Each pinned setting removed from each walk independently |
| n16-existing-time-audit.sql | Invalid coordinates already present in the cloned base |
| s1-history-batch.sql | R12 refusal and chronological-statement workaround |
| s1-head-upgrade.sql | Manually coordinated two-session head-lock upgrade cycle |

The carried-forward observational probes print actual outcomes; their process exit alone is not a pass assertion. Compare their notices with the stated predictions. No probe result or runtime measurement is claimed in this review.

## Author's execution of the probes (2026-10-16)

Each probe was run as the owner on its own fresh clone of `tally` with frozen r5 (md5 `7e914bda…`) strictly applied and TEMP revoked, with a 300 s statement timeout. There were no setup failures except s1-head-upgrade (below), and every probe printed what Codex predicted.

- **n1:** 157 PASS, no FAIL.
- **n14:** the root write-off, a recovery and a deeper adjustment are each refused with 23514 at `infinity`, `-infinity` and +100 years. Past owner history is kept, and future rows outside a write-off tree are admitted. An ordinary recovery that supplies `infinity` is admitted and stamped at the transaction time. The r4 B1 probe, re-run against r5, is refused at its `infinity` row.
- **n15:** removing any one of the four settings from either walk function is caught (0LP01), eight cases in all.
- **n16:** the cloned base has 0 write-off-tree rows at a non-finite or future time.
- **s1-history-batch:** the mixed-instant batch is refused with 40001, and the same rows in two statements are admitted (R12).
- **S1 reproduced (s1-head-upgrade):** the base `tally` has no tenant, so the probe stopped at its own setup check. It was re-run on a clone with one committed tenant (its head is created with it), in two concurrent sessions, with `\prompt` replaced by `pg_sleep(3)` and B started 0.5 s after A. A got 40P01 `deadlock detected`, and B's upgrade was acquired.

```
n1-battery: caught SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: a close head is born with nothing closed; only close_accounting_period() moves it (v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=tenant 00000000-0000-4000-8000-0000000022a1: the closed-through date moves only forward, and only through close_accounting_period() (v5.4.2-22)
/tmp/n1-battery.sql:117: NOTICE:  caught SQLSTATE=23001 message=accounting_close_heads rows are never deleted: the closed-through date is the freeze every money write reads (v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=accounting_close_heads rows are never deleted: the closed-through date is the freeze every money write reads (v5.4.2-22)
n1-battery: caught SQLSTATE=42501 message=permission denied for table accounting_close_heads
n1-battery: caught SQLSTATE=23001 message=tenant 00000000-0000-4000-8000-0000000022a1: the closed-through date moves only forward, and only through close_accounting_period() (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: the next accounting period starts on 2026-02-01, the day after the latest ends — not 2026-01-15 (no gaps, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: the next accounting period starts on 2026-02-01, the day after the latest ends — not 2026-02-02 (no gaps, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=tenant 00000000-0000-4000-8000-0000000022a1: an accounting period is born open; only close_accounting_period() closes it (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=new row for relation "accounting_periods" violates check constraint "accounting_periods_range_check"
n1-battery: caught SQLSTATE=42501 message=permission denied for table accounting_periods
n1-battery: caught SQLSTATE=42501 message=permission denied for table accounting_periods
n1-battery: caught SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002212: only the tenant's latest period, while open, may be withdrawn (v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002213: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withd
n1-battery: caught SQLSTATE=23502 message=accounting period 00000000-0000-4000-8000-000000002214: a withdrawal names its user (app.user_id) (v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002211: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withd
n1-battery: caught SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002211: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withd
n1-battery: caught SQLSTATE=23001 message=accounting_periods rows are never deleted: a snapshot and the freeze stand on them; a mistyped open period is withdrawn (v5.4.2-22)
n1-battery: caught SQLSTATE=42501 message=close_accounting_period(): closing a period is irreversible and is a supervisor's act (app.user_id must name a tenant administrator or a platform administrator) (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002212 starts on 2026-02-01; the books are closed through nothing — periods close in order, the earlier first (v5.4.2-22)
n1-battery: caught SQLSTATE=22023 message=close_accounting_period(): an unbilled-revenue figure is reported with its basis, or neither is given (D-2, v5.4.2-22)
n1-battery: caught SQLSTATE=22023 message=close_accounting_period(): an unbilled-revenue figure is reported with its basis, or neither is given (D-2, v5.4.2-22)
n1-battery: caught SQLSTATE=P0002 message=Accounting period 00000000-0000-4000-8000-000000002219 not found
n1-battery: caught SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002219 ends on 2026-10-16, which has not ended everywhere yet; a period closes after its last day (v5.4.2-22)
n1-battery: caught SQLSTATE=42501 message=permission denied for function close_accounting_period
n1-battery: caught SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002211 (2026-01-01 to 2026-01-31) is already closed; a closed period never reopens (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002213 (2026-03-01 to 2026-03-31) is withdrawn; a withdrawn period never closes or returns (v5.4.2-22)
n1-battery: caught SQLSTATE=42501 message=permission denied for table accounting_period_snapshots
n1-battery: caught SQLSTATE=42501 message=permission denied for table accounting_period_snapshot_lines
n1-battery: caught SQLSTATE=23001 message=accounting_period_snapshots is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=accounting_period_snapshot_lines is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=accounting_period_snapshot_lines is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=account_ledger: dated 2026-01-15, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, 
n1-battery: caught SQLSTATE=23514 message=account_ledger: dated 2025-06-30, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, 
n1-battery: caught SQLSTATE=23514 message=payments: dated 2026-01-30, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2
n1-battery: caught SQLSTATE=23514 message=payments: dated 2026-01-28, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2
n1-battery: caught SQLSTATE=23514 message=payments: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2
n1-battery: caught SQLSTATE=23514 message=payments: dated 2026-01-28, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2
n1-battery: caught SQLSTATE=23514 message=customer_credits: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2
n1-battery: caught SQLSTATE=23514 message=account_ledger: dated 2026-01-31, on or before 2026-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, 
n1-battery: caught SQLSTATE=23514 message=new row for relation "account_ledger" violates check constraint "account_ledger_recovery_lineage_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "account_ledger" violates check constraint "account_ledger_recovery_lineage_check"
n1-battery: caught SQLSTATE=23503 message=a write-off recovery names a write_off entry of its own customer; 00000000-0000-4000-8000-0000000022e2 is not one (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23503 message=a write-off recovery names a write_off entry of its own customer; 00000000-0000-4000-8000-0000000022e4 is not one (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=a write-off recovery has the opposite sign of its write-off: -10.00 against -50.00 (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-0000000022e4: on 2026-02-11 the rows netted against it would come to 50.01, outside 0 to the 50.00 written off (R-02 cap, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-0000000022e4: on 2026-02-12 the rows netted against it would come to 50.01, outside 0 to the 50.00 written off (R-02 cap, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=a row of type adjustment names write-off 00000000-0000-4000-8000-0000000022e4: only a write_off_recovery names a write-off, so the cap counts it (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=account_ledger 00000000-0000-4000-8000-0000000022ea: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=a row of type adjustment names write-off 00000000-0000-4000-8000-000000002251: only a write_off_recovery names a write-off, so the cap counts it (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=a row of type adjustment names write-off 00000000-0000-4000-8000-000000002251: only a write_off_recovery names a write-off, so the cap counts it (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-000000002251: on 2026-02-15 the rows netted against it would come to 110.00, outside 0 to the 100.00 written off (R-02 cap, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-000000002251: on 2026-02-15 the rows netted against it would come to -10.00, outside 0 to the 100.00 written off (R-02 cap, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-000000002251: on 2026-02-16 the rows netted against it would come to 100.01, outside 0 to the 100.00 written off (R-02 cap, v5.4.2-22)
n1-battery: caught SQLSTATE=P0001 message=R10f sentinel: admitted
n1-battery: caught SQLSTATE=P0001 message=R10g sentinel
n1-battery: caught SQLSTATE=23514 message=account_ledger 00000000-0000-4000-9022-000000000001: its reversal chain does not reach an original within 1000 entries (too long, or a loop); a reversal names an earlier entry (R-02, v5.4.
n1-battery: caught SQLSTATE=23514 message=write-off 00000000-0000-4000-8000-000000002261: on 2026-02-20 the rows netted against it would come to 200.00, outside 0 to the 100.00 written off (R-02 cap, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=a row under write-off 00000000-0000-4000-8000-000000002261 is dated on or after the entry it names: 0d8e9cad-3c92-4245-bf30-edbf4afe49ff is dated 2026-02-03, before 2026-02-25 (R-02, v5.4.
n1-battery: caught SQLSTATE=23514 message=a row under write-off 00000000-0000-4000-8000-000000002261 is dated on or after the entry it names: 7e359aac-fba7-4b10-98df-99610fcd8461 is dated 2026-02-09, before 2026-02-10 (R-02, v5.4.
n1-battery: caught SQLSTATE=P0001 message=R12d sentinel
n1-battery: caught SQLSTATE=40001 message=write-off 00000000-0000-4000-8000-000000002261: 05ad3a33-bf46-4040-9b64-880f457c9fcd is recorded at 2026-10-16 17:48:06.238467+00, before 00000000-0000-4000-8000-000000002261 (recorded at 
n1-battery: caught SQLSTATE=23514 message=write-off 1e531081-1058-47ae-88a9-2902f31055d6 is recorded in the future (infinity): a row in a write-off's tree is recorded at a time already reached (R-02, v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=a row under write-off 00000000-0000-4000-8000-000000002261 is recorded in the future (2200-01-01 00:00:00+00): a row in a write-off's tree is recorded at a time already reached (R-02, v5.4
n1-battery: caught SQLSTATE=P0001 message=R12h sentinel
n1-battery: caught SQLSTATE=22004 message=receivables_aging_as_of: tenant, date and recorded-at coordinate are all required; never default to today (v5.4.2-22)
n1-battery: caught SQLSTATE=P0002 message=receivables_aging_as_of: tenant 00000000-0000-4000-8000-0000000022a2 has no aging bucket setting recorded at 2026-10-16 17:49:07.508425+00, or is not visible in this session (v5.4.2-22)
n1-battery: caught SQLSTATE=22023 message=receivables_aging_as_of: [0:1]={90,30} is not a list of bucket edges (one-based, 1 to 12 positive days, increasing) (v5.4.2-22)
n1-battery: caught SQLSTATE=P0002 message=receivables_aging_as_of: tenant 00000000-0000-4000-8000-0000000022a1 has no aging bucket setting recorded at 2026-10-16 17:49:05.238467+00, or is not visible in this session (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_receivables_aging_bucket_days_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenant_configuration_history" violates check constraint "tenant_configuration_history_aging_days_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenant_configuration_history" violates check constraint "tenant_configuration_history_aging_days_check"
n1-battery: caught SQLSTATE=22000 message=receivables_aging_as_of: 2 ledger entries of tenant 00000000-0000-4000-8000-0000000022a1 reach no original (a reversal loop); aging would omit them (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=new row for relation "tenants" violates check constraint "tenants_write_off_threshold_days_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_charge_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_charge_pair_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_customer_class_check"
n1-battery: caught SQLSTATE=23514 message=new row for relation "gl_account_mappings" violates check constraint "gl_account_mappings_account_check"
n1-battery: caught SQLSTATE=23P01 message=conflicting key value violates exclusion constraint "gl_account_mappings_no_overlap"
n1-battery: caught SQLSTATE=23514 message=gl_account_mappings: a mapping in force on or before 2026-01-31, the end of the last closed period, would change a closed period's export (D-2, v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=gl_account_mappings 00000000-0000-4000-8000-000000002232 is never edited: a change is a close (effective_to, once) and a successor row (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=gl_account_mappings 00000000-0000-4000-8000-000000002232: a close on 2026-01-31 would end the mapping inside a closed period (closed through 2026-01-31) (D-2, v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=gl_account_mappings 00000000-0000-4000-8000-000000002232 is never edited: a change is a close (effective_to, once) and a successor row (v5.4.2-22)
n1-battery: caught SQLSTATE=42501 message=permission denied for table gl_account_mappings
n1-battery: caught SQLSTATE=22004 message=gl_mapping_as_of: tenant, charge source and code, date and recorded-at coordinate are required; never default to today (v5.4.2-22)
n1-battery: caught SQLSTATE=23001 message=gl_account_mappings rows are never deleted: a past export must stay answerable (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002214 starts on 2026-03-01; the books are closed through 2026-01-31 — periods close in order, the earlier first (v5.4.2-22)
n1-battery: caught SQLSTATE=23514 message=accounting period 00000000-0000-4000-8000-000000002214: ledger rows dated on or before 2026-03-31 are recorded after the close's instant 2026-10-16 17:49:07.535387+00; a close counts every
n1-battery: caught SQLSTATE=23001 message=accounting period 00000000-0000-4000-8000-000000002212: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withd
n10-bound-and-invariants: 1000 entries including root admitted
n10-bound-and-invariants: bound SQLSTATE=23514 message=account_ledger 9f770806-7edb-4cfb-bdd8-97dcd19e77f2: its reversal chain does not reach an original within 1000 entries (too long, or a loop); a reversal names an earlier entry
n10-bound-and-invariants: constraint tenant_configuration_history_key_known_check SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
n10-bound-and-invariants: constraint account_ledger_reversal_not_self_check SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
n10-bound-and-invariants: constraint account_ledger_reverses_ledger_entry_fkey SQLSTATE=0LP01 message=a v5.4.2-22 constraint is missing, changed or not validated:
n10-bound-and-invariants: closed_by SQLSTATE=0LP01 message=the close's tables are writable outside close_accounting_period() (closed_through or status) (v5.4.2-22)
n11-settings-and-edge-invariant: enforce_write_off_recovery() function settings: {"search_path=public, pg_temp",enable_seqscan=off,enable_hashjoin=off,enable_mergejoin=off}
n11-settings-and-edge-invariant: enforce_ledger_lineage_acyclic() function settings: {"search_path=public, pg_temp",enable_seqscan=off,enable_hashjoin=off,enable_mergejoin=off}
n11-settings-and-edge-invariant: Edge guard body: CREATE OR REPLACE FUNCTION public.enforce_aging_edges_close_order()
n11-settings-and-edge-invariant: Close role explicit privileges: {"column public.accounting_close_heads.closed_through UPDATE","column public.accounting_close_heads.updated_at UPDATE","column public.accounting_periods.closed_at UP
n11-settings-and-edge-invariant: disabled edge guard SQLSTATE=0LP01 message=a v5.4.2-22 guard is missing, changed, or not ENABLE ALWAYS:
n12-date-recorded-grid: 36 date/recorded coordinates: cap in [0,100], aging reconciles; correction of correction accepted
n13-serializable-admission: SERIALIZABLE admission SQLSTATE=25000 message=an accounting period is created at READ COMMITTED (this transaction is serializable): the no-gap check must see the latest period committed while it waited 
n13-serializable-admission: SERIALIZABLE admission SQLSTATE=25000 message=close_accounting_period() runs at READ COMMITTED (this transaction is serializable): the close must read what the writers it waited for committed (v5.4.2-22
n13-serializable-admission: SERIALIZABLE admission SQLSTATE=25000 message=a row under write-off 7bfb8796-6270-4516-bce2-b826b01c31d5 is posted at READ COMMITTED (this transaction is serializable): the cap must see every row commit
n14-future-time: write_off at infinity SQLSTATE=23514 message=write-off fdc04934-c858-4a61-84a9-2e41b76dcfd5 is recorded in the future (infinity): a row in a write-off's tree is recorded at a time already reached (R-02, v5.4.2-22)
n14-future-time: write_off_recovery at infinity SQLSTATE=23514 message=a row under write-off 745c0bf8-a182-4c79-b3b0-9952f7dbdd11 is recorded in the future (infinity): a row in a write-off's tree is recorded at a time already reac
n14-future-time: adjustment at infinity SQLSTATE=23514 message=a row under write-off 745c0bf8-a182-4c79-b3b0-9952f7dbdd11 is recorded in the future (infinity): a row in a write-off's tree is recorded at a time already reached (R-0
n14-future-time: write_off at -infinity SQLSTATE=23514 message=write-off 65ab905f-19df-4c93-8249-04918d636756 is recorded in the future (-infinity): a row in a write-off's tree is recorded at a time already reached (R-02, v5.4.2-2
n14-future-time: write_off_recovery at -infinity SQLSTATE=23514 message=a row under write-off 745c0bf8-a182-4c79-b3b0-9952f7dbdd11 is recorded in the future (-infinity): a row in a write-off's tree is recorded at a time already re
n14-future-time: adjustment at -infinity SQLSTATE=23514 message=a row under write-off 745c0bf8-a182-4c79-b3b0-9952f7dbdd11 is recorded in the future (-infinity): a row in a write-off's tree is recorded at a time already reached (R
n14-future-time: write_off at 2126-10-16 17:49:09.850812+00 SQLSTATE=23514 message=write-off 13fbbd8e-55f1-4721-ac19-560e2aeaea35 is recorded in the future (2126-10-16 17:49:09.850812+00): a row in a write-off's tree is recorded a
n14-future-time: write_off_recovery at 2126-10-16 17:49:09.850812+00 SQLSTATE=23514 message=a row under write-off 745c0bf8-a182-4c79-b3b0-9952f7dbdd11 is recorded in the future (2126-10-16 17:49:09.850812+00): a row in a write-off
n14-future-time: adjustment at 2126-10-16 17:49:09.850812+00 SQLSTATE=23514 message=a row under write-off 745c0bf8-a182-4c79-b3b0-9952f7dbdd11 is recorded in the future (2126-10-16 17:49:09.850812+00): a row in a write-off's tree 
n14-future-time: Past history retained; future root/descendant outside write-off tree admitted
n14-future-time: Ordinary recovery admitted, supplied infinity stamped to transaction time 2026-10-16 17:49:09.841871+00
n15-plan-invariant: public.enforce_write_off_recovery() reset enable_seqscan SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce_write
n15-plan-invariant: public.enforce_write_off_recovery() reset enable_hashjoin SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce_writ
n15-plan-invariant: public.enforce_write_off_recovery() reset enable_mergejoin SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce_wri
n15-plan-invariant: public.enforce_write_off_recovery() reset search_path SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce_write_of
n15-plan-invariant: public.enforce_ledger_lineage_acyclic() reset enable_seqscan SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce_l
n15-plan-invariant: public.enforce_ledger_lineage_acyclic() reset enable_hashjoin SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce_
n15-plan-invariant: public.enforce_ledger_lineage_acyclic() reset enable_mergejoin SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce
n15-plan-invariant: public.enforce_ledger_lineage_acyclic() reset search_path SQLSTATE=0LP01 message=a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): public.enforce_ledg
n15-plan-invariant: Both functions: each removed setting detected; subtransaction restored definitions
n16-existing-time-audit: Existing invalid time count=0 (expected zero for deployment)
n2-statement-regression: OBSERVED N2 contiguous periods in multi-row statement=3
n2-statement-regression: OBSERVED N2 recovery statement refused: 23514 write-off 81c8736f-9448-4a4a-b841-c7e3e74465e5: on 2020-01-03 the rows netted against it would come to 60.00, outside 0 to the 50.00 written off (R-02 cap, v5.
n2-statement-regression: OBSERVED N2 cap SQLSTATE=23514 surviving recovery count=0
n2-statement-regression: OBSERVED N2 CTE close at=2026-10-16 17:49:10.842181+00 snapshot closing=75.00 ledger=75.00
n2-statement-regression: OBSERVED N2 after-close write refused: 23514 account_ledger: dated 2020-01-07, on or before 2020-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correctio
n3-gl-coordinate: OBSERVED N3 at=2026-10-16 17:49:11.205936+00 before=389a82b2-f455-4636-87c9-57e407ac69b3 after=389a82b2-f455-4636-87c9-57e407ac69b3 close stamp=2026-10-16 17:49:11.206488+00
n4-invariant-definition: OBSERVED N4 invariant refused: 0LP01 a v5.4.2-22 constraint is missing, changed or not validated:
n5-snapshot-edges: OBSERVED N5 before=[{"amount": 100.00, "balance": 100.00, "customer_id": "42544b6c-5a11-4818-9556-49a5c3e0a33c", "bucket_index": 0, "bucket_to_days": 30, "customer_number": "CX-1", "customer_status": "active", "
n5-snapshot-edges: OBSERVED N5 snapshot edges={30,60,90,120}; as-of edges={15,45}
n5-snapshot-edges: OBSERVED N5 manual backdate accepted; same-coordinate edges now={10,20}
n5-snapshot-edges: R2 explicit edges unchanged after manual history=t
n5-snapshot-edges: R2 three-argument result changed=t
n6-cycle-shapes: multi-row cycle SQLSTATE=23514 message=account_ledger d32c014e-5143-4b19-8a0b-7b1b6ce9ff87: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
n6-cycle-shapes: writable CTE cycle SQLSTATE=23514 message=account_ledger a7f37c99-7a6d-4f78-98bb-ebe1b0e57acf: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
n7-copy-cycle: COPY capture control SQLSTATE=22P02 message=invalid input syntax for type integer: "not-an-integer"
n7-copy-cycle: COPY transport and error capture controls passed
n7-copy-cycle: COPY cycle SQLSTATE=23514 message=account_ledger c0440000-0000-4000-8000-000000000003: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)
n8-aging-rls: tenant own aging rows=1 sum=100.00
n8-aging-rls: tenant cross-tenant SQLSTATE=P0002 message=receivables_aging_as_of: tenant 3344f9c5-71bf-49df-aea5-eb361b07578c is not visible in this session (v5.4.2-22)
n8-aging-rls: platform requested tenant one rows=1 sum=100.00
n8-aging-rls: platform requested tenant two rows=1 sum=200.00
n9-nested-trees: nested valid tree admitted; expected outer net=80 inner net=30
n9-nested-trees: inner overflow SQLSTATE=23514 message=write-off 1d4aa917-8f2d-4fc1-867b-79a14d84c5ae: on 2020-01-01 the rows netted against it would come to 31.00, outside 0 to the 30.00 written off (R-02 cap, v5.4.2-22)
n9-nested-trees: outer overflow SQLSTATE=23514 message=write-off 9fdb2751-20c8-46cc-ba63-ac238173e44a: on 2020-01-01 the rows netted against it would come to 101.00, outside 0 to the 100.00 written off (R-02 cap, v5.4.2-22)
n9-nested-trees: cross-customer boundary respected; total aging=981.00
s1-history-batch: valid multi-instant batch SQLSTATE=40001 message=write-off 992387f5-e9a0-4f4d-89e9-de8c72ea81d9: 5cd61eaa-df33-49a9-b416-38da5e9ec8e2 is recorded at 2020-02-02 00:00:00+00, before a6d650f8-6b80-4c89-9dd4-d363af92
s1-history-batch: Same historical rows admitted as two statements: all date/recorded prefixes net 0, 50 or 30
-- s1-head-upgrade (two sessions)
A: PID 84285 holds head 17bf0f71-3742-462b-a20d-6a7b4154331f FOR SHARE
A: Head upgrade SQLSTATE=40P01 message=deadlock detected
B: PID 84292 holds head 17bf0f71-3742-462b-a20d-6a7b4154331f FOR SHARE
B: Head upgrade acquired
```
