# Codex — v5.4.2-27, review round 4

Verdict: **ready** (source review, with nonblocking S items).

**B: none identified.** This is not confirmation of database results. The author must run the supplied probes; in particular, S1 is a prediction. I ran no SQL, Docker, psql, CI, races or mutation runner. I read no `opus-*.md` or `fable-*.md`. Only this review and `codex-r4-probes/` were written.

“Executed” below means checksum verification or source inspection, not database execution. Every database prediction is assigned a probe below. Prior author-run output is explicitly distinguished from r4 evidence.

## N1 — executed: frozen inputs and authority

The brief's MD5 matched `review-brief-27-r4.md5`, and all five frozen hashes matched before review proceeded:

| File | MD5 |
| --- | --- |
| review-brief-27-r4.md | 881c0e0706648c12ccb8912c7624e670 |
| patch-27-frozen-r4.sql | a31850a02ca0b7259da5baeb119ce69c |
| battery-27-frozen-r4.sql | 50a3895686f60bbb51733738484cc29c |
| shortfall-27-frozen-r4.sh | aa30b429d11ecb44268003c7fe608216 |
| mutations-27-frozen-r4.py | 56a61b306b3dc8f82fb2f0eb1c07c40a |
| r3-to-r4.diff | a8380a6bb640953d3f3cc98dc6d98d89 |

Authority reviewed: the design, merged r2–r4 plans, 2026-11-06 (-27 r3) DECISION-LOG entry and Kyle's 2026-10-30 credit-shortfall ruling in gas-billing-memory/application. I checked the inherited R-02 date restriction and relevant cash, share, recorded-order and credit-status functions in `sql/tu.sql`. The later decisions control older design descriptions.

## N2 — executed: disposition of my r3 findings and plan coverage

- **S1 fixed in source:** E20 calls the bill writer with the carry; E20b checks applied 20, refunded 5 from E9, remaining 5. This is the promised positive bill-use regression. Probe 00 reproduces these checks; probe 12 preserves the independent lifecycle branch.
- **S2 fixed for the repaid term:** the comment now recognizes same-transaction timestamps, J1 observes the -20 term and share 80, and M65 removes that term with J1 as its named check. I read probe 13's permitted r3 author-run output: it reports those numbers. That is r3 evidence only; probes 00 and 13 reproduce the r4 prediction. The separate source-term assertion remains questionable: see S1 below.
- **S3 fixed in source:** R5 says one local day ahead in Texas, up to two in the far west, and identifies `now()` as the transaction instant. Probe 11 retains the deterministic calendar example.
- **N1 refreshed** by this review's checksum table.
- **N2 refreshed:** the earlier carry-birth and privilege fixes remain in source; no reversal of the earlier dispositions found.
- **N3 superseded as planned:** the old timestamp comparison is replaced by the database-written fact, and the second date reading is removed. The DECISION-LOG explicitly explains building option 2 instead of the earlier recommendation of option 1. This is a documented design change, not an unnoticed half-implementation.
- **N4 remains predictions:** see the probe inventory; no earlier result is promoted to an executed r4 result.
- **N5 retained with the limitations below:** lock ordering, isolation restriction and structural invariants remain; concurrency tests have not been reproduced.
- **N6 retained with r4's date rule:** R1–R5 remain accepted scope boundaries, discussed below.

The r4 plan's main changes are present: the undo date rule, one-pass target checker, stamp and locked comparison, carry predicate, invariant entries, E15/E15a, E18e, E20/E20b, J1, and SR10/SR11. The mutation table targets the replacement date rule rather than the removed pass. The plan's general claim that the source term is unobservable should be revised if probe 15 confirms S1.

## S1 — predicted: the source-shortfall term can also be nonzero at a take-back instant

**Locations:** frozen patch lines 449–453; frozen mutation runner lines 207–210.

The remaining assertion says the source's shortfall applications net to zero at *every* take-back instant, and consequently no check can name M64. R15 checks the state when the take-back is inserted. It does not establish that a later draw in the same transaction will be absent when that instant is replayed: both rows use `now()` and the reader uses `<=`.

[15-source-at-takeback.sql](codex-r4-probes/15-source-at-takeback.sql) constructs a separate target owing 30 and a source payment of 100 with an overpayment credit of 80. It takes back 20 under the source's posting entry, leaving the payment posted, then applies 10 of the credit to the target in the same transaction as `tally_app`. No guard is disabled and no time is chosen.

**Prediction:** accepted; at the partial take-back's recorded instant the source-shortfall term is **10**, `cash_drawn_at('credit', credit, instant)` is **10**, and the root share is **20**. The reader already includes the term, so this is not a demonstrated money-path defect. In this fixture removing the term changes the direct reader result to zero; I am **not** claiming that this fixture changes the share allocation.

If confirmed, correct the comment and add this direct reader assertion with a narrowly targeted M64. Distinguish “does not change this fixture's share” from “always reads zero.” The partial take-back preceding the draw is the relevant order; attempting the take-back after the draw would instead test R15.

## S2 — executed: SR11 does not assert the SQLSTATE named in its label

**Locations:** frozen race script's `verdict()` helper and SR11 invocation.

SR11's label promises 40001, but the helper checks session A success, observed blocking, session B failure, and a message fragment. It never checks the SQLSTATE in the verbose error output. Thus source inspection establishes that changing only the exception's ERRCODE would not invalidate this test's predicate. This is a test-contract observation, not an executed race result.

Require the verbose error's 40001 as well as the stamp-specific message. M60c removes the comparison entirely; it is useful coverage of the branch, but does not independently pin the retry code. The same helper limitation applies to other labels naming SQLSTATEs. This is nonblocking because the frozen function itself explicitly selects `serialization_failure`.

## N3 — predicted: undo dates and removal of the second reading

Probe evidence: [00-baseline.sql](codex-r4-probes/00-baseline.sql), [09-boundary.sql](codex-r4-probes/09-boundary.sql), [10-date-pairs.sql](codex-r4-probes/10-date-pairs.sql).

The guard imposes both bounds: repayment date <= undo date <= max(today at UTC+14, repayment date). It applies to every undo, including partial undos. The separate sum-of-undos check remains under the target/source locks. Probe 10 predicts that a future repayment can be fully undone on its own date, and two partial undos today can settle a historical repayment; the next day after the permitted bound is refused at the undo INSERT. Probe 07 covers two partial undos onto an escheated credit and their carries.

The redundancy argument is sound for the selected transaction date T. For an original repayment dated r and an undo dated u:

- If r <= T, then r <= u <= T; both date interpretations include the undo at every date d >= T.
- If r > T, the bounds force u = r; the interpretations agree on every date.

This argument applies separately to every partial undo, so it also applies to their sum. No discrepancy between the retroactive reading and actual-date reading survives at or after T. Before the first repayment there is no repayment to correct; afterwards the cumulative sum changes only at its event dates. The removed zero row was needed for the old divergent boundary, not for a new divergence under this bound.

I found no newly impossible correction caused by the upper bound: a historical repayment can be corrected today in an open period, and a future repayment on its own date. The inherited closed-period and ended-source restrictions still apply; this is not a promise to admit every arbitrary historical edit. Probe 09 preserves the older-date/partial-correction regression, rather than relying solely on the new date examples.

## N4 — executed: stamp, locks, statement shapes and recorded order analysis

The BEFORE trigger overwrites the supplied boolean and is ALWAYS, with no role exemption. The CHECK limits true to a credit undo; it does not purport to establish the credit's status by itself. The AFTER function calls `check_cash_source` before comparing the stamp with the credit's status again. That call acquires the family-payment lock where applicable, then the credit lock, and requires READ COMMITTED. The comparison therefore follows the lock that orders an escheat. A stale initial read is explicitly handled rather than silently used.

40001 is an appropriate retry signal for this stale classification. It does not mean the transaction was running at SERIALIZABLE. The message's description of another transaction committing is less general than the comparison itself: unusual same-statement ordering could also make the two observations differ. A mismatch still fails closed.

The target payment lock precedes source-family payment and credit locks. The date rule adds no lock, and removing the second reading removes no lock. Cross-family deadlocks remain possible and require the existing 40P01/40001 retry contract. The carry's amount calculation follows its source locks. Its early status lookup is a rejection filter; the admitted status is terminal, and the source check subsequently runs under the lock. I found no new permissive path caused by that early read.

The stamp records the status when the row is written, rather than reconstructing it from two owner-selected timestamps. The ordinary recorded-order checks are still called on target and source, and the carry still has its born-active check without a superuser exemption. This does not independently certify arbitrary owner-imported histories as chronologically complete.

Representative database predictions are in probes 00, 04–07, 14, 16 and 17. Probe 16 combines two partial undos, caller-supplied false values, a writable CTE and two carries. Probe 17 tests owner COPY supplying false to an escheated source. They predict replacement with true and successful deferred settlement. Probe 05 retains a failing COPY cap case and prints COPY's own verbose error. These examples are not an exhaustive claim about every possible writable-CTE execution order. I found no source-level bypass involving the stamp, and I did not execute or independently reproduce SR10/SR11.

## N5 — executed: -23 integration, invariants and tests

The new date condition restricts an existing write path. The source/target caps, family walks, carry sizing, cover and recorded-order calls remain present. The stamp is a carry-eligibility fact, not a new amount in a reader. The baseline probe retains their behavioral cases, including same-instant J1 and the deep-line share vector E18e; probes 12, 13 and 15 isolate selected reader/lifecycle boundaries. This is source integration review, not certification of -23's reported 409/409 or 51/51 results.

The invariant contains the exact ALWAYS stamp-trigger definition and the validated CHECK definition. It checks grants, policy shape, FORCE RLS and the carry's unique index. Its comment explicitly excludes function-body verification. Accordingly it does not independently prove that the stamp reads the right status or that the date predicate is correct: behavioral tests and mutations provide that coverage. I found no new mismatch between that stated structural scope and its implementation.

The mutation runner requires the named first failure, including infrastructure-error handling. M60b/M60e intentionally fail at S3/E3 when the locked comparison detects a wrong stamp; their descriptions acknowledge that they do not reach E15a. This is legitimate behavioral detection, not an unrelated failure being counted as a successful stamp-value assertion. M60d tests trigger structure at apply. M56/M57/M57b/M58 target the correct date boundaries. I found no concrete new mutation credited for the wrong reason from the source. I did not reproduce 72/72.

E15 pins the carry's *eligibility error*, even though its proposed carry would also face other guards if that predicate were removed. Its rejection helper matches the expected SQLSTATE and guard text, so a different later rejection is a test failure rather than a false pass. E18e actually asserts the split, rather than only a final zero balance. E20b accounts for E9's refund; its remaining 5 is appropriate to that fixture. Missing coverage is primarily S1 and S2, plus the new stamp statement-shape probes supplied here.

## N6 — executed: residuals and acceptance boundary

R1 (ordering/netting before refunds), R2 (netting before escheat reports), R3 (only ended-payment targets) and R4 (one-pot presentation) remain explicitly assigned responsibilities outside this patch. None is a new blocker.

R5 remains an intentional distinction between retroactive correction in a cap and own-date reading in positions. R4 bounds it using the transaction's UTC+14 date, not the operator's local date or continuously advancing wall-clock date. The revised wording acknowledges those limits; the date-pair and zone probes cover representative boundaries. I found no additional future interval beyond that policy from the new rule.

The possible mirror issue in -23's `refund_reissue` and its returned-refund settlement is explicitly deferred in the merged plan. I make no new database finding about that path here. It does not block -27 on the evidence reviewed: the new carry has its own stamped eligibility predicate and deferred remainder check. A separate money-stream review should establish and fix the inherited issue, rather than treating -27's source review as its reproduction.

## N7 — predicted: author-run probe inventory

Every script is for an owner session on a fresh clone with frozen r4 strictly applied. Role switches follow owner fixture setup. Each ends in ROLLBACK; caught errors print SQLSTATE and message with RAISE NOTICE. COPY prints its own verbose error and does not use LAST_ERROR_SQLSTATE. Static packaging was checked; SQL was not executed.

| Probe | Purpose / expected result |
| --- | --- |
| [00-baseline.sql](codex-r4-probes/00-baseline.sql) | Frozen r4 battery with catch notices added; expected checks retained, including caps, cover, RLS, dates, stamp, bill use and structural drift. |
| [04-statement-shapes.sql](codex-r4-probes/04-statement-shapes.sql) | Multi-row and writable-CTE target overpayment: 23514. |
| [05-copy.sql](codex-r4-probes/05-copy.sql) | COPY over target cap: COPY's own 23514 error. |
| [06-carry-history.sql](codex-r4-probes/06-carry-history.sql) | History-load carry born escheated/voided: immediate refusal. |
| [07-two-undos.sql](codex-r4-probes/07-two-undos.sql) | Partial undos require settlement; correctly sized carries settle them. |
| [09-boundary.sql](codex-r4-probes/09-boundary.sql) | Earlier repayment cannot be hidden by a later row; partial correction remains bounded. |
| [10-date-pairs.sql](codex-r4-probes/10-date-pairs.sql) | Future same-date pair and two partial undos today admitted; over-bound dates refused at INSERT. |
| [11-zone-bound.sql](codex-r4-probes/11-zone-bound.sql) | UTC+14 versus far-west calendar boundary. |
| [12-carry-lifecycle.sql](codex-r4-probes/12-carry-lifecycle.sql) | Carry pays a bill; checked endings and non-voidability retained. |
| [13-same-instant-reader.sql](codex-r4-probes/13-same-instant-reader.sql) | Repaid term -20 and root share 80, reproducing the earlier author-run case. |
| [14-isolation.sql](codex-r4-probes/14-isolation.sql) | Shared checker rejects REPEATABLE READ and SERIALIZABLE with 25000; direct branch test only. |
| [15-source-at-takeback.sql](codex-r4-probes/15-source-at-takeback.sql) | S1: nonzero source term at an earlier statement's equal recorded instant. |
| [16-stamp-shapes.sql](codex-r4-probes/16-stamp-shapes.sql) | App multi-row writable CTE replaces false stamps and creates matching carries. |
| [17-copy-stamp.sql](codex-r4-probes/17-copy-stamp.sql) | Owner COPY replaces false stamp; carry settles the undo. |
