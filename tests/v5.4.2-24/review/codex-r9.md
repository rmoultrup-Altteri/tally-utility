# Codex review — v5.4.2-24, round 9

**Verdict: not yet.** One blocking prediction: the new returns-due reader uses the final misposted share at historical coordinates where that share is different. It can both double-recognize money and omit money. The earlier write-side fixes remain present; this is a new read-side composition defect. All database outcomes below are **predicted**, not executed.

## N1 — executed: identity and scope

Checked the brief's checksum and all six frozen checksums before source review. All matched:

| File | md5 |
|---|---|
| review-brief-24-r9.md | a4f09bb6e7cad8e2c4817c8c3d06a6aa |
| patch-24-frozen-r9.sql | 9b00e46bfab97e0d83a01870f820147c |
| battery-24-frozen-r9.sql | e917ec270f043111f73b5ac0c0cd780b |
| suspense-24-frozen-r9.sh | 55c631999a54b336848e18cb06c80331 |
| mutations-24-frozen-r9.py | 18f737f9519d66c17e95c37170d11266 |
| ci-24-frozen-r9.diff | c343828be614b5abf30a15944402ee0c |
| r8-to-r9.diff | b512ae0bf4744162f3b136fd5878efbe |

Source only. No Docker, psql, CI, races or mutation runner executed. No `opus-*.md` or `fable-*.md` read. Read the r2–r9 plans first, then the frozen changes, relevant inherited cash source, my r6 review/probes and selected author r6 probe output. Consulted tally-utility's design, inventory and DECISION-LOG, and GBM's CI-053, CI-056 and the two specified workflows. This is a review against those supplied rulings, not independent legal advice.

Static verification found **30 matching embedded function-body md5s** and **282 battery assertion call sites**. These are file checks, not database passes. The brief's strict double apply, 282 battery results, 24 race results, 119 mutation catches and 63 CI steps are author-reported, not reproduced here. The historical author logs inspected confirm the original r6 recorded-time and missing-helper observations; they are not r9 execution evidence.

Every database prediction below maps to a file in [codex-r9-probes](codex-r9-probes/). Run each file independently as owner on its **own fresh clone with frozen r9 applied**, with clone TEMP revoked as the brief requires. Files end in ROLLBACK; caught errors print SQLSTATE and message with RAISE NOTICE. Probe 02 catches COPY's own server exception and prints it, without trusting LAST_ERROR_SQLSTATE. It uses COPY FROM PROGRAM with a fixed generated CSV payload, requiring the owner/superuser environment described by the brief. No probe creates, drops or alters a cluster role. A failed assertion with ON_ERROR_STOP aborts that file; disconnect rolls its transaction back.

## B1 — predicted: the returns-due reader is not a historical money position

**Source:** frozen patch lines 906–933 (`suspense_misposted_share`) and 1396–1423 (`suspense_misposting_returns_due_as_of`). The helper deliberately sums the final tree, with positive-NSF subtrees pruned. The reader filters by the terminal status timestamp and the named cause's business date, but passes neither coordinate to the share calculation. It does not check the cause's `created_at`, the later tree dates, or later tree timestamps.

The moved walk retains the old arithmetic and the three planner pins. That is suitable for the existing **write guard**, which separately requires a return on/after the entire tree's latest date and no earlier than its latest recording (lines 1022–1061). The reader has no equivalent condition. A tree being immutable **now** does not make its final sum correct at every earlier coordinate.

Three independent probes make the distinction concrete, without disabling any trigger:

| Probe | Admitted history and requested coordinates | Predicted r9 result |
|---|---|---|
| [01-reader-business-date.sql](codex-r9-probes/01-reader-business-date.sql) | Frozen P14h's shape: receipt/payment 100 on March 10; reversal +100 March 11; undo −100 March 12; second reversal +100 March 13. Terminal status names the first reversal. Read March 12 at current knowledge. | Receipt held 0; payment received 100; **returns due also 100**. The same receipt is recognized as 200 across payment and reconciliation suspense. A March-13 return removes the due row on March 13 but leaves the March-12 error. |
| [07-reader-recorded-time.sql](codex-r9-probes/07-reader-recorded-time.sql) | Owner history load: reversal recorded at `clock_timestamp()`, status timestamp left at transaction start. Read March 11 as known at that start. This is the already established r6 prerequisite. | Receipt held 0; payment received 100; **returns due also 100**, although the supporting ledger reversal was not yet recorded at that instant. A later correctly recorded return does not repair the earlier reading. |
| [09-reader-omitted-history.sql](codex-r9-probes/09-reader-omitted-history.sql) | Frozen P14b's shape: reversal March 11, undo March 12, bank take-back March 13. Final misposted share 0. Read March 11 at current knowledge. | Receipt held 0; payment received 0; no bank take-back effective yet; **no returns-due row**. The 100 waiting between reversal and undo is absent from all three positions. |

These are errors in the proposed reconciliation/operational surface, not a demonstrated new way to spend the receipt twice. Probes 01 and 07 explicitly confirm the earlier return-writing refusals still hold (23514 by date, 40001 at transaction start, 23514 for a chosen earlier timestamp). Their final-coordinate controls predict correct ordinary totals. The recorded-time example is a superuser history load; the business-date examples reuse ordinary admitted battery trees.

**Impact:** round-8 Opus S1 is only partially closed. Today's simple unreturned reversal is surfaced, but the promised date/recorded-instant reader can manufacture a liability alongside money still on a customer's account, or hide the liability before a later undo/bank return. Adding its `owed` to suspense held for reconciliation therefore does not compose with -23's coordinate-aware received position. This violates the historical reconciliation purpose of CI-053 and can misstate age/service-level reporting under CI-056.

**Required correction:** distinguish the final share eligible for a new return from the amount actually in transit at the requested coordinates. Derive the latter from ledger evidence effective and recorded by those coordinates, retaining the NSF/sign/lineage semantics, and subtract a return only once it is visible at both coordinates. Keep the final-share helper and its existing write preconditions if useful. Simply waiting until the entire tree is visible prevents the double count but still drops the legitimate March-11 interval in probe 09. Do not fix this by only adding `status_cause.created_at <= p_recorded_at`; later descendants also matter. Add both directions of the temporal tests before calling this an as-of reconciliation reader.

## S1 — predicted: conservation coverage excludes the new position

**Source:** battery S4b, lines 1172–1210, adds receipt held, payment received and non-misposting dispositions, then checks only `> receipt.amount`. It never calls the new returns-due reader. S8–S8e cover an ordinary outstanding final share, an already returned payment, a final zero share, a date before the named reversal, and shared arithmetic. None checks the intervals exposed by B1.

**Evidence/probes:** 00 carries the frozen battery with caught-error logging added; 01, 07 and 09 expose the missing coordinates. The old S4b operands are respectively 100, 100 and 0 in these examples, so its upper-bound condition cannot identify the new reconciliation errors. The omitted-history case also needs a lower-bound/equality expectation for a fully classified, posted fixture.

Extend conservation coverage to the new position. Use explicit bank-outflow classification and distinguish pending/unposted money and posted refunds/shortfalls rather than mechanically requiring the existing partial expression to equal every receipt. At minimum, require exact totals for the three simple B1 fixtures. Add targeted temporal-reader mutations alongside M117–M119. This is one test gap accompanying B1, not a second independent money defect.

The six strengthened refusal messages do address round-8 Fable S1: they now constrain the calculated share, rather than merely demanding rejection of some wrong amount. M117–M119 each target a real new filter. I found no new concrete wrong-reason mutation catch in the reviewed changes. That is not an execution of, or exhaustive certification of, all 119 mutations. The old redundant M74 is removed; its claimed independent protection is no longer counted.

## N2 — predicted: closure of earlier findings

Coverage refers to the r9 probe filenames; `00` is the frozen battery, not the old r6 battery.

| Prior finding | Assessment / evidence |
|---|---|
| r8 Opus S1, money waiting for return invisible | Partially closed by the new reader; B1 remains for historical coordinates. 00 S8, 01/07/09. |
| r8 Opus S2 / Fable N1, old “at most” wording | Corrected in the table comment, guard explanation and design section 2.3. Exact comparison remains. 00 P9b3/P9b3b. |
| r8 Fable S1, refusals do not prove the share | Six message checks strengthened as requested. 00 P9b3b/P13/P14b/c/e/f. |
| r7 Opus S1, short return strands remainder | Exact-share comparison and once-only return remain. 00 P9b3b and admitting partners. |
| r7 Opus S2, chosen-time branch untested | P14i4/M116 retained; 07 independently checks 23514. |
| r6 Codex B1, return recorded before ledger evidence | Closed on writes: maximum tree recording checked, with retry/chosen-time branches. 00 P14i family; 07. B1 here is a new reader failure, not re-admission of that write. |
| r6 Codex S1, redundant reversal-date mutation | Separate check and M74 removed; full-tree date check remains. 00 P9b2/P14h; 01. |
| r6 Codex S2, missing inherited helper overlooked | Required EXECUTE test now coalesces NULL to false. 00 I9d2 removes `cash_source_lock_key` locally and expects refusal. |
| r6 Fable conservation request | S4b added for old operands; incomplete for r9's new operand (S1 above). |
| r5 negative-NSF undo; r5 Codex business-date bound | Both recursive legs prune only positive NSF rows; complete-tree maximum date remains. 00 P14e–i; 01. |
| r2–r4 partial bank return, reversal/undo trees, nested NSF, return before payment | Arithmetic, payment-date bound and exact-share behavior retained. 00 P13/P14/P9b11–12; 06. |
| r1 provider duplicates, late assignment, equal UUIDs, instrument drift, isolation | Shared namespace lock, internal READ COMMITTED pin, table-specific self exclusion and UPDATE checks retained. 00 U8/P5e; 03/04. |
| Earlier recorded-order, release order, self-exclusion, NaN, clocks | All corresponding clauses remain. 00 O/P/U/L; no claim to fix inherited general NaN behavior outside -24. |
| Earlier tenancy with FKs off, settings history, bill restriction, retirement reuse, invariants | Explicit tenant checks, CHECKs, restriction equality, partial active-name index and expanded manifests retained. 00 O3/S/L18/A/I; 02/05. |
| Earlier test labels, refund-trace coverage | Corrected labels retained. The shortfall-reissue branch has behavior tests, still no dedicated mutation; the 1,000-step trace bound remains disclosed as untested. 00 G; 06. |

No other earlier concrete counterexample was found reintroduced. This does not assert exhaustive safety of all histories.

## N3 — predicted: design, rulings and attempted bypasses

Apart from B1, the source implements the intended additive record layer: unidentified receipts, explicit operator resolution, typed agency pledges and settings/readers. No new writer selects a customer from the candidates table or allocates suspense to revenue. These are source observations; intake identification and the operator's reasoning are not facts the database can verify.

| Attempt / requirement | Source assessment and runnable coverage |
|---|---|
| Spend a receipt twice | AFTER INSERT cap on payments and dispositions, cumulative at every money date, under receipt lock; lower bound retained. 00 P/X, 02 multi-row/CTE/COPY. B1 is separate historical reporting. |
| Wrong payment date/effective date, tenant or missing reason/user | Insert/update guards, immutable linkage, composite FKs and CHECKs. 00 P3–P5/T/O3. |
| Record provider transaction twice | Shared receipt/payment namespace and lock; late assignment checked; incoming payments distinguished from refund namespace. 00 U8; 03/04. |
| Wrong agency/customer pays pledge, pledge ended twice, premature lapse | Identity equality, one-event uniqueness, computed pay-by and UTC date bounds. 00 L7/L10–L14. |
| Payment names pledge recorded in error | Payment/event handshake and checks both ways. 00 L; 02 dependent writable CTEs in both orders. |
| Agency pays above pledge | Deliberately accepted; actual money is not capped at the promise. 00 L12. |
| Caller supplies/edits agreement or pay-by; resurrects agency | Database chooses and freezes pledge terms; setup tables permit only stamped withdrawal/retirement. 00 A/L; 02 owner refusals distinguish trigger protection from app ACLs. |
| Agency refund to customer/wrong agency, customer refund to agency | Source agency traced through payment, overpayment, refund reissue and shortfall reissue; refund agency must match. 00 G1–G7. Subject to accepted L5/L6. |
| Reader boundaries | 08 covers status beyond recording, date before reversal, void, return code, tenant argument/RLS, core access, exact service-level boundary and NULL coordinate. 07 covers unknown service level and later recording; 01 same-day return. |
| Roles/isolation/statement shape/history | 00 app/owner and replica-mode history cases; 02 owner/app/core, multi-row, dependent CTE and server-caught COPY; 03 REPEATABLE READ and 04 SERIALIZABLE; 07 owner history load. |

Pledge state precedence remains void, paid, effective event, no agreement, overdue, open (00 L8–L15). Reader data is only the record side of CI-056: operator queues, disconnect execution, statutory rule evaluation and remittance matching remain core work. Missing settings have the documented distinctions: aged-receipt service-level evaluation raises, retention can be unknown, and the new returns-due list retains money with NULL service-level flags (00 S; 07/08).

Ryan's 11-07 agency-refund ruling is implemented on the typed paths above. DECISION-LOG explicitly accepts L5/L6 as limits, so I do not turn them into a new blocker or claim universal routing enforcement.

## N4 — predicted: -23/-27 composition and concurrency

-24 does not reissue an existing cash/shortfall function. The extracted share walk preserves the final-tree rule and planner settings. However, additive DDL still must compose semantically: B1 pairs the new reader with -23's coordinate-filtered `payment_position_as_of`/`payment_draws_as_of`, and they disagree about where the same money is. Probe 05 prints installed trigger order and inherited lineage guards; 06 covers ordinary overpayment-credit, posted-refund/shortfall and deposit-posting composition. The posted refund remains an expenditure with debt/shortfall; it must not be counted as newly created money while ignoring that debt. The deposit control is a payment-ledger branch, not certification of -15's entire deposit lifecycle.

Trigger timing/order matters. The inherited BEFORE birth/stamp/freeze/immutability rules compose with `enforce_payment_suspense_pledge`; the receipt cap runs AFTER INSERT, when statement inserts are visible. The statement-shape controls in 02 are important here. The CI diff ports agency identity into -23 fixtures and adds -24 after -25/-26/-30; I inspected that integration without running it.

Both receipt-cap write call sites acquire the receipt advisory lock before cap/order reads. Provider checking takes its own namespace lock and pins isolation internally. Pledge insertion/agreement selection serialize with agency retirement/withdrawal; payment INSERT and pledge-event INSERT share the pledge lock. The terminal payment-status path does not add a pledge lock on every update, but pending payment existence already bars recorded-in-error, late payment after lapse/withdrawal is allowed, and paid outranks those events. SU3 tests pending insertion, not posting-versus-lapse.

I found no additional unprotected receipt-cap write path in source. 00/02/03/04 are single-session probes of guards and isolation requirements; 05 exposes definitions/order. Frozen SU1–SU12 are reviewed schedules, **not executed concurrency evidence**. A source-only review cannot certify their waits or all interleavings. Their fixed sleeps are visible in source; the brief's unrelated race failures do not establish an additional -24 bug.

The lock order is a per-path rule (tenant close head, inherited cash locks, then receipt/pledge), not a total ordering across arbitrary multi-row transactions. The documented 40P01/40001 retry requirement remains necessary. The cap helper itself is read-only and assumes its writer holds the lock; invoking it directly does not authorize a write.

## N5 — predicted: invariant scope and known limits

The invariant enumerates required trigger definitions/ALWAYS enabling, tenant policy/FORCE RLS, table and stamp-column grants, validated constraint definitions, valid unique indexes, function bodies/attributes, required NOT NULL columns and app helper EXECUTE. New helper/reader bodies and attributes are listed; the shared helper is in the app EXECUTE list. The missing-helper NULL case is repaired. Coverage: 00 I and 05; static body hashes are N1's executed file check.

These are required-item checks, not equality of every possible catalog object or a semantic proof. Inherited helper bodies are not all pinned by -24. Reader EXECUTE grants to both roles are not exhaustively monitored by the app-write-helper list; 08 exercises the new core read path. A matching body hash can preserve B1 exactly. I found no new concrete catalog bypass to elevate alongside it.

L1–L6 are not independently blocking for this scoped patch: L1 candidate quality and L3 batch matching remain intake/core duties; L2 statutory pledge protection remains rule/core work; L4 the close snapshot lacks a suspense line; L5 deposit returns and L6 untyped credit origins retain Ryan's accepted routing limits. Probes 00 C/S/G/L and 06 cover the implemented boundaries, not the deferred workflows. **L4 does not excuse B1:** the substitute reconciliation readers must still provide coherent figures at their stated coordinates. Close/report consumers must include returns due once that reader is corrected; held alone intentionally excludes that money.

Only `codex-r9.md` and the ten SQL files under `codex-r9-probes/` were written. All database findings await the author's probe runs.
