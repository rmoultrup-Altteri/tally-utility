# Codex review — v5.4.2-23, round 7

Verdict: **not yet**.

**Executed — source review only.** Read the brief and checked all six MD5s before substantive review; all matched. Inspected the frozen patch, battery, race and mutation sources, older-test diff, r6-to-r7 diff, all three r6 reviews, the design/inventory, r7 plan, DECISION-LOG, AC-44, and the supplied Kyle rulings. Did not read Opus's or Fable's round-7 reviews. Did not run Docker, psql, an apply, CI, races, mutations or database experiments. Only this review and `codex-r7-probes/` were written.

**Predicted** labels below cover every database result, closure assessment and lock conclusion. **Executed** means a source inspection or file/hash check, never SQL execution. Author-reported runs are not independently reproduced. Source line references are to `patch-23-frozen-r7.sql` unless another file is named.

| Frozen file | Executed MD5 |
|---|---|
| patch-23-frozen-r7.sql | 9bbaab8a2f23634ad617c5bb12cb196a |
| battery-23-frozen-r7.sql | e43f0c34c7930d62ee4d3c8959ec0f10 |
| cash-23-frozen-r7.sh | 90d6d81e656a1c47971f8837c1edfb0e |
| mutations-23-frozen-r7.py | 8f699ac28b9f3c4d024067ff372e585d |
| older-tests-23-frozen-r5.diff | be99c2f963ab9f2177c9f059a4de7e5c |
| patch-23-r6-to-r7.diff | 3b96c94570aa33ddc0062e1cfd8468e0 |

## Blocking items

### B1 — predicted: with two positive siblings, the cover assigns balances that the unchanged caps do not enforce

**Source:** sibling cover at 1970–1981; per-credit cap reads the uncovered shares at 3199–3228; family pool at 3237–3264. **Probe:** [01-two-positive-siblings.sql](codex-r7-probes/01-two-positive-siblings.sql).

All guards enabled, owner history load, distinct recorded instants:

1. P 100, overpayment K 100.
2. Return two separate posted refunds of 20 from K and carry them into R1 and R2, in that order. K holds 60, R1 20, R2 20.
3. Refund/post K's 60 and both reissues' 20. Nothing is held.
4. Take back 10 under P. Its share falls on K.
5. Return R1's and R2's refunds. Force all deferred checks.

Before the cover the remainders are P 0, K −10, R1 20, R2 20. The latest-first cover moves 10 from R2 to K: **positions P 0, K 0, R1 20, R2 10**. The total 30 is correct and no deficit sits beside money.

But R2's own cap still admits 20, and the pool has 30. Independently attempted refunds of **10.01 and 20 from R2 are predicted admitted**; 20.01 is refused by its own cap (23514). The supplied `agree()` reports failure on the first cent above R2's displayed remainder. R1 independently admits 20 as well; those alternatives cannot be added together as simultaneous availability.

The distinction matters: a source's maximum next draw is `min(its uncovered positive remainder, the available pool)`. With two positive sources and a third in deficit, those maxima need not sum to the pool. A deterministic allocation of the deficit can conserve the sum, but cannot also equal every unchanged cap. The r7 loop correctly removes opposite signs; that alone does not establish the stronger position/cap contract.

This is an attribution/reader blocker under the same contract used for Opus r6 B3, **not a claim that money escapes K-10's pool**. Decide explicitly how an allocated position and a permitted next draw relate. Either make the chosen allocation binding with corresponding writer checks, or distinguish allocated balances from per-source draw capacity and revise the public contract and `agree()` accordingly. Merely changing latest-first to oldest-first moves the discrepancy.

### B2 — predicted: a refund returned after a valid escheat can hide money there until the payment's refund returns

**Source:** own-side check only on the escheat transition, 2558–2571; `enforce_escheated_credit_settled` still checks the covered position only, 3543–3571; that deferred trigger is limited to refunds naming a credit. **Probe:** [02-return-after-escheat.sql](codex-r7-probes/02-return-after-escheat.sql).

All guards enabled, owner history load, distinct recorded instants:

1. P 100; overpayment K 30. Refund/post 20 from K and 70 directly from P.
2. Remit K's remaining 10 and escheat K. This is a legitimate transition: both K's own and covered remainders are zero.
3. Take back 50 under P: K absorbs 30, P 20. P stays posted (a partial return).
4. Give back 30: the credit's share is restored first. K's own remainder is zero and P's is −20. The escheated-credit give-back check admits this cancellation of debt.
5. Return K's posted refund of 20. **Force deferred checks now, before the next act.** K now has own remainder +20, but covers P's −20, so both positions read zero. The deferred settlement check admits the return without a reissue.
6. Return P's posted refund of 70. Force deferred checks again.

Predicted final positions: **P 50; K 20, still escheated**. The ledger leaves 70 (100 − 50 + 30 − 10). A refund of P's 50 is admitted; 50.01 is refused by P's cap. A refund of 0.01 from K is refused because it has ended. `agree()` catches the positive escheated balance. Each attempted draw is rolled back independently.

This reaches Opus r6 B1's stranded-money state despite satisfying the new escheat-transition guard. The new predicate establishes the condition at the transition, but the returned-refund path can invalidate it afterward. The late return of P's refund is a real bank event and cannot safely be prohibited as the fix. Extend the settlement/reissue design to handle **own money hidden by cover on an already-escheated credit**, retaining the full-bounce/zero-reissue controls. Checking only the displayed remainder at commit is insufficient. This is within one payment family, so R23 does not excuse it.

## Round-6 disposition, item by item

All behavioral dispositions below are **predicted**. `00` means [00-frozen-battery.sql](codex-r7-probes/00-frozen-battery.sql), a copy of the frozen battery with caught-error notices and two direct generation checks. It preserves the original test assertions, including Z6's limitation. `03` means the three extracted lock-topology probes, not an executed trigger race.

| Codex r6 item | Disposition | Evidence / qualification |
|---|---|---|
| B1 family deficit beside money | **Partly closed** | 00 Z3/Z3a closes the reported give-back shape; the sibling pass removes opposite signs. New B1 breaks the broader cap-agreement claim. |
| B2 depth loses payment | **Closed for the fail-open boundary** | Shared 999 bound; insert checks generation; all three walkers detect generation 1000 and raise. 00 Z6a–d plus direct generation checks. S1 limits the positive-control/performance evidence. |
| S1 void/give-back deadlock | **Closed for the reported pair** | Void now takes P before K/R (2481–2491); 03 and frozen CR25 source. |
| S2 coverage/attribution | **Partly closed** | APPLY first-error match, shares plan list and count text fixed. New compositions absent; Z6 positive control remains narrow, S1/S2 below. |
| S3 durable comments | **Closed for the named stale descriptions** | Reissue amount comments, held-credit bounce wording, R15 descendants changed. Executed source observation; one awkward phrase remains, N4. |
| N1 rulings | **Partly closed** | Depth repair and Kyle's attribution authority addressed; new B2 still defeats the escheat rule. |
| N2 locks/roles/shapes | **Partly closed as a universal claim** | Named lock/depth defects repaired; retained probes 07–10. New B1/B2 require no role/isolation bypass. |
| N3 residuals | **Partly closed** | R22/R23 explicitly authorized; R20's position/cap assertion still fails in B1. See residual table. |
| N4 probe delivery | **Closed as delivery/provenance** | Earlier author results remain r6 evidence. New files are unexecuted r7 probes. |

| Opus r6 item | Disposition | Evidence / qualification |
|---|---|---|
| B1 covered escheat later holds money | **Partly closed** | 00 Z4a/Z4c blocks E/Ec's original escheat; Z4f retains genuine zero control. New B2 reaches the same outcome by returning K's refund after a valid escheat. |
| B2 family cover | **Partly closed** | 00 Z2/Z2a closes F; new B1 needs two positive siblings. |
| B3 void retains share | **Closed for V** | 00 Z5–Z5d refuses the share-bearing void, then admits it after give-back. R22 authorizes this alternative to transferring the share. |
| S1 lock cycle | **Closed for D** | Payment-first void; 03 / CR25 source. |
| S2 comments | **Closed for listed comments** | Executed source changes described above. |
| S3 tests | **Partly closed** | E/Ec/F/V/D and escheated `agree()` branch added; new B1/B2 absent. |
| N1 take-back recorded order | **Closed as retained scoped observation** | 00 Y5 controls; no new refusal claimed for that path. |
| N2 lineage recorded time | **Closed for named gap** | Full bounded walks; 00 Y6 and boundary checks. No assertion over arbitrary trigger-disabled corruption. |
| N3 one instant | **Closed as retained temporal qualification** | 00 W12/Y0c/Y4; not an exemption from B1/B2. |
| N4 cover versus money caps | **Partly closed** | Pool remains the guard; the stronger equality of each position to its cap fails in new B1. |
| N5 voided position reads amount | **Closed as retained note** | 00 Z5; `agree()` excludes voided credits from its family total. No new blocker asserted for that display convention. |
| N6 residuals | **Partly closed** | R22/R23 explicit; B1/B2 are not accepted residual behavior. |
| N7 count | **Closed in source** | Brief/header/plan now say 372; executed text check, not an executed PASS count. |

| Fable r6 item | Disposition | Evidence / qualification |
|---|---|---|
| B1 refund return leaves sibling money beside deficit | **Partly closed** | 00 Z1/Z1c and agree() close P1/P1c; new B1 defeats general cap equality. |
| S1 void/give-back cycle | **Closed for RR-E** | Payment-first void, 03 / CR25 source. |
| S2 missing tests | **Partly closed** | Original return and race shapes added; new B1/B2 absent. |
| N1 transaction-start return changes attribution | **Closed as documentation** | R17 now says so explicitly (executed text); 00 temporal controls retain the model. |
| N2 lineage completeness | **Closed for reported depth limit** | Shared bound; 00 Y6 and Z6; source excludes no new legitimate recorded-order path identified here. |
| N3 take-back ordering | **Closed as retained scoped observation** | 00 Y5; no new violation claimed. |
| N4 remaining lock order | **Closed for the named pair** | 03 / CR25; multi-act/multi-row arbitrary lock ordering remains outside that claim. |
| N5 pool and reissue sizing | **Partly closed** | 00 W/Y/Z retains original controls; new B1 refutes the general reader/cap identity, B2 exposes settlement rather than an excess payout. |
| N6 roles/superuser | **Closed for the listed guards** | Probe 07 catalog, 08 COPY, 09 statement shapes, 10 isolation, and 00 owner time checks. No universal security proof. |
| N7 mutations | **Partly closed** | N212–N219 cover the named new legs; no multi-surplus or post-escheat hidden-return check. |
| N8 residuals | **Partly closed** | R20 now names sibling cover; new B1/B2 still conflict with the claimed behavior. |
| N9 red-run provenance | **Closed as provenance only** | Author's red-run report not reproduced. |

## Should-fix items

### S1 — executed source: Z6 does not establish successful generation-999 creation or usable near-boundary performance

Battery 2495–2509 catches every error from the 999th insert/constraint flush and fails only when the message contains `reissues deep`. An unrelated refusal is followed by `PASS Z6 the 999th reissue passes the bound`. The comments disclose this; the result proves traversal reaches a later check, not successful creation. The ancestors are planted with triggers disabled and no money rows. That is useful defensive testing, but not a valid full-history boundary control.

Keep this test and add a bounded, valid positive-control fixture that actually inserts generation 999, flushes deferred checks and exercises its payment-linked cap. Require its exact success rather than accepting arbitrary errors. The 1000th refusal and planted-overdepth raises remain useful. The plan's “checked by an invariant” should not imply that `assert_cash_guard_invariants()` compares function bodies or enforces the walkers' arithmetic: it does neither.

**Performance:** executed source inspection confirms the materialized shares query removes the once-per-member call in `overpayment_absorbed_as_of`. It does not establish that the maximum supported line is usable one act at a time. Each position still enumerates the family; shares still read each member at each take-back, and the payment-side `overpayment_split` still has a correlated shares query per ledger row. No near-boundary timing is certified or predicted here. [04-bounded-real-chain.sql](codex-r7-probes/04-bounded-real-chain.sql) supplies a real 20-generation history sample with a 180-second statement timeout; it is explicitly not a 999-generation benchmark. `00` has a 300-second statement timeout and supplements Z6 with direct `reissue_generation` checks.

### S2 — executed source: the expanded agreement tests still exercise only one positive survivor of a shortfall

Z1–Z3 are relevant repairs, but none tests K negative with both R1 and R2 positive. Z4 tests money already hidden at the escheat transition, not own money hidden by a refund return after a legitimate transition. Add 01/02 to the agreement suite and mutation coverage. For B2 flush deferred checks at step 5 before releasing the cover at step 6, so the regression demonstrates the two-act failure rather than only an unfinished transaction.

The APPLY branch now matches the first line containing `ERROR`, which closes the reported whole-stderr matching issue. N212 drops the sibling pass, N213 the escheat own-side check, N214 the void-share check, N215 the payment lock, N216 the make bound, N217/N218 the walker raises, N219 the shares plan pin. The named anchors are pertinent. I found no concrete frozen mutation demonstrably caught for the wrong reason; I did not execute them. Counts and reported timing misses remain author evidence.

## Notes

### N1 — executed authority review; predicted implementation: rulings

K-10's independent bank movements, pending-refund hold-up and tenant-controlled return window remain the governing model (00 W/Y controls). Kyle's 10-30 answer authorizes internal attribution order and requires one customer-wide net display; it does not promise per-source independent capacities will sum to that total. R22's refusal alternative is Ryan's explicit accepted call. Statuses remain forward-only, and returned-credit money still needs an available destination. B2 violates that last escheat requirement despite the original Z4 repair.

R23/AC-44 is an explicitly accepted schema/core boundary, not a new blocker by itself. **For the escheat report in particular, do not treat a per-credit aging row as a net amount approved for remittance.** The contract requires the customer-wide netting step before reporting as well as before refunding. Preserve the underlying dates and attribution when that is implemented. I am evaluating consistency with the supplied product rulings, not offering a legal determination of setoff or dormancy. New B2 is a separate within-family defect even when the core obeys AC-44.

### N2 — predicted: concurrency, roles, isolation and statement shapes

For the reported void/give-back pair, the added common payment mutex precedes K/R on both paths, removing the inversion regardless of UUID order. The `03-C`, `03-A`, `03-B` files exercise exactly that extracted topology in three owner sessions on one clone; they commit no fixtures and all roll back. They do **not** claim to reproduce CR25's actual triggers. Frozen CR25 uses three sessions and its common verdict checks A/B exits and observed blocking; its reported result remains unexecuted here.

Source draws acquire payment-before-credit for payment families; applications acquire their line lock afterward. Returns/cancellations of refunds take the source locks that the next draw awaits; reissue voids retain their immediate predecessor lock in addition to the new payment lock. Source and pool cap queries occur behind the locks. The tested isolation contract refuses non-READ-COMMITTED writes, rather than relying on stale post-lock snapshots. An escheat move takes only its credit lock; the new own-side condition is not, by itself, a substitute for checking later settlement paths (B2). No additional concrete single-act lock cycle is asserted.

Evidence files: 00 for ordinary and owner-history guards; [regression-07](codex-r7-probes/regression-07-catalog-and-invariants.sql) for catalog/privileges; [regression-08](codex-r7-probes/regression-08-copy-arrival.sql) for COPY; [regression-09](codex-r7-probes/regression-09-donation-statement-shapes.sql) for multi-row and writable-CTE caps; [regression-10](codex-r7-probes/regression-10-isolation-pins.sql) for RR/SERIALIZABLE refusals. These are retained author-run controls, not exhaustive proofs over every SQL composition. ENABLE ALWAYS is not protection against a superuser deliberately disabling guards; the depth fixture expressly tests defensive readers after such planting. New B1/B2 use enabled guards and need no such planting.

### N3 — executed review judgment; predicted behavior: residuals R1–R23

| Residual | Assessment |
|---|---|
| R1 ledger-tree bound | Accepted, separate from the now-explicit reissue bound. No new ledger-depth blocker claimed. |
| R2 recorded coordinates | Retained model, including open transactions; 00 Y6 temporal controls. |
| R3 paid/partial lifecycle | Explicitly separate from balances; not a blocker. |
| R4 applications after bill void | Core workflow responsibility; retained. |
| R5 repeated charge-type vocabulary | Maintenance obligation; retained. |
| R6 source-less line classification | Explicit core boundary; retained. |
| R7 allocation/floor/notifications | Explicit core boundary; no new policy inferred. |
| R8 older tests | Retained adaptations; the frozen diff still includes the labelled -25 dispute-fields edit. Not exclusively -23 provenance. |
| R9 tariff service/system matching | Retained core responsibility. |
| R10 deposit refund cap | Retained earlier-patch responsibility. |
| R11 long statements/timeouts | Accepted operational limit; S1 concerns unproven near-boundary usability. |
| R12 return plus status move | Both new probes write both and flush deferred checks; this residual does not excuse B2. |
| R13 one-click cancellation | UI obligation, not a blocker. |
| R14 return-window policy | Explicit K-10 tenant choice. |
| R15 withdrawal restrictions | Descendants now named; 00 original controls retained. |
| R16 one live overpayment | Accepted; B1 uses two legitimate reissues, not two overpayment roots. |
| R17 one instant | Temporal qualification documented; 01/02 use distinct historical recorded instants. |
| R18 erroneous refund return | Accepted terminal-workflow limit; 00 W1. |
| R19 app timestamps | Retained validation-before-stamping rule; 00 W10/Y6. |
| R20 attribution | Authorized order; it does not establish per-source cap equality (B1). |
| R21 cost | Earlier measured examples are not r7 boundary evidence; S1. |
| R22 share-bearing void | Explicitly accepted; 00 Z5 refusal and give-back control. |
| R23 customer-wide pot | Explicitly accepted core boundary, including escheat reporting; see N1. B2 is not cross-payment netting. |

### N4 — executed source and delivery notes

The durable reissue comments now describe remaining money. The revised ledger-reversal COMMENT at 955 says “nor while a reissue ... is applied or has a refund pending” inside a sentence about waiting; change “nor” to “also” to make the hold-up unambiguous. This is wording only, not another behavioral finding.

Eleven SQL files are delivered. Run each standalone file as owner on its own fresh clone with frozen r7 applied and TEMP revoked from PUBLIC, tally_app and tally_core; run the three `03` files together on one such clone in their documented order. No file creates, alters or drops a role. Each ends in ROLLBACK; isolation controls contain two separately rolled-back transactions. Caught errors print SQLSTATE and message; the COPY probe prints its native verbose error and `\errverbose`, never relying on `LAST_ERROR_SQLSTATE`. P0099 notices in draw tests are deliberate rollback sentinels, not refusals by a guard. A setup failure or timeout is not confirmation of a finding. No probe result is executed evidence until the author runs it.
