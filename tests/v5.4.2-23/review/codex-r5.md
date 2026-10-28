# Codex review — v5.4.2-23, round 5

Verdict: **not yet**.

**Executed:** read the brief and checked all six MD5s before substantive review; all matched. Reviewed frozen source, the three round-4 reviews (including the author-run results appended to Codex r4), the design and inventory, the r5 plan/as-built record, DECISION-LOG, and Kyle's K-10 ruling. Did not read either other reviewer's round-5 file. No Docker, psql, CI, race, mutation runner, database apply, or database experiment was run. Only this review and files in `codex-r5-probes/` were written.

**Predicted:** every database outcome, closure assessment, and concurrency conclusion below. “Executed” source findings mean inspection of text, not execution of its SQL. The author's reported 293 checks, 33 race results, 190 mutation catches, strict apply twice and 49 CI steps have **not** been reproduced by this reviewer.

| Frozen file | Executed MD5 |
|---|---|
| patch-23-frozen-r5.sql | 3e29cdb7900ee02fdf4109e29f098849 |
| battery-23-frozen-r5.sql | 8d6f85a3a4c1f4faaf1e6ec8a30fa7ee |
| cash-23-frozen-r5.sh | 09a1a2f432f8f12fddd188ccd2c864e4 |
| mutations-23-frozen-r5.py | 97ed11196a45bc8e3bf7f0c87dc1d741 |
| older-tests-23-frozen-r5.diff | be99c2f963ab9f2177c9f059a4de7e5c |
| patch-23-r4-to-r5.diff | 1b6bdb48dd8b381b7c32d0e7af0633e7 |

Patch references mean the frozen r5 SQL. All probes run in an owner session on a fresh clone with frozen r5 applied and TEMP revoked from PUBLIC, tally_app and tally_core. Each ends in ROLLBACK. Probes 01–04 use the supported superuser history-load facility to give successive acts distinct, finite past instants without committing fixtures. Probe 05 repeats B1 as tally_app with ordinary transaction-start stamps. No role is created, dropped or altered. Caught errors print SQLSTATE and message. The COPY regression prints its native verbose error and `\errverbose`; it does not infer success from LAST_ERROR_SQLSTATE. An unexpected setup failure is not confirmation of any finding.

## Blocking items

### B1 — predicted: reissue before the parent bounce escapes the payment's cap

**Source:** `customer_credit_position_as_of` around 1585 treats refund_reissue issued money as its original amount. `check_cash_source`, 2402–2407 and 2551–2556, associates the shared pool only with an **overpayment** credit. The bounce guards at 765–778 and the payment status guard inspect the direct overpayment credit's applications/pending refunds, not its reissue successors. `cash_drawn_at` counts a reissue as money already given by its predecessor.

Concrete path, with all guards enabled:

1. Post payment 100; hold 100 in overpayment credit K.
2. Refund 30 from K, post that refund, remit 70 and escheat K.
3. Return the refund, move it to reversed and carry 30 into refund_reissue K2. Force the deferred checks: K has nothing left.
4. Return the original payment in full and move it to reversed.
5. Refund and post 30 from K2 **after** that full payment return.

Predicted: all five steps are admitted. At step 4 K has issued 0, given_up 70, carried 30 and remaining −100; K2 still has issued/remaining 30. Step 5 consults K2's fixed amount without the original payment's tree or shared pool. Thus it pays out another 30 after the source has returned completely. The deficit records that result but does not make the new payout lawful under K-10.

The active-credit control is simpler: payment 100 → overpayment 100 → refund 100 → refund returned → reissue 100 while the original credit remains active → parent returned 100 → successor refunded 100. It avoids escheat entirely. This is an internal transfer becoming detached from the cash that supports it, not an earlier bank payout standing under K-10.

R5 addresses **bounce before reissue**, but not **reissue before bounce**. Keep the successor's unspent money and future draws within the underlying cash lineage and its lock/cap contract. Do not solve this by refusing a real bank return merely because an internal successor holds the money; already-paid-out amounts still stand.

**Probes:** [02-reissue-before-bounce.sql](codex-r5-probes/02-reissue-before-bounce.sql), [05-reissue-before-bounce-app.sql](codex-r5-probes/05-reissue-before-bounce-app.sql). Both include active and escheated predecessor variants, positions, and forced deferred checks. The latter requests the ordinary application-role path.

### B2 — predicted: give-back-first-to-credit leaves a surplus beside a deficit, so displayed remaining is not drawable

**Source:** `overpayment_split`, 1493–1506, particularly `absorbed := -least(-r.amount, v_abs)`, versus the pool check at 2587–2612.

Path with distinct recorded instants:

1. Payment 60; overpayment credit 20.
2. Direct refund 40 from the payment, posted.
3. Take back 30 under the payment: the credit absorbs 20; the other 10 becomes the payment's deficit.
4. Give back 20 under that take-back.

Predicted positions after step 4: payment received 50, credited 20, refunded 40, **remaining −10**; credit issued/remaining **20**. Total remaining is correctly 10, but the credit's displayed 20 is not spendable: a refund of 20 is refused by the shared pool, while 10 is admitted. After drawing the actual 10, the positions still show credit +10 and payment −10.

This answers the brief's “does a deficit ever sit on one side while the other still has money to give?” with yes. The aggregate cap prevents excess payout, but the split fails the requirement that each position's remainder equal what its cap admits. The refusal of 20 is correct under K-10; removing the pool guard would be the wrong fix. The allocation of restored money must account for the other side's deficit, or the promised per-source remaining contract must be changed explicitly. This is the r4 reader/cap problem in a new composition, not the accepted one-live-credit restriction.

**Probe:** [01-giveback-deficit.sql](codex-r5-probes/01-giveback-deficit.sql), prints both positions and the split before and after the 10 draw, with the 20 and 10 attempts separately caught.

### B3 — predicted: tied correction rows are split by UUID, allowing a give-back to precede the take-back it undoes

**Source:** `overpayment_split`, 1490–1506, orders by `l.created_at, l.id` without accounting for lineage within a tied instant.

Post payment 100 and hold all 100 as a credit. In one recorded instant, write a +20 take-back and its −20 give-back, in that causal order. Give the give-back a smaller UUID than its parent. The ledger tree correctly nets to zero; all 100 was restored.

Predicted split: the give-back is processed first, when `v_abs = 0`, so absorbs 0. The +20 then absorbs 20. The credit reads 80; the payment reads 20. A subsequent refund of the credit's approved/restored 100 is refused. Swap only the two UUID orderings and the credit reads 100, the payment 0, and the refund of 100 is admitted.

R17 explains taking same-instant draws into account when allocating a take-back. It does not supply a meaningful accounting reason to process a correction before the entry it corrects. Nor does the shared cap restore the credit's missing allocation. Resolve same-instant tree corrections in a causally valid order, or define a netting rule that preserves restoration and money-date behavior. Test both UUID orders, including distinct transaction dates within the tied recorded instant.

**Probe:** [03-tied-corrections.sql](codex-r5-probes/03-tied-corrections.sql), two independent fixtures differing in correction UUID ordering, with later refund attempts. No triggers are disabled.

### B4 — predicted: an allowed finite past status correction rewrites the split and restores money to an escheated credit

**Source:** `cash_drawn_at`, 1431–1434, reconstructs earlier refund participation from the mutable latest `status_recorded_at`. The same-status superuser branch of `enforce_payment_immutable`, 1811–1818, returns before the locks and financial checks. The deferred settlement trigger is `AFTER UPDATE OF status`, not timestamp correction.

Path, using only finite past history coordinates:

1. Payment 60; overpayment credit 20; refund 20 posted and then returned.
2. Flush that return's deferred check while the credit is active.
3. Take back 10 from the parent at instant T. The refund had already returned, so the credit absorbs 10 and holds 10.
4. Remit that 10 and escheat the credit with nothing left.
5. As owner, correct the returned refund's status timestamp to T + 30 seconds, still in the past and before the escheat.

Predicted: step 5 and forced deferred checks succeed. `cash_drawn_at` now considers the old refund outstanding at T, so the 10 take-back shifts from the credit to the payment. The escheated credit's issued rises from 10 to 20, its remittance remains 10, and **remaining becomes +10**. No ledger give-back is inserted, so the new escheated-credit guard is never reached. The past position changes as well.

The r4 future-timestamp path is closed, but “finite and not future” is not sufficient for a timestamp now used to allocate cash between sources. This is within the explicitly supported owner history-correction path; it needs no DDL or disabled trigger. Restrict corrections that cross already-consumed recorded boundaries, or apply the locks and all resulting settlement/cap checks to the affected lineage. Clarify the fixed-as-of claim for supported history loads.

**Probe:** [04-status-history-rewrites-split.sql](codex-r5-probes/04-status-history-rewrites-split.sql), including the initial deferred-check flush, current and past positions, and the timestamp-only update followed by forced checks.

## Round-4 disposition, item by item

**Predicted** closures below are limited to the reported paths. Probe `00-frozen-battery.sql` is the frozen r5 battery with full caught-error notices added; W/V names refer to that deliverable. `regression-*` files are the previous standalone probes adapted to frozen r5; their old scenario comments/labels identify r4 findings, not a claim those bugs still exist.

| Codex r4 item | Disposition | Evidence and limit |
|---|---|---|
| B1 terminal refund tree repaid | **Closed** | W1/W1b/W1c; regression-01 and regression-06. New guard takes the refund lock and rejects either sign after termination. |
| B2 give-back under escheated overpayment | **Closed for that writer** | W5/W5a; regression-02/06. B4 above reaches the same forbidden state through a different writer. |
| B3 bounce plus failed refund cannot settle | **Partly closed** | W6/W7 and regression-03/06 cover bounce first, including zero/negative remainder. New B1 reverses the order. |
| B4 future owner timestamp hides settlement | **Closed for future/non-finite values** | W10–W10e; regression-05. Finite past correction remains new B4. |
| S1 parent position/cap disagreement | **Partly closed** | W2/W3/W4 close the reported simple splits; B2/B3 above still break the broader allocation contract. |
| S2 tests and N170 attribution | **Partly closed** | Executed source: W tests added, N170 renamed accurately, N190/W9 now covers reissue arrival prohibition. New compositions and APPLY attribution caveat remain, S2 below. |
| S3 pending-payment comment | **Closed** | Executed source: reader explains arrival-row existence and atomic posting; regression-11 supplies the observation. |
| N1 rulings | **Partly closed** | Status vocabulary retained; K-10 and remainder refinement sound for W cases, incomplete across successor lineage (B1). |
| N2 concurrency/roles/shapes | **Partly closed** | Refund-tree lock and parent give-back handshake added; isolation regression extended. B1/B4 exclude a universal completeness claim. |
| N3 invariants/provenance | **Closed as a scoped note** | Definitions remain distinguished from function-body correctness; same older-tests MD5. Catalog probe supplied; no result counts certified. |
| N4 residuals | **Partly closed** | R15/R16 documentation improved; R17 now exposes B3. See residual table. |
| N5 probe delivery | **Closed as an executed delivery note** | R4 author execution remains r4 evidence. New probes are delivered here, unexecuted. |

| Opus r4 item | Disposition | Evidence and limit |
|---|---|---|
| B1 partial take-back split/cap | **Partly closed** | W2/W3/W4; B2/B3 remain. The as-built held-money refinement correctly avoids P2's 60-out-of-50 error. |
| B2 refund tree unguarded | **Closed** | W1 and regression-01. |
| S1 reissue predates returned money | **Closed for money date** | W8/W8a; return cause's transaction_date checked before the amount/cap. |
| S2 tests | **Partly closed** | W and new races/mutations target original paths; S2 below lists omissions. |
| N1 second hold after first spent | **Closed as documentation** | Executed source: R16 states this case and direct-payment alternative. No change to one-live-credit contract. |
| N2 commit-time check reach | **Partly closed** | W5 closes the ledger give-back gap; W7 closes the negative-remainder dead end; B4 is an unqueued timestamp update. |
| N3 lock order | **Partly closed** | Direct credit draws now take payment before credit. No universal lock or successor-lineage certification; N2 below. |
| N4 arrival dates | **Closed for reported exception** | W8 adds reissue return-date floor; V10 retains ACH arrival-date behavior. |
| N5 escheated-credit full bounce | **Closed for original shape** | V1/V2/W7 provide related owner-run evidence; B1 concerns a still-held successor, not an earlier remittance. |
| N6 residuals | **Partly closed** | R15/R16 wording addressed; new R17 issue B3. |
| N7 mutations | **Closed as source inventory only** | No mutation execution certified; see S2. |

| Fable r4 item | Disposition | Evidence and limit |
|---|---|---|
| B1 take-back before credit counted twice | **Closed for original path** | W4/W4a excludes pre-credit rows from absorption. Broader split defects are B2/B3. |
| B2 escheated overpayment give-back | **Closed for original writer** | W5a and regression-02/06. |
| B3 RR stale arrival status | **Closed by rejecting that isolation** | Top-of-function pin precedes arrival reads. Extended regression-10 asks for payment/credit arrival rejection at RR and SERIALIZABLE; CR20/20b source covers the two-session case, not executed here. |
| S1 refund tree repaid | **Closed** | W1/W1c and regression-01. |
| S2 R15 wording | **Closed** | Executed source: header describes applications and pending refunds, and what already-paid-out credit money does not block. |
| S3 “either order” reissue comment | **Closed** | Executed source: refund move then reissue stated at 2858–2866. |
| N1 history load born posted | **Closed as documentation** | Executed source: birth commentary says pending, arrival, then move. |
| N2 lock order | **Partly closed** | Main payment/credit order updated. Earlier warning about a donation also being a reversal is superseded by the frozen CHECK excluding donation from reversal types. Arbitrary multi-act transactions remain retryable. |
| N3 ledger undo without refund status | **Closed as retained residual** | R12 remains explicit; B1/B4 above do perform the refund's status move. |
| N4 reissue has no arrival tree | **Closed as retained contract** | V7/W9 and regression-11; this absence is also why later parent money changes need an explicit lineage mechanism (B1). |
| N5 second live hold | **Closed as documentation** | R16. |
| N6 credited absorbs all prior take-backs | **Closed for original predicate** | W4; B3 qualifies tied rows. |
| N7 mutation coverage | **Partly closed** | New named legs added; new compositions absent. |
| N8 residuals | **Partly closed** | Original R1–R16 scoped decisions retained; R17 has B3. |

## Should-fix items

### S1 — executed source finding: remaining stale descriptions of reissue amount and bounce blocking

The column comment on `reissues_refund_id` near 1370 still says “Its amount is the refund's”; `enforce_cash_draw`'s COMMENT near 2847 still says it carries exactly the refund. Both conflict with `least(-v_refund.amount, v_left)`. `enforce_ledger_reversal`'s COMMENT near 837 still says a payment's posting-entry undo waits while it is held as a credit, unlike the current guard and corrected R15. Update these durable database descriptions with the final contracts. This is a textual finding, not a new database experiment.

### S2 — executed source finding: coverage does not establish the new compositions or universal first-failure attribution

W2e/W2f checks giving money back when neither side has a deficit. W6/W7 tests parent return before refund reissue. W10 rejects future/infinite stamps, not a finite past correction crossing a split boundary. W12 tests same-instant draws, not parent/child correction UUID ordering. None covers B1–B4; add the delivered probes' positive and negative controls to the permanent suite and assign mutations to the newly required behavior.

N170's renamed shape-check mutation and N190/W9 repair the r4 label/behavior mismatch. N145's retirement is justified for the direct overpayment draw/bounce pair by the new parent lock; N191 is mapped to CR18 (CR22 also exercises the lock). N181 is mapped to W3a, not W12; that is explicitly documented in its label. N152 now maps to W11's recorded-order leg rather than pretending V7i reaches the cap after the new amount check.

The APPLY branch still accepts `phrase in a.stderr`; it does not parse the first error. The behavioral branch does enforce the named first failure. Therefore the blanket statement “each at its named check as the first failure” is stronger than the runner's APPLY logic. N164 still removes the chosen-time refusal while leaving the fallback retry refusal; its catch establishes a diagnostic distinction, not admission of an unsafe row. No claim is made here that any frozen mutation actually passed for an unrelated reason; execution was prohibited.

The frozen older-tests diff remains byte-identical by MD5 to r4. It still contains the explicitly -25 dispute-field edit, so it is not solely -23 provenance. The cancellation-before-bounce and lineage/sign/date adaptations follow the changed contracts; the C19 disabled-trigger fixture is a deliberate pre-rule invalid-history test, not ordinary writer evidence.

## Notes

### N1 — executed authority assessment; predicted implementation: K-10 and Ryan's decisions

The as-built B2 refinement is right for the motivating P2: 60 received, 20 already refunded through a credit, 10 returned leaves 30, not 40, to refund. Charging that return against an already-empty credit while leaving a spendable 40 on the payment would violate Kyle's cap. W3 and the shared pool address that example. A single shared split is also the right consistency direction; the formulas need the additional B2/B3 cases.

Ryan's removal of refunded/donated statuses is retained. His reissue option is implemented without a duplicate arrival row. Applying K-10 to carry only the positive remainder, at most the returned refund, is justified for **bounce first**: a fully returned payment supplies no new money just because its refund later returns; an existing remittance remains debt. W6/W7 and regression-03 request those results. This does not justify severing the successor from a later return of the same original payment (B1), or leaving a positive remainder on an escheated source (B4).

### N2 — predicted: locks, roles, isolation, statement shapes

For the direct payment/overpayment pair, the writer bodies show payment → credit for a credit draw, parent → credit for a give-back, tree → refund for a row under a refund's posting entry. The ledger pin now precedes the source reads. Both split cap and shared cap are inside `check_cash_source` after the applicable source locks. Removing the take-back's redundant credit lock is reasonable when all relevant direct credit draws first take the payment lock.

This is not proof that every money change is covered. A refund leaving an overpayment credit still locks its own refund then the credit; it does not acquire the parent lock. That generally frees money conservatively for a parent-only draw, but the current source code does not support saying that every change to the shared pool takes the parent mutex. B4's same-status history correction takes neither financial lock. B1's successor draw never joins the original payment's mutex/cap. See probes 02/04/05 and `regression-07-catalog-and-invariants.sql` for concrete outcomes and installed writer definitions to inspect.

No new single-act deadlock cycle is asserted here. UPDATE row locks precede advisory locks; opposite-order multi-act transactions and multi-row statements still cannot be certified deadlock-free. CR21 and CR22 check the intended new waits in source. Their results were not reproduced. CR20's scheduling uses sleeps rather than an explicit snapshot barrier; rejection by an unconditional isolation pin is useful evidence, but is not by itself proof of the advertised stale-snapshot interleaving.

`regression-10-isolation-pins.sql` asks for RR and SERIALIZABLE rejection of status moves, cap entry and both arrival types. `regression-06-app-role-paths.sql`, new probe 05 and the frozen battery exercise tally_app from owner sessions. `regression-07` supplies invariant/grant checks for the read-only and seal-role boundaries. `regression-09` covers multi-row and writable-CTE donation corrections; `regression-08` covers COPY's late arrival with its own error output. The frozen triggers are row-level and ALWAYS; that design is not a substitute for a universal statement-shape proof. The concrete single-session B1 and owner B4 paths already prevent a “no path around any rule” conclusion.

### N3 — executed source assessment: invariant scope

The invariant inventory pins trigger definitions/enabled state, selected constraints and indexes, grants, counter removal and walk settings. It explicitly does not pin function bodies. The new split helpers do not make a mathematical cash invariant merely by being called by every reader. B1–B4 can occur with the frozen trigger/constraint inventory intact. Probe `regression-07` requests the catalog and invariant baseline; `00-frozen-battery.sql` requests the frozen functional checks with full error notices. Neither has been run here.

### N4 — executed review judgment: residuals R1–R17

| Residual | Assessment |
|---|---|
| R1 depth/performance bound | Not blocking as an accepted scope decision; no timing claim reproduced. |
| R2 fixed recorded coordinates | Contract needs qualification/enforcement for supported history correction; B4 is a blocker, not an authorized escape. |
| R3 paid/partial lifecycle | Not blocking; separate app lifecycle from derived money. |
| R4 undo applications on bill void | Not blocking; explicit workflow responsibility. |
| R5 duplicated charge-type list | Not blocking; maintenance obligation. |
| R6 source-less line classification | Not blocking; accepted core boundary. |
| R7 allocation/floor/notification | Not blocking; no new policy decision inferred. |
| R8 older-test adaptations | Not blocking; provenance caveat S2. |
| R9 tariff service/system matching | Not blocking as explicitly retained boundary. |
| R10 deposit refunds | Not blocking as retained -15 responsibility. |
| R11 long statement/timeout | Not blocking as accepted operational requirement; unmeasured. |
| R12 ledger return plus status move | Not blocking for the atomic workflow. B1/B4 do not omit the move. |
| R13 one-click cancel | Not blocking; UI requirement. |
| R14 tenant return-window policy | Not blocking; K-10 explicitly leaves it outside this schema rule. |
| R15 withdrawal restrictions | Revised wording addresses r4. Does not excuse the successor or restored-money paths above. |
| R16 one live overpayment | Not blocking by itself; cannot justify UUID-dependent relocation of an existing holding. |
| R17 same recorded instant | Acceptable only with sound tie semantics. B3 blocks the present implementation; shared cap alone does not repair its allocation. |

### N5 — executed delivery; predicted database outcomes

The new finding probes are 01–05. Probe 00 carries all frozen battery assertions. Ten `regression-*` files retain owner-run closure, application-role, isolation, COPY, statement-shape and catalog evidence requests. No database results have been added or represented as executed. Each file ends in ROLLBACK; all caught exceptions in the delivered SQL print SQLSTATE and message. Compare the actual positions and named errors with this review: an `ADMITTED SQLSTATE=00000` notice describes acceptance, not correctness.

## Probe outputs (run by the author, 2026-10-28, fresh clone of tally with frozen r5 strict-applied)

Codex finished its review (no usage limit this round). B1–B4 reproduced (executed); the regression probes show round 4's blockers stay closed (regression-01s "second refund from reissue ADMITTED" is the reissue's own legitimate refund: the re-payment under the old refund row is caught).

```
### 01-giveback-deficit
NOTICE:  after give-back payment={"amount":60.00,"received":50.00,"applied":0,"credited":20.00,"refunded":40.00,"remaining":-10.00}
NOTICE:  after give-back credit={"amount":20.00,"issued":20.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":20.00}
NOTICE:  after give-back split=[{"id": "f4d26fce-b355-4cc5-808c-0908ec84131a", "amount": 30.00, "on_date": "2026-03-14", "absorbed": 20.00, "created_at": "2026-10-27T17:09:51.098559+00:00"}, {"id": "a1e4fe2a-de18-4be7-a8c4-2992a5b661ae", "amount": -20.00, "on_date": "2026-03-15", "absorbed": -20.00, "created_at": "2026-10-27T17:
NOTICE:  credit refund 20 CAUGHT SQLSTATE=23514 MESSAGE=payment 7ffa2bb9-9341-4c69-b982-73d933684432 and its overpayment credit: on 2026-03-17 what they gave and what was taken back on the ledger would come to 70.00, more than the payment's 60.00 (R-06 cap, K-10; v5.4.2-23)
NOTICE:  credit refund actual 10 ADMITTED SQLSTATE=00000
NOTICE:  after actual 10 drawn payment={"amount":60.00,"received":50.00,"applied":0,"credited":20.00,"refunded":40.00,"remaining":-10.00}
NOTICE:  after actual 10 drawn credit={"amount":20.00,"issued":20.00,"applied":0,"refunded":10.00,"given_up":0,"carried":0,"remaining":10.00}
NOTICE:  after actual 10 drawn split=[{"id": "f4d26fce-b355-4cc5-808c-0908ec84131a", "amount": 30.00, "on_date": "2026-03-14", "absorbed": 20.00, "created_at": "2026-10-27T17:09:51.098559+00:00"}, {"id": "a1e4fe2a-de18-4be7-a8c4-2992a5b661ae", "amount": -20.00, "on_date": "2026-03-15", "absorbed": -20.00, "created_at": "2026-10-
### 02-reissue-before-bounce
NOTICE:  remit=0 parent full return ADMITTED SQLSTATE=00000
NOTICE:  after parent return payment={"amount":100.00,"received":0.00,"applied":0,"credited":0.00,"refunded":0,"remaining":0.00}
NOTICE:  after parent return credit={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":0,"carried":100.00,"remaining":-100.00}
NOTICE:  after parent return split=[{"id": "dd326fe2-c47e-48d0-9405-507ad45b2202", "amount": 100.00, "on_date": "2026-03-19", "absorbed": 100.00, "created_at": "2026-10-27T17:12:51.233008+00:00"}]
NOTICE:  successor position={"amount":100.00,"issued":100.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":100.00}
NOTICE:  remit=0 refund AFTER parent full return ADMITTED SQLSTATE=00000
NOTICE:  remit=70 parent full return ADMITTED SQLSTATE=00000
NOTICE:  after parent return payment={"amount":100.00,"received":0.00,"applied":0,"credited":0.00,"refunded":0,"remaining":0.00}
NOTICE:  after parent return credit={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":70.00,"carried":30.00,"remaining":-100.00}
NOTICE:  after parent return split=[{"id": "0d3d70e1-bb30-463d-810f-b9d66612b953", "amount": 100.00, "on_date": "2026-03-19", "absorbed": 100.00, "created_at": "2026-10-27T17:30:51.233008+00:00"}]
NOTICE:  successor position={"amount":30.00,"issued":30.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":30.00}
NOTICE:  remit=70 refund AFTER parent full return ADMITTED SQLSTATE=00000
### 03-tied-corrections
NOTICE:  UUID ordering variant 1 payment={"amount":100.00,"received":100.00,"applied":0,"credited":80.00,"refunded":0,"remaining":20.00}
NOTICE:  UUID ordering variant 1 credit={"amount":100.00,"issued":80.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":80.00}
NOTICE:  UUID ordering variant 1 split=[{"id": "00000000-0000-4000-8000-00000000fa01", "amount": -20.00, "on_date": "2026-03-15", "absorbed": 0, "created_at": "2026-10-27T17:06:51.36955+00:00"}, {"id": "00000000-0000-4000-8000-00000000fa02", "amount": 20.00, "on_date": "2026-03-14", "absorbed": 20.00, "created_at": "2026-10-27T1
NOTICE:  variant 1 credit refund 100 CAUGHT SQLSTATE=23514 MESSAGE=credit e51e8ebd-5674-4bc6-8279-25211fdbb3ec: on 2026-03-17 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 120.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
NOTICE:  UUID ordering variant 2 payment={"amount":100.00,"received":100.00,"applied":0,"credited":100.00,"refunded":0,"remaining":0.00}
NOTICE:  UUID ordering variant 2 credit={"amount":100.00,"issued":100.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":100.00}
NOTICE:  UUID ordering variant 2 split=[{"id": "00000000-0000-4000-8000-00000000fb01", "amount": 20.00, "on_date": "2026-03-14", "absorbed": 20.00, "created_at": "2026-10-27T17:13:51.36955+00:00"}, {"id": "00000000-0000-4000-8000-00000000fb02", "amount": -20.00, "on_date": "2026-03-15", "absorbed": -20.00, "created_at": "2026-10
NOTICE:  variant 2 credit refund 100 ADMITTED SQLSTATE=00000
### 04-status-history-rewrites-split
NOTICE:  escheated with zero left payment={"amount":60.00,"received":50.00,"applied":0,"credited":10.00,"refunded":0,"remaining":40.00}
NOTICE:  escheated with zero left credit={"amount":20.00,"issued":10.00,"applied":0,"refunded":0,"given_up":10.00,"carried":0,"remaining":0.00}
NOTICE:  escheated with zero left split=[{"id": "7bca6c87-c08d-4487-8281-a3fc91d3a7e9", "amount": 10.00, "on_date": "2026-03-14", "absorbed": 10.00, "created_at": "2026-10-27T17:11:51.485943+00:00"}]
NOTICE:  past credit before correction={"amount":20.00,"issued":10.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":10.00}
NOTICE:  past-only status timestamp correction and deferred checks ADMITTED SQLSTATE=00000
NOTICE:  after timestamp correction payment={"amount":60.00,"received":50.00,"applied":0,"credited":20.00,"refunded":0,"remaining":30.00}
NOTICE:  after timestamp correction credit={"amount":20.00,"issued":20.00,"applied":0,"refunded":0,"given_up":10.00,"carried":0,"remaining":10.00}
NOTICE:  after timestamp correction split=[{"id": "7bca6c87-c08d-4487-8281-a3fc91d3a7e9", "amount": 10.00, "on_date": "2026-03-14", "absorbed": 0.00, "created_at": "2026-10-27T17:11:51.485943+00:00"}]
NOTICE:  past credit after correction={"amount":20.00,"issued":20.00,"applied":0,"refunded":20.00,"given_up":0,"carried":0,"remaining":0.00}
### 05-reissue-before-bounce-app
NOTICE:  remit=0 parent full return ADMITTED SQLSTATE=00000
NOTICE:  after parent return payment={"amount":100.00,"received":0.00,"applied":0,"credited":0.00,"refunded":0,"remaining":0.00}
NOTICE:  after parent return credit={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":0,"carried":100.00,"remaining":-100.00}
NOTICE:  after parent return split=[{"id": "31d80956-75ae-4130-bcf0-bf5b85787803", "amount": 100.00, "on_date": "2026-03-19", "absorbed": 100.00, "created_at": "2026-10-28T17:00:51.613047+00:00"}]
NOTICE:  successor position={"amount":100.00,"issued":100.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":100.00}
NOTICE:  remit=0 refund AFTER parent full return ADMITTED SQLSTATE=00000
NOTICE:  remit=70 parent full return ADMITTED SQLSTATE=00000
NOTICE:  after parent return payment={"amount":100.00,"received":0.00,"applied":0,"credited":0.00,"refunded":0,"remaining":0.00}
NOTICE:  after parent return credit={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":70.00,"carried":30.00,"remaining":-100.00}
NOTICE:  after parent return split=[{"id": "147db3f1-2ccb-4374-86b9-4173c6466012", "amount": 100.00, "on_date": "2026-03-19", "absorbed": 100.00, "created_at": "2026-10-28T17:00:51.613047+00:00"}]
NOTICE:  successor position={"amount":30.00,"issued":30.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":30.00}
NOTICE:  remit=70 refund AFTER parent full return ADMITTED SQLSTATE=00000
### regression-01-ended-refund-tree
NOTICE:  B1 CAUGHT SQLSTATE=23001 MESSAGE=account_ledger aea85ca1-795d-4966-99f4-1277d345cc96 is under refund c833ab0d-9181-4497-9879-68b20d9f1126's posting row, and the refund is reversed: nothing more goes under it — a re-sent refund is a new refund (guard the act; CI-013, v5.4.2-23)
NOTICE:  B1 reissue position={"amount":30.00,"issued":30.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":30.00}
NOTICE:  B1 second refund from reissue ADMITTED SQLSTATE=00000
### regression-02-escheated-overpayment-giveback
NOTICE:  B2 CAUGHT SQLSTATE=23001 MESSAGE=account_ledger 2fc68ce6-f778-42ec-a03b-b8d04dde25f5 gives money back under payment 22b8df50-4efb-435a-8ecb-07422ca5b608, whose overpayment credit a884043d-a476-4018-b810-372893c17889 is escheated: nothing comes back to an escheated credit — post a new payment (Ryan, 2026-10-21; v5.4.2-23
NOTICE:  B2 credit status=escheated position={"amount":100.00,"issued":80.00,"applied":0,"refunded":0,"given_up":80.00,"carried":0,"remaining":0.00}
### regression-03-reissue-after-parent-bounce
NOTICE:  B3 parent take-back=100 old credit position={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":-70.00}
NOTICE:  B3 take-back=100 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit 0ea24c64-0644-4a6a-9a58-be966e3c53df reissues 9d2f6913-6bd1-4fa5-b87b-61cc628a28de for 30.00: it carries what came back (30.00) as far as it is what is left on the credit (-70.00 before it) (Ryan, 2026-10-21; K-10; v5.4.2-23)
NOTICE:  B3 take-back=100 deferred settlement ADMITTED SQLSTATE=00000, reissue count=0
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
NOTICE:  B3 parent take-back=30 old credit position={"amount":100.00,"issued":70.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":0.00}
NOTICE:  B3 take-back=30 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit 8da16c73-4672-4d8f-a883-32adb439a669 reissues ba398cd0-00a0-4477-8634-a864ca37bcc3 for 30.00: it carries what came back (30.00) as far as it is what is left on the credit (0.00 before it) (Ryan, 2026-10-21; K-10; v5.4.2-23)
NOTICE:  B3 take-back=30 deferred settlement ADMITTED SQLSTATE=00000, reissue count=0
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
### regression-05-superuser-settlement-clock
NOTICE:  B4 CAUGHT SQLSTATE=23514 MESSAGE=payment fbc833d6-2a66-4c1d-b63e-00328f6e98a5: status_recorded_at 2026-10-29 17:00:52.123676+00 is not a time already reached — a status is recorded at a finite time already reached (Q1 (a), v5.4.2-23)
### regression-06-app-role-paths
NOTICE:  B1 CAUGHT SQLSTATE=23001 MESSAGE=account_ledger 04b99649-06a4-49a3-a7a6-873d5de2d913 is under refund f775d9fa-aa05-43cd-b5e9-f8d0eda5d97b's posting row, and the refund is reversed: nothing more goes under it — a re-sent refund is a new refund (guard the act; CI-013, v5.4.2-23)
NOTICE:  B1 reissue position={"amount":30.00,"issued":30.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":30.00}
NOTICE:  B1 second refund from reissue ADMITTED SQLSTATE=00000
NOTICE:  B2 CAUGHT SQLSTATE=23001 MESSAGE=account_ledger 86f91ce0-c2e5-458a-9936-64f6174d63da gives money back under payment 77ce2594-e01c-42ec-a9cb-3305cdf66e80, whose overpayment credit 57725dd5-21a3-486a-811f-7c40e29d05da is escheated: nothing comes back to an escheated credit — post a new payment (Ryan, 2026-10-21; v5.4.2-23
NOTICE:  B2 credit status=escheated position={"amount":100.00,"issued":80.00,"applied":0,"refunded":0,"given_up":80.00,"carried":0,"remaining":0.00}
NOTICE:  B3 parent take-back=100 old credit position={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":-70.00}
NOTICE:  B3 take-back=100 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit de170e8a-9cf2-48bb-824e-aec9ebf89c0d reissues 0bb2a6c5-0818-4339-a683-907126c6a3d6 for 30.00: it carries what came back (30.00) as far as it is what is left on the credit (-70.00 before it) (Ryan, 2026-10-21; K-10; v5.4.2-23)
NOTICE:  B3 take-back=100 deferred settlement ADMITTED SQLSTATE=00000, reissue count=0
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
NOTICE:  B3 parent take-back=30 old credit position={"amount":100.00,"issued":70.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":0.00}
NOTICE:  B3 take-back=30 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit dda32e8a-a5ad-48e3-bd98-e2b5dcd9bb8c reissues b96b645c-1de7-4e51-8adf-f8aed15eedb9 for 30.00: it carries what came back (30.00) as far as it is what is left on the credit (0.00 before it) (Ryan, 2026-10-21; K-10; v5.4.2-23)
NOTICE:  B3 take-back=30 deferred settlement ADMITTED SQLSTATE=00000, reissue count=0
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
NOTICE:  S1 payment position={"amount":100.00,"received":80.00,"applied":0,"credited":20.00,"refunded":0,"remaining":60.00}
NOTICE:  S1 credit position={"amount":40.00,"issued":20.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":20.00}
NOTICE:  S1 direct refund 60 ADMITTED SQLSTATE=00000
### regression-07-catalog-and-invariants
NOTICE:  baseline invariants ADMITTED SQLSTATE=00000
### regression-08-copy-arrival
COPY probe: expected native ERROR 23514 (still pending); the following error is the probe result, not LAST_ERROR_SQLSTATE.
ERROR:  23514: account_ledger 6f315ac4-3c40-4147-80c3-42e596d876e0 posts payment copy-voided, which is voided: a posting row is written for a payment still pending, before its move to posted (R-05, v5.4.2-23)
error: ERROR:  23514: account_ledger 6f315ac4-3c40-4147-80c3-42e596d876e0 posts payment copy-voided, which is voided: a posting row is written for a payment still pending, before its move to posted (R-05, v5.4.2-23)
```
