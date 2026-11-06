# Codex — v5.4.2-27, review round 3

Verdict: **ready** (source review; nonblocking S items below).

No new blocking money-path defect identified. My r2 B1 is addressed. The remaining findings concern a missing promised regression, the rationale for omitting reader mutations, and the wording of the timezone residual. Author execution of the supplied probes remains outstanding; this verdict is not a claim that they passed.

**Executed** means checksum verification, source inspection/comparison, or reading an explicitly permitted prior author-run output. **Predicted** means an unexecuted database result, accompanied by a probe. I ran no Docker, psql, CI, races, mutation runner, or SQL. I read no `opus-*.md` or `fable-*.md`. Only this review and `codex-r3-probes/` were written.

## N1 — executed: freeze and authority

All hashes matched before source review:

| File | MD5 |
| --- | --- |
| review-brief-27-r3.md | 8b093403fe66d18202d3bb88dfa54239 |
| patch-27-frozen-r3.sql | 135242ab0b14159bfea2b3045ce1312d |
| battery-27-frozen-r3.sql | f44547c8e2816cc3a5c819326029ae33 |
| shortfall-27-frozen-r3.sh | 939b0cbb22ca3b37f392dc8792861ade |
| mutations-27-frozen-r3.py | 2e325488d7b98e789e01295c4c99e3a6 |
| r2-to-r3.diff | d58402023878e191bf0fd58c9fc939c0 |

The brief matches its `.md5` file. Authority considered: the -27 design and merged r2/r3 plans; tally-utility's DECISION-LOG, wave-2 inventory and PATCH-LESSONS; the permitted Kyle decisions dated 2026-10-21 and 2026-10-30 in gas-billing-memory/application. Later explicit decisions control the older design descriptions. No new product ruling is inferred here.

## N2 — executed: disposition of every r2 item

- **B1 — fixed in source.** `enforce_shortfall_reissue`, frozen patch lines 1302–1306, rejects every non-active birth before its other checks, without the inherited superuser exemption. E6c/E6d and M59 address the original case. The permitted r2 author output for probe 06 confirms the old escheated-birth acceptance; it is not an r3 result. R3 reproduction: [06-carry-history.sql](codex-r3-probes/06-carry-history.sql), predicted immediate 23514 for both terminal births. [12-carry-lifecycle.sql](codex-r3-probes/12-carry-lifecycle.sql) additionally exercises active birth followed by ordinary checked endings.
- **S1 — substantially fixed, not entirely.** C2b is a genuine partial undo; E7c compares account balances; E7d observes the carry draw; S3c tests the never-escheated source; E15 tests recorded ordering; E17 tests depth; E16/E18 test both mixed directions; E19/E19b test ordinary undo callers. Missing positive bill application and the reader-mutation rationale are S1/S2 below.
- **N1 — refreshed** by this review's N1.
- **N2 — addressed.** The race monitor/reaper now uses `MON`, with a five-second statement timeout and connection timeout. This resolves my specific query-timeout observation. It does not establish a process deadline for a stalled Docker transport. The r1 findings recapped in r2 N2 remain addressed by the retained r2 source.
- **N3 — retained and extended.** The r3 executable changes to the patch are the repayment zero scale, two-pass cap with a boundary sentinel, active birth, and the undo/escheat stamp comparison. The r2 ancestry/reader additions remain in place.
- **N4 — refreshed as predictions**, not promoted to executed r3 results. See the probe inventory below.
- **N5 — source lock/isolation conclusions retained**, with invariant limitations made explicit in N5 below. The header/table/section comments now acknowledge R5, subject to S3's precision correction.
- **N6 — retained with amended R5.** R1–R4 are authorized divisions of responsibility, not blockers; the second reading bounds R5 by the selected UTC+14 date. See N6 and S3.

## S1 — executed: the positive bill-application regression is still missing

The r2 plan expressly promises that a carry can pay a bill. R2 S1 flagged its absence. The r3 battery's only invoice-application INSERTs are E19's setup and attempted undo, both on the ordinary goodwill credit `n50`, not a `shortfall_reissue`. E9 exercises a refund from the carry, which does not test the bill writer.

Add the small positive caller-level test in [12-carry-lifecycle.sql](codex-r3-probes/12-carry-lifecycle.sql): a valid 30 carry pays 20 of a real issued bill, then reads applied 20 / remaining 10. **Predicted**, not executed. This is a regression omission, not evidence that the writer fails.

I accept the explanation for dropping the *different* requested test, an invoice-application undo on an already repaid family: the inherited R15 bounce checks require the family's bill applications to net to zero before the payment ends. E19 is a useful reachable caller test of the escheated-source rule. That explanation does not dispose of the positive carry-to-bill test.

## S2 — predicted: “the repaid term is zero at every take-back instant” overlooks equal timestamps

Frozen patch lines 418–424 and mutation-runner lines 187–194 assert that both omitted terms read zero whenever `overpayment_shares` asks. Recorded-after enforcement uses comparisons permitting equality, and ordinary rows in one transaction share `now()`. A repayment performed after a bounce can therefore be included by `created_at <= take_back.created_at` during a later replay of that same instant.

[13-same-instant-reader.sql](codex-r3-probes/13-same-instant-reader.sql) supplies a concrete ordinary sequence, as owner with guards enabled:

1. Payment 100, held wholly as an overpayment credit; that credit refunds 100.
2. Bounce the payment in the same transaction.
3. Apply another credit's 20 to its shortfall, still in that transaction.
4. Read the target's repaid term and `cash_drawn_at` at the bounce row's recorded instant, then replay `overpayment_shares`.

Prediction: the repaid term and the payment's `cash_drawn_at` are **-20**, not zero. The root's recorded share is **80**. By source arithmetic, deleting the repaid term would instead assign **100** to that root: `v_hold_p` would be 0 rather than 20. This is an observable reader boundary suitable for a focused regression; I did not run or create a mutation runner.

Retain the terms. Correct the universal zero/no-observable-test explanation and revisit the omitted repaid-term mutation using this fixture. This finding does **not** allege that frozen r3 has a broken cap, or that the reported frozen mutation results are fabricated. The supplied 67 mutations do not include that term. I have not constructed a corresponding downstream difference for the source-shortfall term, and do not claim one.

## S3 — predicted: R5 can reach two local calendar dates ahead

The UTC+14 bound is a defensible zone-independent choice: among the supported zones under discussion, an earlier scalar date could reject an undo dated today in the most advanced zone. Using a tenant zone would be tighter for that tenant but would change this deliberate zone-free contract.

The description “at most one local day ahead,” however, is too narrow. [11-zone-bound.sql](codex-r3-probes/11-zone-bound.sql) uses the fixed instant `2026-11-06 10:30+00`. Predicted dates: UTC+14 is November 7; UTC-12 and Pacific/Pago_Pago are November 5. The difference in date labels is **two**, including an inhabited zone. The probe also prints Honolulu, Chicago and Kiritimati for comparison. It changes no clock or function.

Describe the residual as bounded by the UTC+14 date, potentially two local calendar dates ahead in far-west zones, rather than promising one everywhere. This is a documentation/acceptance-boundary correction, not a bypass of the implemented UTC+14 comparison. Also name that `now()` is the transaction's instant: a transaction spanning that zone's midnight does not advance its bound. I am not proposing a wall-clock substitution without considering the existing transaction-time model.

## N3 — executed: r3 plan implementation and stamp choice

The two readings implement the plan's historical correction plus current/future bound. For a leaving move, pass 1 uses the earliest positive repayment date and projects each undo onto its own original row; pass 2 uses actual row dates from UTC+14 today. The zero sentinel at `v_from` matters: it samples a carried-forward positive balance even without a row dated on that boundary. A new positive repayment still gets one own-date reading. Partial undos remain linked and capped by the original application.

I agree with choosing `status_recorded_at` over `escheated_at`. The former is the inherited transition stamp and is fixed without a status change; the latter is an app-written, write-once field. The inherited credit transition also checks a history loader's chosen timestamp against its lineage and rejects future/infinite timestamps. Equality is deliberately allowed; this is a recorded-time ordering rule, not a statement-sequence ordering rule. E15 distinguishes the timestamps by choosing the later status stamp. Its expected refusal is included in probe 00.

The source check is before the carry's locks, but normal escheated status is terminal and its stamp cannot subsequently change; the size read follows the source-family/payment and source-credit locks. I found no new ordinary stale-status race introduced by this comparison. Imported old credits with incomplete history remain subject to the inherited history-load model; this review does not certify arbitrary owner-imported histories as independently audited chronology.

The plan's phrase “rule is added to the invariant” must be understood narrowly. The invariant already lists this exact ALWAYS trigger; r3 changes its function body. The invariant does not independently inspect the born-active predicate. E6c/E6d/M59 supply its behavioral coverage.

## N4 — predicted: two readings, statement shapes, lifecycle and -23 integration

All database predictions have owner-session scripts under `codex-r3-probes/`, each for a fresh clone with frozen r3 applied, ending in ROLLBACK. Application-role cases switch locally after owner fixture setup. Caught errors print SQLSTATE and message. COPY prints its own verbose error and `\errverbose`, never `LAST_ERROR_SQLSTATE`.

| Probe | Purpose / prediction |
| --- | --- |
| [00-baseline.sql](codex-r3-probes/00-baseline.sql) | Frozen r3 battery with catch notices added; expected checks retained, including the two date boundaries, history stamps, caps, cover, mixed lines, RLS, source exclusions and invariant drift. Not an independently observed 135-check pass. |
| [04-statement-shapes.sql](codex-r3-probes/04-statement-shapes.sql) | Multi-row and writable-CTE repayments exceeding a dated target cap: predicted 23514. |
| [05-copy.sql](codex-r3-probes/05-copy.sql) | Owner COPY of two 6 rows into a 10 shortfall: predicted COPY's own 23514 error. |
| [06-carry-history.sql](codex-r3-probes/06-carry-history.sql) | Original r2 blocker rerun: escheated and voided carry births now refused immediately. |
| [07-two-undos.sql](codex-r3-probes/07-two-undos.sql) | Two partial undos: deferred refusal without carries, then correctly sized multi-row carries of 10 and 20. |
| [09-boundary.sql](codex-r3-probes/09-boundary.sql) | Retained earlier/later repayment hole and partial correction; forward replacement remains the continuation. Zero formatting updated for r3. |
| [10-date-pairs.sql](codex-r3-probes/10-date-pairs.sql) | Future repayment and undo on the same future date admitted; undo a day later refused. Two partial undos today admitted; leaving 20 to undo tomorrow refused. Each scenario rolls back locally, printing its outcome. |
| [11-zone-bound.sql](codex-r3-probes/11-zone-bound.sql) | S3's deterministic calendar boundary. |
| [12-carry-lifecycle.sql](codex-r3-probes/12-carry-lifecycle.sql) | Active carry cannot escheat without a remittance or be voided; proper full remittance permits ending at zero; separate savepoint branch tests paying a bill. |
| [13-same-instant-reader.sql](codex-r3-probes/13-same-instant-reader.sql) | S2's nonzero repayment term at the recorded take-back instant. |
| [14-isolation.sql](codex-r3-probes/14-isolation.sql) | Shared source checker rejects REPEATABLE READ and SERIALIZABLE with 25000 before source lookup. Direct branch test, not an end-to-end race. |

From the source, the second window samples the cumulative sum at its boundary and every later event date; that sum is constant between event dates. I found no sequence that evades both readings and leaves a positive *family total* at a later actual-date reading. This is a source argument, not exhaustive model checking. Probe 10 specifically covers the legitimate future-dated repayment/undo pair that a blanket future-date prohibition would reject.

The born-active AFTER INSERT check has no superuser early return. Subsequent UPDATEs still traverse `enforce_customer_credit_immutable`, including its remittance/cause and remaining checks, and the new shortfall-reissue UPDATE guard forbids voiding. An AFTER trigger's timing alone does not exempt another UPDATE in the transaction from those checks. The probes exercise representative shapes, not every possible chained writable CTE.

The mixed fixture actually constructs overpayment → shortfall_reissue → refund_reissue → shortfall_reissue. E16 asserts generation 2/root/family and balances; E18b asserts generation 3/root/family and balances; E18c/d exercise the original payment's later bounce. Generation 1 is independently asserted in E13b. E14c checks the share before cover, which is stronger than only checking a zero final position. E18d itself checks only the final remaining amount; it is not a full per-generation share-vector assertion. Probe 00 preserves these distinctions.

## N5 — executed: locks, invariants and test evidence limits

R3's second reading runs under the same caller-held target/family payment lock as the first. It adds no lock edge. Shortfall writers still take close head, target payment, then source-family payment and source credit. Carry size is read after its source locks; deferred settlement relies on the undo's transaction-held locks. The ancestry keys are fixed. I found no additional cap read newly detached from its ordering lock.

Cross-family target/source ordering can deadlock; the documented 40P01/40001 retry contract remains necessary. This is not deadlock freedom. The frozen races exercise both source-draw directions, target competition, returned refunds and recorded-order retries; they have no dedicated carry-creation race. No concurrency result was executed or independently reproduced here. The new date pass does not fix or worsen the already documented cross-family lock cycle by adding a new lock.

The invariant checks exact trigger definitions/ALWAYS flags, validated constraint definitions, unique carry index, RLS/policy shape and privileges. It checks neither arbitrary function semantics nor all stored history. Its own comment disclaims function-body checking. The required app SELECT/INSERT and core SELECT privileges remain checked individually; forbidden column grants are included.

The mutation runner still demands the named first failure. The rejection helper checks SQLSTATE and guard text, so an unrelated earlier refusal does not count as the intended battery success. M38 deliberately tests losing the escheated-undo exception by failing E3 on the wrong guard. M61 narrows the depth bound inside the failing subtransaction, so the ordinary E18 continuation uses the real bound again. I found no concrete frozen mutation credited for the wrong reason from source inspection. I did not reproduce 67/67, 16 race results, strict apply/twice, the -23 regression counts or CI's 55 steps.

## N6 — executed: residuals and acceptance boundary

R1's ordering/customer-wide refund netting, R2's jurisdiction-dependent escheat policy, R3's ended-payment target restriction and R4's one-pot presentation remain expressly assigned outside these guards. None is a new blocker.

R5 remains an intentional discrepancy between a correction's retroactive cap treatment and the position reader's own-date treatment. R3 adds the actual-date window from the selected UTC+14 date; it does not erase historical positive readings or adopt tenant-local today. S3 corrects the width description without changing that design choice. Probe 10 supplies the current/future correction boundary, while probe 00 retains the historical cases.

The source addresses the terminal-carry blocker and the future-undo gap described in the brief. The remaining S items should be resolved in tests/comments; none here establishes a new accepted invalid money movement in frozen r3. The author should run the probes, particularly 10, 12 and 13, before treating the predictions as verified results.
