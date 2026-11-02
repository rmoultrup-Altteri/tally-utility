# Codex review — v5.4.2-23, round 8

Verdict: **not yet**.

**Executed: source review only.** Checked the six frozen MD5s first; all matched. Reviewed the frozen patch and r7-to-r8 diff, battery, race and mutation sources, older-test diff, all three r7 reviews, the design/inventory, r8 plan, relevant DECISION-LOG entries, AC-44, and Kyle's 10-21 and 10-30 rulings. Did not read Opus's or Fable's r8 review. Did not run Docker, psql, an apply, CI, races, mutations or any database experiment. Wrote only this review and `codex-r8-probes/`.

**Predicted** means a database outcome or behavioral closure inferred from source, not an executed result. **Executed** means file/hash/source inspection. Author-reported 390 checks, 40 race results, 225 mutations and timings are not independently reproduced here. Unless qualified otherwise, patch line numbers refer to `patch-23-frozen-r8.sql`.

| Frozen file | Executed MD5 |
| --- | --- |
| patch-23-frozen-r8.sql | 25e0a9212a348dfabab4f3fa22c65822 |
| battery-23-frozen-r8.sql | c5c7fb7b3f55e6e8c192dbda94cf37a1 |
| cash-23-frozen-r8.sh | 46ed9b5d66a5fe6114f0e3fbc54942b8 |
| mutations-23-frozen-r8.py | 0478e49e40ab2e7d7fe1bc85b777d662 |
| older-tests-23-frozen-r5.diff | be99c2f963ab9f2177c9f059a4de7e5c |
| patch-23-r7-to-r8.diff | 12f52de9201be5b08e177bc71a59c83f |

## Blocking item

### B1 — predicted: the mandatory own-side reissue cannot settle a returned refund while the family remains in deficit

**Probe:** [01-negative-pool-reissue.sql](codex-r8-probes/01-negative-pool-reissue.sql). Owner history load, guards enabled, distinct recorded instants, fresh clone with frozen r8 applied. It runs the original take-back of 50 as a control and a take-back of 60 as the failing variant, rolling each scenario back independently. Every caught error prints its SQLSTATE and message.

**Concrete path:** Q5/Codex 02, changing only the take-back from 50 to 60:

1. Post payment P 100 and make overpayment credit K 30.
2. Post a refund of 20 from K and a refund of 70 directly from P.
3. Remit K's remaining 10, escheat K, and flush deferred checks. K's own and covered remainders are zero.
4. Take back 60 under P. K absorbs 30; P absorbs 30. Give back 30 under that take-back. It restores K's share, leaving K's own remainder zero and P's own remainder −30. Flush checks.
5. K's posted refund of 20 really returns from the bank. Record its reversal and move it to nsf. K now holds 20 of its own, covering part of P's −30: the positions read **P −10, K 0**.
6. Flush without a reissue: predicted **23514**, `was escheated`, from the repaired deferred check. That refusal is correct under the new own-side contract.
7. Instead carry the required 20 to a reissue in the same transaction: the size check accepts 20, but `check_cash_source` rejects it with predicted **23514**, `payment ... and its overpayment credit ... more than the payment's 100`.

**Why the required act is impossible:**

- Lines 3582–3589 size the reissue from the predecessor's and new credit's own remainders and then call `check_cash_source(..., 'reissue', ...)`.
- The per-credit cap is satisfied: K has 10 remitted plus 20 carried, no remaining absorbed share, against its original 30.
- The family cap at approximately 3318–3350 runs for a reissue as for an external draw. It correctly excludes the reissue's amount as an internal transfer, but still rejects the **existing** negative pool. P's posted refund 70 + remittance 10 + net take-back 30 = **110 against 100**. The reissue changes none of that arithmetic.
- Lines 3651–3658 still require K's own positive remainder to leave K before settlement. A smaller carry does not solve this: the size check demands 20; a zero carry leaves K's own 20 and fails deferred settlement. The probe tries 10, 20 and 20.01 independently.

The 50 control is predicted to settle with a reissue of 20 because its pool is exactly zero: 70 + 10 + (50 − 30) = 100. That is why frozen Q5b does not expose this interaction. The probe also attempts a cent of external refund after a successful carry and prints positions after the payment's separate refund subsequently returns.

This is not an excess payout, an option-A attribution complaint, an R24 terminal-status limitation, or a cross-payment AC-44 issue. It prevents completing the bank return and required status/reissue transaction within one family. The customer still owes 10; that legitimate debt is not a reason to refuse an internal carry which changes no outside money. Leaving only the ledger reversal while keeping the refund posted would violate the intended R12 workflow and leave its source position stale. The other refund may have cleared and need never return.

**Fix direction, predicted and requiring a measured regression:** distinguish a validated internal carry from a new external draw in the family-cap decision. Preserve exact own-side sizing, predecessor/source checks, dates, recorded order, locks and the external payout cap. Do not generally exempt refunds or donations from the pool, and do not restore the covered settlement check. Add the negative-pool variant and a no-external-cent control to Q5 and the mutation coverage. The author should run 01 before choosing the implementation.

## Round-7 disposition, item by item

The behavioral entries below are **predicted**. Source/contract-only dispositions are explicitly **executed**. `00` is [00-frozen-battery.sql](codex-r8-probes/00-frozen-battery.sql): frozen r8 assertions with caught-error notices and a 300-second per-statement timeout. `01` is B1 above. `02` and `03` are extracted advisory-lock topologies, not end-to-end trigger races. `04` is the retained real 20-generation history probe. `07`–`10` are retained catalog, COPY, multi-row/CTE and isolation probes, all in this round's directory.

| Codex r7 item | Disposition | Evidence / qualification |
| --- | --- | --- |
| B1 two positive siblings, position versus cap | **Closed by ruling** | Executed: Ryan chose option A; R17/R20 and agree() now state the narrower promise. Predicted: 00 Q1–Q3 test the shapes and exact positions. S2 below identifies a remaining contradictory header paragraph. |
| B2 returned refund hides own money on escheated credit | **Partly closed** | Predicted: 00 Q5a rejects the old no-carry path and Q5b settles the original shape. New 01 exposes the mandatory carry's conflict with a negative pool. |
| S1 Z6 success and performance evidence | **Partly closed** | Executed: Z6 now accepts only its deliberate P0099 success sentinel, flushes constraints and inserts a refund. It still plants ancestor history with triggers disabled; S1 below. Four additional functions and their invariant entries are pinned. 00 Z6 and 04 are author-run controls, not timings measured here. |
| S2 missing compositions and mutation coverage | **Closed for the named shapes** | Executed: Q1–Q5, CR26, N220–N226, Y7j2 and N207's new anchor are present. Predicted outcomes: 00. B1 is the new adjacent composition still missing. |
| N1 rulings | **Partly closed** | Executed: option A and updated AC-44 settle the contract questions. Predicted: the old stranded-money shape is rejected; B1 prevents settlement of another real bank return. |
| N2 locks/roles/shapes | **Closed for the listed repair; qualified** | Predicted: payment-before-credit escheat ordering, 02/03; 00 and 07–10 retain role/time/shape checks. No universal proof over every transaction composition. |
| N3 residuals R1–R23 | **Closed as accepted scope** | Executed: R20 narrowed, R21 qualified and R23 revised. R24 is expressly accepted. B1 is outside those limits. |
| N4 comments/probe provenance | **Partly closed** | Executed: the `nor while a reissue ...` wording remains at line 997; S2. Earlier author runs remain earlier-round evidence. New probes are unexecuted. |

| Opus r7 item | Disposition | Evidence / qualification |
| --- | --- | --- |
| B1 H: give-back hides own money on escheated K | **Closed for H** | Predicted: 00 Q4 rejects the 40 give-back, Q4a admits the 30 debt cancellation, Q4b/Q4c retain positions. The guard now reads own money. |
| B2 G: two holders, under-reading one cap | **Closed by option A** | Executed ruling and contract change; predicted 00 Q3/Q3a/Q3b. Exact per-line equality is no longer required. |
| S1 escheat/draw versus give-back deadlock | **Closed for D2** | Executed: payment lock now precedes K's lock at 2593–2598; CR26 and N224 added. Predicted topology in 02. Actual CR26 not run here. |
| S2 H/G/D2 tests | **Closed for requested shapes** | Executed Q3/Q4, agree() calls, CR26 and pertinent mutations; predicted 00 and 02. |
| N1 depth timings | **Closed as documentation** | Executed R21 records the reported 22–27-second refund and states 999 is a safety bound. Performance not independently certified. |
| N2 permanently netted credit never closes | **Closed as accepted residual** | Executed R24/AC-44, with -27 as closing act. Predicted related zero/own-side controls in 00 Z4 and Q5. |
| N3 jurisdiction rule and absent application target | **Closed as decision/contract** | Executed 11-02 DECISION-LOG and AC-44: per-state setoff, absent rule means report own money in full; new application targeting shortfall in -27, no invented billed charge. No -23 schema implementation claimed. |
| N4 other lock order | **Closed as scoped observation** | Predicted 02/03; the escheat exception is now aligned. Arbitrary multi-act inversion remains the explicit retry contract. |
| N5 escheat checks behind locks | **Closed for named concern** | Executed own-side and covered checks follow both locks. Predicted original zero-credit/escheat controls in 00; not a claim that B1 is resolved. |
| N6 residuals | **Closed as accepted scope** | Executed R20/R21/R23/R24 match the decisions; see residual assessment below. |

| Fable r7 item | Disposition | Evidence / qualification |
| --- | --- | --- |
| B1 P2/P3 position/cap equality | **Closed by option A** | Executed narrowed contract; predicted 00 Q1/Q2 through agree(), with exact expected figures separately checked. |
| S1 plan sensitivity | **Closed in source; timing unverified** | Executed: reissue_generation, overpayment_root, overpayment_family and cash_source_draws pinned and included in invariant; runner vacuums all three tables. 00 Z6/07 allow author verification. |
| S2 netted credit never closes | **Closed as accepted residual** | Executed R24 and AC-44; -27 owns the new closing application. |
| S3 P2/P3 tests | **Closed** | Executed Q1/Q2 plus agree(); no demand to mutate a freely chosen attribution order. |
| N1 sibling pass/conservation | **Closed as retained scoped observation** | Predicted 00 Y/Z/Q: the pass transfers at most a positive holder's available own amount and stops after removing the opposite sign; exact fixture positions and conservation remain tested. |
| N2 own-side escheat check | **Closed for the named check** | Executed common helper replaces inline formula; non-family credits now use their ordinary position rather than the old NULL skip. Predicted 00 W/Y/Z/Q zero/remitted controls. B1 concerns the later mandatory carry. |
| N3 lock order | **Closed with escheat correction** | Predicted 02/03; source now takes P before K for escheat too. |
| N4 roles/isolation/statement shapes | **Closed as scoped observation** | Executed new helper is STABLE, invoker-rights, PUBLIC revoked, app/core execute. Predicted 00 and 07–10. No new definer or write privilege. |
| N5 void-share instant | **Closed as retained behavior** | Predicted 00 Z5–Z5d; shares still read under P's lock, share-bearing void still refused until give-back. |
| N6 good-statistics depth timings | **Closed as recorded evidence** | Executed R21 retains the performance limitation. 00/04 supplied, no new timing claim. |
| N7 AC-44 before escheat | **Closed as revised contract** | Executed 11-02 ruling narrows the earlier unconditional step to allowed jurisdictions, with full reporting on absent rule. |
| N8 residuals | **Closed as accepted scope** | Executed R17/R20 narrowing, R21 timing qualification, R24 addition. |
| N9 mutations | **Closed for named source changes** | Executed runner retains first-failure attribution and adds new legs. Counts remain author evidence. |
| N10 container note | **Closed / outside this review** | Executed: no container command was run; no present container-count claim. |
| N11 red-run provenance | **Closed as provenance only** | Executed: earlier and current red-run reports are not independently reproduced. |

## Should-fix items

### S1 — executed: Z6 proves a guarded endpoint on planted history, not the plan's full-history boundary control

Battery 2472–2519 still disables all payment and credit triggers, inserts returned refunds directly as nsf without posting/return ledger rows or status causes, and inserts the first 998 reissues directly. At 2522–2541, the 999th creation, constraint flush and refund are now required to succeed. That **does** repair the old arbitrary-error-as-PASS defect. It does not implement the r8 plan's stronger “with full history” positive control.

Keep the defensive planted-chain test, but label its evidence accurately, and retain a real-history positive control separately. The supplied [04-bounded-real-chain.sql](codex-r8-probes/04-bounded-real-chain.sql) makes 20 generations through enabled guards and flushes checks, bounded to 180 seconds; it is not a 999-generation benchmark. Do not require an unbounded 999-act experiment to resolve this wording gap. If claiming full-history generation-999 validation, supply a bounded, faithful fixture and measure it separately. The stale Z6 preamble still says “whatever the later checks say”; update it now that the endpoint must succeed.

### S2 — executed: the old exact-cap promise remains in the patch header

Lines 128–134 still say: “Each position then equals what its cap admits ...”. The r8 paragraph and R17/R20 correctly supersede that promise, but the “What changes” section now states both contracts without marking the old one withdrawn. Narrow this occurrence too. This is documentation, not a demand to reverse option A.

The `enforce_ledger_reversal` COMMENT at line 997 also retains the previously flagged “nor while a reissue ... is applied or has a refund pending” wording inside its description of when a bounce waits. Replace “nor” with wording that clearly includes descendants in the hold-up.

## Notes and remaining review questions

### N1 — executed authority review; predicted behavior: rulings and reissue sizing

Option A is explicitly authorized. A displayed allocation below a line's permitted next draw is accepted; exact cap equality should not be reintroduced through tests. Q1–Q3 retain exact expected positions, while agree() tests positive position admission, pool-plus-cent refusal, absence of opposite signs and conservation. That is a coherent distinction.

The own-side helper uses one supplied date/recorded coordinate for the share and draw reads. Its family branch is original amount minus recorded share minus applied/refunded/given-up/carried; its non-family branch delegates to the existing position reader. Each caller supplies the last finite date and current recorded time. The transition, give-back guard, deferred settlement and reissue-size expression all call it. Probe 00 retains Y8/Y8c/Z4d and Q4a debt-cancellation controls, Z4f genuinely empty control, and W/Y/Q refund-return controls. These are **predicted**, not freshly observed admissions.

The reissue's own-side size is necessary for the original Q5 shape; simply restoring covered sizing would make that required carry zero. The amount is bounded by the returned refund and the computed own money. The new failure is the subsequent pool admission decision (B1), not evidence to weaken own-side settlement.

K-10's bank movements remain independent, and posted refunds do not reduce the reversal-tree cap. The pending-refund hold-up and utility-controlled return-window boundary are retained (00). Ryan's terminal escheat rule is enforced more completely, but B1 prevents recording a legitimate returned refund under that rule. This is why the verdict remains not yet despite the original H and Q5 repairs.

AC-44's per-jurisdiction condition and missing-rule default are explicit product decisions here; I am checking their implementation boundary, not making a legal finding about any state's law. -27's application is expressly deferred. R23 and R24 do not authorize refusing B1's bank return.

### N2 — executed source tracing; predicted concurrency, role and statement behavior

The source caps are read after their source mutexes. Payment-family credit draws take P before the credit; line applications take the line lock afterward. Give-backs take the tree, P and family credits; reissue voids take P, predecessor and self. The added escheat lock precedes the credit lock. Refund leaving moves acquire their source locks before releasing the money for a subsequent draw; the deferred settlement executes in that same transaction. Relevant controls: 00, [02-A](codex-r8-probes/02-escheat-lock-topology-A.sql)/[02-B](codex-r8-probes/02-escheat-lock-topology-B.sql), and 03-A/B/C.

The 02/03 probes establish only the extracted advisory-lock ordering when the author runs them; they neither create cash fixtures nor certify actual trigger races. CR26's source exercises the actual escheat/draw versus give-back sequence, checks blocking and process outcomes and detects 40P01. I did not run it. No additional concrete lock cycle is asserted. The header's allowance for arbitrary multi-act and multi-row ordering, with 40P01/40001 retry, remains necessary.

The writer guards explicitly reject non-READ-COMMITTED execution rather than relying on a stale snapshot after waiting. [10](codex-r8-probes/regression-10-isolation-pins.sql) tests REPEATABLE READ and SERIALIZABLE; the other controls use READ COMMITTED. [07](codex-r8-probes/regression-07-catalog-and-invariants.sql) inspects privileges, invoker/definer properties, pins and invariants. [08](codex-r8-probes/regression-08-copy-arrival.sql) exercises COPY with its own native verbose error. [09](codex-r8-probes/regression-09-donation-statement-shapes.sql) covers multi-row and writable-CTE cap attempts. 00 contains app-role and owner-history controls. These are bounded coverage, not a claim to have proved every role/statement combination safe. A superuser intentionally disabling triggers is outside ordinary enforcement; Z6 does that deliberately for its fixture. B1 requires no bypass.

R17's transaction-start attribution qualification is retained. A chosen owner history move is checked against lineage, while an ordinary early-start transaction is subject to the documented model. No new retroactive-return exploit is established by this review; the supplied temporal tests do not prove all possible interleavings.

### N3 — executed: invariants, mutation attribution and coverage

All four new pinned functions appear in the exact proconfig list alongside the earlier tree/share functions. The invariant checks catalog definitions/settings and grants, not arithmetic equivalence or planner execution cost. Its final COMMENT says so. Pins discourage the specific bad plans; they are not a proof that no statistics or family shape can perform poorly. I make no fresh latency claim.

N207 now has a direct own-cap boundary at Y7j2, so narrowing agree() no longer removes that explicit refusal test. N220 changes the give-back reader, N221 the deferred reader, N222 the size reader, N223 the helper's cover argument, N224 the escheat payment lock, and N225/N226 the plan pins. Their named anchors correspond to the affected source checks. The runner rejects failures at the wrong named check; the APPLY branch reads the first ERROR line. I found no additional concrete existing mutation caught for a demonstrably unrelated reason in source review; **225/225 remains reported, not executed evidence**.

The newly missing test is an internal carry while the family remains negative, not another assertion that an external refund is capped. Frozen Q5's exact zero pool hides it. Include 01's negative variant and ensure its eventual mutation is caught by the settlement path and not by fixture setup.

The frozen older-tests diff remains unchanged since r5. Its fixture adaptations do not constitute a current CI result; it also retains the already-labelled -25 dispute-field adaptation. This review does not claim end-to-end compatibility of every earlier suite.

### N4 — executed scope judgment; predicted behavior: residuals R1–R24

None of the explicitly accepted residuals is independently blocking. Their boundaries remain:

| Residual | Assessment |
| --- | --- |
| R1 | Accepted ledger-tree depth/cost limit, separate from the 999 reissue bound. 00 depth controls; no fresh timing claim. |
| R2 | Accepted recorded-coordinate/open-transaction model; 00 temporal controls. |
| R3 | Invoice paid/partial labels remain separate from the derived balance. |
| R4 | Application undo/rebill workflow remains the core's responsibility. |
| R5 | Repeated charge-type vocabulary remains a maintenance obligation. |
| R6 | Source-less line classification remains the core's responsibility. |
| R7 | Allocation/floor/notification policy remains outside these guards. |
| R8 | Earlier-test adaptations remain explicit; CI was not run here. |
| R9 | Matching tariff service/system to a bill remains the core's responsibility. |
| R10 | Deposit-wide refund cap remains the earlier deposit/event machinery's scope. |
| R11 | Long statements/timeouts remain an operational constraint. |
| R12 | Return ledger row and status move belong together; B1 prevents completing that transaction and is not excused by this residual. |
| R13 | Pending-refund cancellation UI remains application work; database hold-up retained in 00. |
| R14 | Return-window policy/configuration remains an explicit later/core concern. |
| R15 | Bounce/draw hold-up retained, including descendant reissues; 00 W/Y controls. |
| R16 | One live overpayment credit per payment retained; 00 and 07. |
| R17 | Transaction-start/same-instant attribution accepted, with narrowed position claim; 00 temporal controls. |
| R18 | Erroneous refund-return correction limitation accepted; no new correction path claimed. |
| R19 | Reissue lineage immutability accepted. |
| R20 | Option A accepted. S2 concerns inconsistent explanatory text only. |
| R21 | Safety bound and long-lock cost disclosed. S1 limits the endpoint test's provenance. |
| R22 | Share-bearing reissue void refusal explicitly accepted; 00 Z5. |
| R23 | Across-payment netting assigned to core, per-state before escheat; -27 records it. |
| R24 | Permanently netted active credit accepted, with -27 as closing act. This does not permit an unrecordable return as in B1. |

### N5 — executed: probe delivery and limits

Twelve SQL files are delivered in [codex-r8-probes](codex-r8-probes/). Run each standalone probe as owner on a fresh clone with frozen r8 strictly applied and clone TEMP revoked from PUBLIC, tally_app and tally_core. Run the two 02 files together on one such clone, and the three 03 files together on another, in their documented order. No probe creates, drops or alters roles. Every file ends in ROLLBACK; 10 uses two separately rolled-back isolation transactions. Caught errors print SQLSTATE and message; COPY prints its native verbose error and `\errverbose`, never relying on LAST_ERROR_SQLSTATE.

P0099 is an intentional rollback sentinel, not a guard refusal. An unexpected setup error or timeout is not confirmation of B1 or a passing regression. Probe 00 preserves the frozen assertions, including Z6's planted ancestors; the 300-second statement timeout bounds the endpoint. Probe 04 is limited to 20 real generations and 180 seconds. No probe result is executed evidence until the author runs it.
