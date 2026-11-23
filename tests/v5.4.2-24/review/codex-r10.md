# Codex — v5.4.2-24, review round 10

**Verdict: not yet.** The three concrete round-9 temporal counterexamples are addressed. I do not accept proposed L7 as a harmless limit: it permits an ordinary application's terminal update to make real misposted money unreturnable and invisible. The NSF exception also relies on classification that the status/cause does not establish. One blocking classification finding, two should-fix items, and scoped closure notes follow.

Every database outcome here is **predicted**, not executed. The author must run the probes before treating a prediction as confirmed.

## N1 — executed: frozen identity and scope

Checked the brief's checksum first, then all six frozen checksums; all match:

| File | MD5 |
|---|---|
| review-brief-24-r10.md | 2c1baad89f2410260629edbf17621471 |
| patch-24-frozen-r10.sql | 72fdcfdcb52c94098c4e54e8f649b139 |
| battery-24-frozen-r10.sql | e7bbce6f85f8c70059aedcab4f104d6f |
| suspense-24-frozen-r10.sh | 55c631999a54b336848e18cb06c80331 |
| mutations-24-frozen-r10.py | b15bec4ea9869b8f1cc4288ba2d3e3b8 |
| ci-24-frozen-r10.diff | c343828be614b5abf30a15944402ee0c |
| r9-to-r10.diff | 31b5de1846a33de65bac7758a96c7670 |

Read the r2–r10 plans before reviewing implementation, especially the rejected alternative in r10. Consulted the design, source inventory, DECISION-LOG, GBM CI-053/CI-056 and the specified workflows, the permitted Codex reviews, and author output for the earlier Codex temporal probes. No other reviewers' review files were read. This assesses the supplied rulings; it is not independent legal research.

Source checks found **31 matching embedded function-body hashes** and **309 battery assertion call sites**. Those are executed file checks, not database passes. Strict apply twice, 309 battery results, 24 race results, 142 mutation catches and 63 CI steps remain author-reported. No Docker, psql, CI, race script or mutation runner was executed. No agents were delegated work.

Only this review and SQL files in [codex-r10-probes](codex-r10-probes/) were written. Each probe is independently run as owner on its own fresh clone with frozen r10 applied. Revoke clone TEMP as instructed by the brief before patch application. Existing app/core role switches exercise their privileges; no probe creates, drops or alters a role. All files end in ROLLBACK; all caught errors print SQLSTATE and message through RAISE NOTICE. COPY exceptions are caught at the server and print COPY's own error, without LAST_ERROR_SQLSTATE. COPY FROM PROGRAM uses a fixed, generated printf payload and requires the described superuser environment. An unexpected assertion failure under ON_ERROR_STOP aborts the file; disconnect rolls its transaction back.

## B1 — predicted: payment-level classification still loses money, and an NSF label does not resolve it

**Source:** frozen patch lines 755–778 (code admission), 936–951 (pruned final share), 1006–1013 (NSF return eligibility), 1422–1495 (dated share and due-list exclusion). Inherited -23 `enforce_payment_immutable`, particularly its `nsf` cause test, checks a direct NSF child and a fully reversed posting entry; it does not require that named NSF child to retain a positive balance.

### Proposed L7: not acceptable under the supplied rule

[01-coded-mixed-reversals.sql](codex-r10-probes/01-coded-mixed-reversals.sql) constructs the brief's example as `tally_app`: receipt/payment 100, plain reversal 60 representing a misposting, plain reversal 40 representing the bank's take-back, then `reversed` with R01. The calculated share is 100, so the new partial-share check admits the code. Predicted results:

- Receipt held = 0; customer's received = 0; returns-due has no row.
- Returning the real misposted 60 is refused because of the code.
- Paying that 60 to the correct customer is refused by the receipt cap.

The ledger does not type the two purposes, so the database cannot *calculate* the correct 60 from this representation. That is precisely why it should not accept a terminal representation that silently chooses “all 100 went to the bank.” The code can describe one part; it is not evidence that every plain reversal is a bank take-back.

This is the same CI-053 failure used to justify the r8 exact-return fix and r10's partial-NSF fix: retained money reaches neither an account, a receipt holding, nor a return-due queue. It is not merely an optional workflow outside -24. Unlike L5/L6, no supplied decision accepts this exception. My answer to direct question 1 is **no**.

### The NSF exception has the opposite ambiguity

[02-undone-nsf-ending.sql](codex-r10-probes/02-undone-nsf-ending.sql) builds an NSF +100, its undo −100, and a new direct plain reversal +100. It ends the payment `nsf` naming the **undone** NSF row, with R01. Predicted: the ending is admitted; share = 100; due = 100; a return of 100 and a new customer's payment of 100 are admitted.

If the last plain reversal represents a misposting, that return is correct. If it represents the bank take-back described by the code, it gives back money the bank took. The stored shape accepts both readings. The code is barred from giving money back with `reversed`, but ceases to bar it solely because the terminal status names an old, undone bounce. Thus “the code is the bounce's” is an assumption, not a property established by the new guard. This is not a claim that the numeric receipt cap itself is exceeded.

The rejected rule in the r10 plan was rejected because an NSF row plus a coded plain reversal can represent two bank take-backs. Testing `status = 'nsf'` does not in itself remove that ambiguity, especially when its cause was undone. Checking only that some positive NSF row exists would repeat it.

[08-nsf-subtree-stranded.sql](codex-r10-probes/08-nsf-subtree-stranded.sql) probes the other conservative edge: NSF +100, undo −100, then a plain misposting +100 **under that undo**, and terminal NSF. The pruned share and due are predicted zero; the receipt and customer hold zero; returning 100 is refused. The file attempts the corrective undo after the ending and prints the inherited error (expected 23001). The r6 plan's “file it again under the posting entry” escape requires correction **before** the terminal ending. It is not a recovery procedure for this already-ended shape. This is further classification/terminal-workflow evidence, not a separate arithmetic finding.

**Required direction:** make bank-versus-misposting attribution unambiguous before accepting a terminal receipt payment, or preserve an explicit unresolved amount and a supported correction path. A canonical rule requiring bank take-backs to be recorded as NSF, with suitable restrictions on ambiguous coded plain reversals and terminal histories, is preferable to silently interpreting a payment-level code. Typed per-reversal classification is another route. Do not simply remove NSF pruning or permit arbitrary returns: that reintroduces the earlier bank-money double-spend. Preserve legitimate 60-misposted/40-NSF behavior and fully undone-NSF/redeposit behavior in the regression fixtures.

## S1 — predicted: the documented late-code exception still breaks the historical reader contract

**Source:** frozen patch line 1480 and the reader comment. [12-inserts-and-late-code.sql](codex-r10-probes/12-inserts-and-late-code.sql), second half, loads March facts as owner, reads March 11 as known March 20, then supplies a return code now. Predicted: the identical historical coordinates change from due 100 to no row. The sampled timestamp is earlier than this transaction's start; the probe does not merely sample two different instants.

Direct question 3: **not acceptable for an as-recorded reconciliation reader**. Documenting it makes the exception visible to developers but does not restore the old recorded answer. It may be acceptable for a separately named current-classification report. It should not be silently combined with coordinate-aware cash positions as though all operands use the same knowledge cutoff.

Version the classification/code evidence and consult its recorded time, or explicitly separate current reclassification from the historical API and its reconciliation contract. Merely gating by `status_recorded_at` does not solve a code supplied after that status. This is narrower than the old r9 tree bug: the tree filtering is repaired; the mutable classification remains.

## S2 — executed source assessment; database examples predicted: conservation coverage remains selected and incomplete

S4b now includes returns due at its date/instant grid, addressing Codex r9 S1's omitted operand. S4c adds useful equality checks, but its title is broader than its test:

- It chooses seven UUIDs and March 10–20, at current recorded knowledge only.
- Its bank term is the gross sum of positive NSF rows, not their net after undos, and it has no coded-plain-bank classification.
- A selected fixture set is reasonable for a restricted conservation identity; it is not proof of the other direction for all receipt histories. There is no evidence of author intent to hand-pick a misleading pass, but these selections exclude exactly the classification/redeposit cases raised here.

Probes 01, 02, 08 and 12 cover the missing shapes. Probe 00 reproduces the frozen battery with error notices added. Expand the classification fixtures and give each an explicit expected bank outflow; sweep recorded instants as well as business dates. Do not generalize the gross-NSF expression to all receipts: an undone bounce is not still a bank outflow.

S8f–s and M120–M144 materially strengthen reader coverage: status independence, date/recorded filtering, restart of `since`, tenant filtering, ordering, unknown settings and the threshold are represented. M119 disappeared with its filter; the stated M124 equivalence is consistent with the return-code CHECK. M77 now targets the NSF-aware clause. I found no additional concrete wrong-reason mutation catch in the reviewed changes, but did not execute or certify all mutation outcomes. The removed redundant M74 stays removed. Shortfall-reissue behavior still has no dedicated mutation; the trace-depth bound remains disclosed as untested.

SU1–SU12 are unchanged and do not exercise an NSF return. Add schedules for an NSF ending versus its return, a late NSF code versus a return, and an NSF return versus a new spend; include retry/error observations. Probe 13 covers a multi-row tree, dependent writable CTE ending/return, and COPY duplicate return, **not** those concurrent schedules.

## N2 — predicted: closure of earlier findings

| Prior finding | Round-10 assessment and runnable evidence |
|---|---|
| Codex r9 B1 / Opus r9 S1 / Fable r9 S1, historical tree share | The specific counterexamples are closed: probes 09–11 now expect no due during the undo interval or before the reversal recording, and due 100 in the interval before a later undo/bank return. Probe 00 S8j–s covers restart, dates and recording. S1 above remains the separate code-classification exception. |
| Opus r9 S2, partly misposted NSF payment | The ordinary 60-misposted/40-NSF example is fixed: 00 P15–P16b, O1i and 13. Not fully closed as a general “nothing stranded” claim: B1 and proposed L7 remain. |
| Codex r9 S1 / Opus r9 S3 / Fable tests | Omitted due operand and targeted reader coverage repaired; S2 records the remaining scope. |
| r8 wording/exact-share refusal checks; r7 short return | Exact equality, once-only return, and messages constraining the calculated share remain: 00 P9b3b/P13/P14. |
| Codex r6 B1 and chosen-time follow-up | Full-tree max recorded instant still protects writes, both 40001 and chosen-time 23514: 10 and 00 P14i family. |
| Codex r6 S1/S2 | Redundant separate date guard/M74 stay removed; missing helper EXECUTE uses coalesce(false): 00 I9d2 and 06. |
| Codex r5 B1; negative-NSF undo | Full-tree date bound and sign-sensitive pruning remain: 09, 00 P14e–i. B1 here questions terminal classification, not removal of those bounds. |
| r1 provider duplication/late assignment/equal UUID/isolation/instrument drift | Clauses remain; 00 U/P, 03–05. |
| r1–r4 recorded/release ordering, self-exclusion, NaN, clocks, tenant history | Corresponding guards remain: 00 O/U/P/L/T and 03–05. |
| Earlier pledge restriction, retirement reuse, agreement and refund routing | Retained: 00 A/L/G, 03 and 07. |

No other earlier counterexample was found reintroduced. That is a source review conclusion, not proof over every history.

The as-of walk filters the payment, root and each reachable descendant at both coordinates, groups movements by date, and starts `since` after the last nonpositive daily net, clamped to payment_date. Grouping treats same-day changes as one dated state. Pruned branches stay pruned at partial visibility; that agrees with the conservative classification policy, not necessarily the economic purpose of every descendant (B1). The final-share guard remains separate and still requires the return to follow the entire tree. Probe 00 provides the frozen controls for those distinctions; 09–11 independently repeat my prior counterexamples.

## N3 — predicted: design, rulings, roles and bypasses

The source implements the additive U/L record layer and typed refund routes, subject to B1/S1 and the accepted limits. No writer picks a customer from candidate matches or posts suspense to revenue. Intake truth and the operator's stated reason remain facts outside database knowledge.

| Attempt | Source assessment / probe |
|---|---|
| Spend a receipt twice, including multi-row/CTE/COPY | Cumulative date cap and recorded-order checks remain under receipt lock; 00 P/X/O and 03. B1 concerns whether released money actually belongs to the receipt. |
| Payment date/effective date outside receipt bounds; another tenant; absent reason/user | Insert/update guards, CHECKs, composite keys and fixed linkage: 00 P/T/O. |
| Duplicate provider transaction, including late assignment | Namespace lock, internal READ COMMITTED pin, table-specific self exclusion: 00 U/P, 04–05. |
| Pledge paid by another customer/agency; bill restriction bypass | Identity and restriction checks: 00 L7/L18. |
| Pledge ended twice, early lapse, payment names error-recorded pledge | Unique event, pay-by checks, payment/event lock handshake: 00 L and 03 CTEs in both orders. |
| Agreement chosen/edited by caller; agency resurrected | DB selection and immutable terms/retirement: 00 A/L; 03 owner controls distinguish guards from application ACLs. |
| Agency refund to customer/other agency; customer's refund to agency | Typed payment/credit/reissue lineage: 00 G and 07. |
| App/core/owner; stronger isolation; history load | 00, 03–07 and 10/12. Core write privileges are refused; guarded writers pin READ COMMITTED. |
| NSF return statement shapes | 13: legitimate split, multi-row ledger, dependent CTE, duplicate COPY with its own error. |

Direct question 2 (terminal INSERT): probe 12 predicts `tally_app` is refused by -23's birth guard (23514). A superuser owner can insert the already-reversed coded payment, consumes the receipt, and cannot subsequently post it; no ledger or due row exists. This does **not** bypass the partial-code UPDATE check by constructing a mixed tree. It **does** matter to a history importer: terminal-at-birth is not a usable load order for real suspense money. I treat the inherited superuser birth exception as a history-load limitation rather than a new app exploit; document/enforce pending → ledger → status for receipt imports, and validate the imported totals. The claim “for every role” must not be read as proof that arbitrary superuser history loads conserve cash.

Ryan's 11-07 refund-to-agency ruling is covered on the typed routes. L1 candidate quality, L2 statutory rule evaluation, L3 batch matching, L4 close snapshot integration, and L5/L6 deposit/untyped-credit routing are not new independent blockers for this scoped record patch. DECISION-LOG expressly accepts L5/L6. None excuses a silently lost amount in an implemented suspense resolution path. CI-056's operational pause/reporting still requires core work; the queue is its input, not an executed disconnection guard.

## N4 — predicted: -23/-27, trigger order, concurrency and invariants

-24 reissues no existing cash/shortfall function. The inherited positions, caps and recorded-order guards therefore retain their definitions, but their composition with the new reader and NSF-return policy matters (B1/S1). Probe 07 covers credit/refund/shortfall/deposit composition; 00 G covers typed agency reissues. A posted refund and associated debt must not be omitted from a conservation argument simply because the original payment was later taken back.

Trigger order matters: inherited birth/stamping/freezing precede the relevant new checks; `enforce_payment_immutable` validates and locks a status transition before `enforce_payment_suspense_pledge`; receipt caps run AFTER INSERT with statement rows available. Probe 06 prints catalog definitions/order; 03/13 exercise statement shapes. CI's diff adds -24 after -25/-26/-30 and ports the -23 agency fixture. I reviewed that integration without running it.

Both receipt-cap write call sites take the receipt lock. A code change takes the same receipt lock as a return; terminal status changes take the inherited payment lock. A disposition reads the payment under the receipt lock, without adding a payment lock. That avoids introducing an opposite payment-lock acquisition there; it does not mean it waits for every uncommitted terminal move. Whether the return sees an eligible committed ending, refuses, or retries depends on the schedule. NSF changes without a code do not themselves add a receipt lock. The recorded-order check now includes NSF status time. I found no additional concrete unlocked-cap write path; I do **not** certify the untested NSF interleavings. S2 requests them explicitly.

Provider namespace and pledge/agency handshakes remain. Arbitrary multi-row transactions have no universal row ordering; the documented 40P01/40001 retry contract is necessary. Helpers that only check a cap are not standalone write authorization. Probes 04/05 test stronger-isolation refusal, not serialization under real simultaneous sessions.

The invariant checks required trigger definitions/ALWAYS enabling, tenant policies/FORCE RLS, specified grants, validated constraints, valid unique indexes, NOT NULL, body hashes/attributes, and required write-helper EXECUTE. The new as-of helper is body/attribute-pinned. The required-EXECUTE missing-helper repair remains. Probe 00 I and 06 exercise catalog controls. These are required-object checks, not semantic correctness proofs or a full comparison of every ACL/catalog object. In particular the write-helper EXECUTE list does not promise exhaustive monitoring of reader grants, and -24 does not pin every inherited helper body. Matching all 31 hashes preserves the classification and temporal exceptions too.

## Probe index

| File | Purpose |
|---|---|
| 00-frozen-battery-coverage.sql | Frozen r10 battery, adding SQLSTATE/message notices only |
| 01-coded-mixed-reversals.sql | Proposed L7, app path and stranded 60 |
| 02-undone-nsf-ending.sql | Fully undone NSF cause; whole-share coded ending and re-spend |
| 03-statement-shapes-and-roles.sql | Multi-row/CTE/COPY caps, owner/app/core, pledge-event CTEs |
| 04-repeatable-read.sql; 05-serializable.sql | Isolation controls |
| 06-catalog-contract.sql | Inherited catalog/trigger checks |
| 07-composition-controls.sql | Cash/credit/refund/deposit composition |
| 08-nsf-subtree-stranded.sql | Misposting under a redeposit, terminal recovery attempt |
| 09-reader-business-date.sql | r9 date counterexample, corrected expectations |
| 10-reader-recorded-time.sql | r9 recorded-time counterexample, corrected expectations and write refusals |
| 11-reader-omitted-history.sql | r9 omitted interval, corrected expectation |
| 12-inserts-and-late-code.sql | Terminal inserts by role; later code rewriting a past answer |
| 13-nsf-statement-shapes.sql | NSF multi-row/CTE and duplicate COPY return |

Readiness requires resolving B1's classification/terminal behavior and the historical API contract, with probes and regression expectations updated to the chosen rule. Do not interpret these unexecuted predictions as author-confirmed results.
