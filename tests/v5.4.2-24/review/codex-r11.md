# Codex — v5.4.2-24, review round 11

**Verdict: ready.** No blocking production defect found in this source review. The r10 classification and late-code blockers are addressed by enforceable rules, rather than by accepting L7. One nonblocking should-fix remains in the conservation test: **Codex r10 S2 is improved but not fully closed**. The verdict is for the scoped additive record patch, not certification of a running database or of the collections application.

All database outcomes below are **predicted**, not executed. The supplied probes must be run by the author. “Executed” below means a filesystem/source check only.

## N1 — executed: identity, scope and evidence

Checked the brief and the six frozen files before further review; all seven MD5s match:

| File | MD5 |
|---|---|
| review-brief-24-r11.md | 4040b5b267aa9775c6aaaaa6074df157 |
| patch-24-frozen-r11.sql | 5518d76343e41cc9b6927dd3884a0233 |
| battery-24-frozen-r11.sql | 8328337768052b456974cd2590dfc84b |
| suspense-24-frozen-r11.sh | 360dea4db148825d696134bfa30e0502 |
| mutations-24-frozen-r11.py | 46f7ef4850ba5c50347ade59f366ab81 |
| ci-24-frozen-r11.diff | ec30f74364228bf3f325a1958583d01b |
| r10-to-r11.diff | f428a197b0c908aa6402030a2d9a5da4 |

Read r11's plan first, then the changes and relevant frozen source, the design, wave-2 source inventory, DECISION-LOG, GBM's CI-053/CI-056 and the two specified workflows. Consulted my r10 review and permitted author-run output. No `opus-*.md` or `fable-*.md` was read. The legal/program requirements are assessed as supplied rulings, not independently researched legal advice.

Source checks found **33 matching embedded function-body hashes** and **335 battery assertion call sites**. These are not database passes. Strict apply twice, 335 checks, 29 race results, 161 mutation catches and 61 CI steps remain author-reported. I ran no Docker, psql, CI, race script or mutation runner, and delegated no work.

Only this file and [codex-r11-probes](codex-r11-probes/) were written. There are 13 independent SQL probes. Run each as the owner on its own fresh clone with frozen r11 applied, after the brief's TEMP revocation. They end in ROLLBACK, and every caught error prints SQLSTATE and message with RAISE NOTICE. COPY is caught inside the server and reports its own error; no LAST_ERROR_SQLSTATE inference is used. Those COPY controls use a fixed generated `printf` payload through COPY FROM PROGRAM and require the brief's privileged test environment. An unexpected assertion abort under ON_ERROR_STOP requires disconnect/rollback, not continuation in that transaction.

## B — predicted: none found

I found no remaining concrete cash-loss or double-spend counterexample to the new ending rules with the inherited guards enabled. This is a scoped source conclusion, not an exhaustive proof over all SQL histories or schedules.

## S1 — predicted: S4c's bank operand is not a general conservation oracle

**Source:** frozen battery lines 1375–1399. **Probe:** [01-nested-nsf-conservation.sql](codex-r11-probes/01-nested-nsf-conservation.sql).

The revised expression nets undos and includes coded reversals, which improves r10 substantially. But `nsfroot` starts at **every** positive NSF row bearing the payment reference, then recursively includes every descendant with `UNION ALL`.

The probe makes a legitimate posted 100 payment, NSF +100, undo −100, and a second NSF +100 under that undo. It ends NSF, with no untyped take-back. Predicted results:

- The bank's net take-back is 100; receipt held, payment received and returns-due are all zero.
- S4c's bank expression is **200**: the second NSF row appears once as a seed and once as a descendant of the first NSF row.

The probe also makes a direct NSF reversal whose optional `reference_type` and `reference_id` are absent. Its reversal link still identifies the payment tree, as the production walks intend. Predicted: the ending succeeds and the production readers report the whole bank take-back; S4c finds **no seed**, so its bank operand is zero. This is a second reason to derive the oracle from the posting tree, not secondary reference labels.

Also, “every day” is still March 10–20, at current recorded knowledge. Receipts dated after that window are skipped by `received_on <= g.d`; the test does not sweep their lifetimes. S4b has a recorded-time grid, but tests only the upper bound and omits the bank operand. It does not supply the missing historical equality check.

**Should fix:** traverse each payment's posting tree once, classify entry into the first positive NSF subtree, and count every row of that subtree once. Preserve the distinct coded-reversal term. Generate dates from the fixture events and include recorded boundaries, or narrow the label to the actual sample. Add both probe shapes as fixtures, with independent expected bank amounts.

This leaves **Codex r10 S2 / r9 S1's broad conservation-coverage concern partially open**. It is not a demonstrated production money defect: the counterexample here breaks the test expression, while the production readers and ending rules give the intended result. It therefore does not block this verdict. It should be repaired before relying on S4c as a reusable reconciliation oracle.

## N2 — predicted: closure of r10 and earlier findings

| Finding from the brief | Assessment and r11 probe evidence |
|---|---|
| Codex r10 B1; Opus S1/S3: two plain reversals hidden by one code | Closed for the reported case. A nonzero share requires a named cause retaining the whole payment before a coded `reversed` is admitted. 00 P17–P17d also exercises returning the whole and separately recording the bank's 40. |
| Codex r10 B1, undone NSF cause with no bank remainder | Closed. NSF requires share below the payment, together with the untyped-subtree prohibition. 00 P18. A named cause need not itself retain money if another properly typed NSF takes it; the rule establishes a standing bank portion, not a claim that this cause alone took it all. |
| Codex r10 B1 probe 08, misposting beneath a bounce's undo | Closed at the ending. `suspense_untyped_take_back` refuses a positive untyped remainder before either ending. 00 P19/P19b/P19c verifies refusal and correction before ending. |
| Codex r10 S1; Opus S2: late/early code changes historical answers | Closed for the reported paths. Late code on `reversed` is refused; code written with the ending is gated by `status_recorded_at` in the due reader. 00 P9b9, S8y; 08 owner late-code control. A late NSF code does not change the due reader's classification. 00 P15h and 02. |
| Opus S4: pending posting entry undone | Closed for the reported path, including deposit, multi-row insert, COPY and replica mode controls. 00 P20; 02; 08. |
| Fable S2: born reversed/NSF import | Closed for these two statuses, including owner. 00 O7/O7b. The supported load order remains pending → posting row → posted → reversals → ending. This is not a promise that arbitrary superuser imports are valid. |
| Fable S1; Codex S2; Opus N4: conservation | Partially closed; S1 above remains. |
| Opus S5: new assertions/mutations | The new target checks are present; 00 carries the frozen battery with error notices added. No new concrete wrong-reason catch found by source inspection, but mutation execution is not certified. |

The historical counterexamples from r9 remain represented by **09, 10 and 11**: the undo interval, recording after transaction start, and a historical reversal omitted by a final-only share. Their expected corrected readings remain consistent with the source. The r6 full-tree date/recorded-order bounds, r7 exact return, r8 due queue, provider namespace/isolation protections, instrument pinning, NaN guards, tenant checks, settings checks, retirement/agreement rules and typed refund routing remain in source and are exercised by **00, 03–07, 09–11 and 13**. I found no earlier production counterexample reintroduced. That is a source assessment; it does not convert old author runs into r11 executions.

## N3 — predicted: the three direct questions

### 1. Deposit payment

A receipt's deposit payment is in the root selection of both share functions, the untyped walk and the new pending guard. Inherited -23 chooses `deposit` as its posting kind and fixes `is_deposit` at insert. I found no differing rule that defeats these ending checks.

**02** creates actual deposit payments at insert, checks pending-reversal refusal, coded whole reversal, terminal immutability, extra ledger rows, a 60-misposted/40-NSF split, the late NSF code and replica mode. **07** retains the ordinary deposit reversal/return control. In fact, the permitted r10 probe 07 already contained a receipt-funded deposit control; the missing test is in the *frozen battery*, not all prior review evidence.

Add these controls to the permanent battery. The omission alone is a note, not a blocker and not something that must wait for a deposit patch. Routing an agency-funded deposit's eventual refund is the distinct accepted L5 limit; these controls do not close it.

### 2. Ending order, undone causes, status changes and statement shapes

**Evidence:** 00 P12a/P17–P22/O7/O7b/S8y; 02; 08; 13; catalog/order probe 06.

- A coded whole reversal is admitted; two plain partial reversals with a code are not. Whole typed bank take-back remains admitted even when the non-NSF cause is undone (P21).
- After ending, a negative descendant that would undo the cause is refused by -23's `enforce_ledger_reversal` while holding the payment lock. A further positive take-back alone exceeds the fully reversed root's cap. A compensating multi-row insert cannot escape simply by netting to zero: its negative row still meets the ended-source refusal.
- Neither `reversed → nsf` nor `nsf → reversed` passes inherited `enforce_payment_immutable`. Its transition rule is not waived for owner history loads.
- Code-only updates on reversed payments cannot evade the rule by keeping the status unchanged. NSF code updates remain deliberately allowed and do not hide the misposted share.
- Multi-statement transactions see their preceding statements. 08 tests a pending root/reversal in one multi-row insert and COPY, then the legitimate separate posting/ending order as owner. 13 tests a multi-row mixed reversal followed by a dependent writable CTE ending and return, plus duplicate-return COPY. 03 covers the cap and pledge/error CTEs in both dependency directions.

These controls do not assume that a writable CTE gives arbitrary sibling substatements an execution order. Where a prerequisite is not visible, refusal is acceptable; do not use a sibling CTE as a substitute for the documented ordered load.

### 3. New ledger trigger and every writer

**Source:** patch 1003–1031; inherited `enforce_ledger_reversal` and `void_invoice` in `sql/tu.sql`. **Evidence:** 06 prints actual grants, definer owners and trigger order; 08 exercises the non-payment early-return branch as `tally_void`, core denial, app and owner; 02 exercises replica mode.

| Role/path | Source assessment |
|---|---|
| `tally_app` | Has ledger INSERT/SELECT and payments SELECT. Legitimate posted-payment reversals can pass. A pending receipt-payment reversal is intentionally rejected. No new missing helper grant is needed: this trigger performs direct SELECTs. |
| `tally_core` | Read-only; no legitimate ledger INSERT. Its attempted insert fails at privileges, not at the new trigger. |
| `tally_void` | Has ledger INSERT/SELECT, no payments SELECT. Its canonical writer reverses an invoice charge. Reading the parent and returning before the payments query is essential, and the revised function does that. Probe 08 tests this permission-sensitive branch; it is not a full invoice-void fixture. |
| Owner | Has access; same guard applies on normal and replica loads. Ordered pending/posting/posted histories are the supported contract. |
| `tally_seal`, `tally_close` | Not ledger INSERT writers under the pinned grants. `tally_close` reads the ledger. 06 exposes effective privileges for confirmation. |
| SECURITY DEFINER writers in `tu.sql` | All explicit ledger INSERT sites found are successive definitions of `void_invoice`; the final live writer is owned by `tally_void`. They are not eight separate live writers. No additional live definer ledger writer found. 06 lists live definers mentioning the ledger for author confirmation. |

The trigger is ordinary invoker-security code. Revoking direct EXECUTE on its trigger function does not require granting it to every inserting application role; the SELECT privileges used inside it do matter.

`ENABLE ALWAYS` matters: setting `session_replication_role=replica` does not skip this guard. This does not restore disabled foreign-key checks or promise support for children loaded before their parents. The inherited ALWAYS lineage/reversal checks also remain relevant.

For each applicable inserted row, the AFTER trigger follows the lineage/reversal checks by trigger name; -27's `enforce_ledger_shortfall_source` also precedes it. The new trigger sees the statement's inserted rows. Its correctness does not require VALUES rows to fire in a particular application-specified sequence: a pending parent is invalid however its queued reversal rows are ordered. Multi-row inputs can fail an earlier inherited guard before reaching this one.

## N4 — predicted: design, rulings and bypass inventory

The source implements U/L as additive records pointing at payments. It does not choose a customer from fuzzy candidates or automatically post suspense to revenue. Resolution evidence is required, but the database cannot establish that an operator's stated reason is true.

| Attempt | Evidence / assessed defense |
|---|---|
| Spend a receipt twice, including payment + disposition | 00 P/X/O; 03 multi-row/CTE/COPY. Datewise upper and lower cap under receipt lock. |
| Out-of-bounds payment/effective date, missing reason/user, wrong tenant | 00 P/T/O: CHECKs, explicit receipt reads, immutable linkage, composite tenant keys and RLS. |
| Provider transaction twice, or assigned late | 00 U/P; 03–05. Shared provider namespace lock, late-write check and READ COMMITTED pin. |
| Wrong pledge customer/agency or ignored bill restriction | 00 L: identity checks and restriction inheritance. |
| Pledge ended twice, early lapse, error-recorded pledge paid | 00 L; 03. Unique ending event, date/pay-by checks and payment/event handshake. |
| Agency money to customer/another agency; customer money to agency | 00 G and 07. Typed payment/credit/reissue lineage determines refund agency. |
| Retired agency revived; agreement edited | 00 A; 03 owner controls. Immutable terms and irreversible retirement. |
| App/core/owner or stronger isolation | 00, 03–06, 08. Core cannot write; owner is not generally exempt from semantic checks; read-under-lock writers reject stronger isolation. |

Pledges do not cap agency remittances at the promised amount. Their paid-in-full state precedes terminal events in the reader. An agreement is selected by the database for the pledge date; the caller cannot supply or later rewrite its agreement/pay-by terms. These choices agree with the design and are covered by 00 A/L.

CI-053's implemented holding/resolution paths and Ryan's 11-07 refund rule are consistent with the source within L5/L6. CI-056's queues and dates provide the record-side inputs; actual operator escalation, reporting and disconnect pause are still core/-26 integration work. A successful SQL battery does not prove those operational effects.

I do not elevate L1–L6 into new blockers: L1 candidate quality, L2 jurisdictional protection evaluation, L3 remittance batching, L4 close-snapshot integration, L5 agency deposits and L6 untyped credit origins are explicit scope boundaries. DECISION-LOG 2026-11-07 expressly accepts L5/L6 and retains the core's agency-refund obligation. None would excuse the formerly silent L7 loss; that path is now guarded.

## N5 — predicted: -23/-27 composition, locks and invariants

**Evidence:** 00, 02–08, 09–11, 13. The patch does not reissue an existing -23/-27 position, cap or recorded-order function. New inputs are ordinary payments and ledger rows, so inherited behavior still governs them. 07 specifically checks that a previously paid-out refund remains a debt after a misposting return; conservation cannot ignore that payout merely because the original payment ended.

Payment trigger order matters. `enforce_payment_immutable` validates the transition and acquires the payment source lock before `enforce_payment_suspense_pledge` calculates its share and checks the cause. On ledger reversals, inherited `enforce_ledger_reversal` takes the tree/root and source locks before the new pending check. This is why the new SELECT-only pending trigger does not need a second mutex. -27's shortfall source checks still participate; new receipt provenance grants no exemption from them.

Receipt-cap writers take the receipt advisory lock before checking the projection. Provider and pledge writers have their own existing handshakes. I found no new cap-writing path that calls the projection without its ordering lock. The exposed read/check helpers are not standalone write authorization.

The ending rules read the reversal tree under the inherited payment lock. They do not newly acquire the receipt lock. A misposting disposition takes the receipt lock and reads an already-ended payment without acquiring its payment lock; terminal immutability makes that usable without adding an opposite lock order. An uncommitted ending can produce an immediate refusal and retry rather than a wait for a newly eligible return. The frozen SU13–SU15b source explicitly covers the new ending/refusal and late-NSF-code cases. I did not execute or independently reproduce those interleavings; single-session probes are not race evidence.

There is no universal deadlock-free ordering for arbitrary multi-row transactions across unrelated objects. The documented 40P01/40001 retry contract remains necessary. The new trigger adds no lock acquisition. The stronger-isolation probes 04/05 demonstrate the pin's expected refusals, not serialization under simultaneous writers.

`assert_suspense_pledge_guard_invariants()` checks listed trigger definitions and ALWAYS state, required table policies/FORCE RLS, specified role grants, validated constraints, valid indexes, required NOT NULL columns, body hashes/attributes and write-helper EXECUTE. Both new functions are in the manifest; the missing-helper `coalesce(..., false)` repair remains. 00 I and 06 supply runtime catalog controls.

These are required-object checks, not a semantic proof, not an exhaustive whitelist of all possible database objects, and not an exhaustive monitor of every reader's grants. The function's “every guard” wording should be read as the listed -24 guards. The new trigger's dependence on inherited ledger/table permissions is also protected by the earlier role invariants, which the patch tail invokes; -24's manifest alone is not a replacement for those checks.

## N6 — executed source assessment; database results predicted: tests and integration

The r11 mutation targets visibly correspond to the reported repairs: M145/M146 coded mixed reversals, M149 absent standing bounce, M150/M151 untyped subtree versus its undo, M152 pending reversal, M155/M156 terminal births, M157 recorded code and the reader-coordinate mutations. P12a preserves the deliberate whole-reversal R10 route. M98's named check is now P10a. I found no additional concrete wrong-reason catch in the reviewed changes. The author-reported 161 catches remain unverified here; I did not import or execute the mutation runner.

Permanent coverage still worth adding: S1's two oracle cases; receipt-funded deposit variants in 02; role/replica/COPY controls in 08; concurrent pending reversal versus posting, and return versus a new receipt spend after an NSF ending. Existing SU13–SU15b materially improve r10 but do not demonstrate every permutation. Avoid describing that finite set as exhaustive concurrency proof.

The frozen CI diff adds -24 after pending -25/-26, includes its battery/races/invariant, and ports -23 agency fixtures to name their agency. -30 is in the base and absent from PENDING as described. These are source integration checks only. I have not claimed strict application twice or an executed full CI pass; 00 and 06 are the supplied SQL checks for an author-prepared frozen-r11 clone.

## Probe index

All paths below are under `codex-r11-probes/`; each uses a separate fresh clone.

| File | Purpose |
|---|---|
| 00-frozen-battery-coverage.sql | Exact frozen battery assertions, with caught-error SQLSTATE/message notices added |
| 01-nested-nsf-conservation.sql | S4c double-counted nested NSF and missing link-only NSF seed |
| 02-deposit-and-ending-orders.sql | Actual receipt deposit payments, pending guard, coded whole/split endings, late NSF code, terminal rules, replica mode |
| 03-statement-shapes-and-roles.sql | Multi-row/CTE/COPY caps, app/core/owner, pledge/event CTEs |
| 04-repeatable-read.sql | Stronger-isolation refusal controls |
| 05-serializable.sql | Stronger-isolation refusal controls |
| 06-catalog-contract.sql | Invariants, trigger order, effective role grants and live definers |
| 07-composition-controls.sql | Refund/debt and receipt-deposit composition |
| 08-pending-statement-shapes.sql | Multi-row and COPY pending reversals, owner ending/late-code rules, tally_void early return, core denial |
| 09-reader-business-date.sql | Earlier undo-interval counterexample remains repaired |
| 10-reader-recorded-time.sql | Earlier recorded-time counterexample and return ordering remain repaired |
| 11-reader-omitted-history.sql | Historical share remains visible before later undo/bank return |
| 13-nsf-statement-shapes.sql | Mixed multi-row ledger, dependent ending/return CTE, duplicate COPY return |
