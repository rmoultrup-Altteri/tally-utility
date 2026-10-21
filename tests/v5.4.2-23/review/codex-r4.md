# Codex review — v5.4.2-23, round 4

Verdict: **not yet**.

**Executed:** read the brief, then checked all six frozen MD5s before substantive review. All matched. Reviewed source only; no Docker, psql, CI, race script, mutation runner, database apply or database experiment was run. Did not read `opus-r4.md` or `fable-r4.md`. Read the three round-3 reviews, including the author-added results in Codex r3, the r4 plan, design/inventory, DECISION-LOG and Kyle's K-10 ruling. The source review and writing/static inspection of the delivered probes are executed work; **every database outcome, closure assessment and concurrency conclusion below is predicted**, not reproduced.

| Frozen file | Executed MD5 |
|---|---|
| patch-23-frozen-r4.sql | e4c343f57dc767770dde8d746e9bee3c |
| battery-23-frozen-r4.sql | 4c8f04ddc0fdf1c872b226acf12aa4cc |
| cash-23-frozen-r4.sh | 26c88beead259f132fed05732dedc5eb |
| mutations-23-frozen-r4.py | c3f6b89826442a0d61d728546f5b1e33 |
| older-tests-23-frozen-r4.diff | be99c2f963ab9f2177c9f059a4de7e5c |
| patch-23-r3-to-r4.diff | 26c563b64c89ac678d7d7dc09b706a33 |

Patch line references below mean the frozen r4 file. Probe links are author-run evidence requests. Each standalone probe starts in an owner session on a fresh clone with frozen r4 applied and clone TEMP revoked as required. Each ends in ROLLBACK. Probe 06 temporarily assumes tally_app; no probe creates, drops or alters a role. Caught errors print SQLSTATE and the full message. Probe 08 prints COPY's native verbose error and `\errverbose`, without interpreting LAST_ERROR_SQLSTATE.

## Blocking items

### B1 — predicted: a terminal returned refund can be paid out again through its old ledger tree, while its reissue remains spendable

**Source:** `enforce_ledger_reversal`, 695–764. The source-state branches recognize roots of type payment/deposit, credit_issued and donation. They never recognize a root of type **refund**. X2 alone permits reversing the refund's return.

Concrete path, with all guards enabled:

1. Issue credit 100; post refund 30; remit 70 and escheat the credit.
2. Reverse the refund's +30 posting with −30, move the refund to reversed, and issue the required refund_reissue credit 30. Force the deferred settlement check: it passes.
3. Insert an adjustment +30 reversing the refund's −30 return.
4. Refund the new credit for 30 and post that refund too.

Step 3 is predicted admitted: it obeys both the refund tree's cap and the return row's cap. The old refund now stands at +30 again but remains terminal/reversed, so it does not draw on the original credit. The reissue still has issued=30 and can fund step 4. The two outgoing refunds then stand for a total of 60 against the one returned 30. No new UPDATE of refund status occurs at step 3, so the deferred settlement trigger does not repair this.

This is the refund counterpart of V15's reinstated bounced payment. The old refund's return must not be undone into an uncounted outgoing payment. Handle the act under the appropriate source lock, with explicit rules for already-carried money; a new instrument must be a new capped refund.

**Probes:** [01-ended-refund-tree.sql](codex-r4-probes/01-ended-refund-tree.sql), repeated as tally_app in [06-app-role-paths.sql](codex-r4-probes/06-app-role-paths.sql).

### B2 — predicted: a give-back under a payment restores money to its escheated overpayment credit

**Source:** payment-root negative branch at 700–707 versus the credit locks in its positive branch at 715–717; overpayment `issued` reader at 1410–1415.

Concrete path:

1. Post payment 100 and hold all 100 in an overpayment credit.
2. Take back 20 under the payment's posting entry, leaving the payment status posted. The credit now has issued=80.
3. Remit 80 and move the credit to escheated: nothing remains.
4. Reverse the take-back with −20 under its +20 adjustment.

Step 4 is predicted admitted because the payment is still posted. Its branch neither locks nor checks the overpayment credit. The credit's derived issued returns to 100, given_up remains 80, and **the escheated credit now has remaining=20**. There is no refund status update to queue the settlement check; forcing all deferred constraints does not supply the missing guard.

The new model makes the payment's descendants money changes on its credit too. Give-backs must participate in that credit's lock/status contract, just as take-backs now do. Checking only a direct credit_issued root is incomplete. This is outside the accepted K-10 negative-balance case: it restores positive money to an ended credit.

**Probes:** [02-escheated-overpayment-giveback.sql](codex-r4-probes/02-escheated-overpayment-giveback.sql), probe 06 application-role variant.

### B3 — predicted: K-10 through an escheated overpayment conflicts with the required refund reissue

**Source:** overpayment arrival-tree cap at 2234–2246 and 2334–2358; reissue calls that cap at 2546; settlement checks only `remaining = 0` at 2590–2606.

Start with payment 100, overpayment credit 100, posted refund 30 and remittance 70; the credit is escheated. Then take back the parent payment and return the refund:

| Parent take-back | After the refund returns, without a reissue | Attempt to reissue 30 | Deferred settlement without a reissue |
|---|---|---|---|
| 100 | issued 0, given_up 70, remaining −70 | Refused: remittance 70 + take-back 100 + reissue 30 exceeds 100 | Refused: remaining is not zero |
| 30 | issued 70, given_up 70, remaining 0 | Refused: 70 + 30 + 30 exceeds 100 | **Admitted with no refund_reissue row** |

The full-return variant has no lawful completion for the real refund failure: neither omitting nor adding the required reissue can satisfy the guards. The partial-return variant silently treats an unrelated deficit as the required disposition of the returned refund. `remaining = 0` is not proof that this refund was carried into a new credit naming it.

Ryan's decision requires that concrete successor, for the refund's amount; K-10 permits the earlier outflows to stand when the parent bounces. Those two rules need a consistent treatment of the resulting debt and returned cash. Requiring an aggregate zero and also treating the reissue as an ordinary draw against the reduced overpayment cannot implement both. Do not resolve this by blocking the earlier real bank return. Check the refund's actual successor/lineage, and make its accounting compatible with the K-10 deficit.

**Probes:** [03-reissue-after-parent-bounce.sql](codex-r4-probes/03-reissue-after-parent-bounce.sql), probe 06 application-role variant. Both variants explicitly force the deferred check; each variant rolls back locally before the final ROLLBACK. The parent take-back is a ledger act, so this reproduction does not depend on moving the parent to nsf.

### B4 — predicted: an allowed superuser timestamp bypasses the deferred reissue requirement

**Source:** superuser status timestamp exception at 1647–1649; the position's refund predicate at 1422–1425; settlement's use of clock_timestamp at 2597–2599.

On an otherwise ordinary goodwill-credit 100 / posted-refund 30 / remittance 70 / escheated sequence, return the refund and move it to reversed with `status_recorded_at = clock_timestamp() + interval '1 day'`, without creating a reissue. This is an owner history-load path, with triggers enabled, not a disabled-trigger or DDL bypass.

The move preserves the supplied timestamp. The deferred reader still counts the refund because its exit timestamp is later than the check's wall-clock instant. It therefore sees zero remaining and is predicted to pass. A position read after that timestamp shows 30 stranded on the escheated credit, and no trigger fires when time passes.

The commit invariant needs current structural evidence of the returned refund's disposition, not a temporally filtered position that an admitted history timestamp can hide. Also reject future/non-finite status timestamps if they are not valid history. A superuser may intentionally disable guards, but this path requires none of that and falls within the explicitly supported history-load exception.

**Probe:** [05-superuser-settlement-clock.sql](codex-r4-probes/05-superuser-settlement-clock.sql). It explicitly skips if the clone owner is not superuser.

## Should-fix items

### S1 — predicted: the payment reader reduces its held credit after a take-back, but the payment cap does not

**Source:** `payment_position_as_of` 1374–1382 versus `cash_source_draws` 2108–2110 and the cap at 2334–2358.

Payment 100; overpayment credit 40; partial take-back 20. The payment reader reports received=80, credited=20, remaining=60. Its credit reports issued=20, remaining=20. A new direct refund of 60 is nevertheless predicted refused: the payment cap counts the credit's original 40 plus take-back 20 plus refund 60 = 120. It allows only 40 of the displayed 60.

This creates an additional usability restriction beyond the stated R15/R16 decisions. Use a consistent dated allocation of the take-back in both the parent reader and cap. Merely reducing the credit's current amount in one aggregate is insufficient if earlier and later money dates differ.

**Probes:** [04-parent-position-cap.sql](codex-r4-probes/04-parent-position-cap.sql), probe 06 application-role variant.

### S2 — executed source finding: the new tests do not cover these compositions, and N170's label does not describe its mutation

V1/V2 test full parent bounces with full/partial refunds through a credit. V7 tests reissue from a goodwill credit. They do not combine escheated **overpayment**, parent take-back and returned refund (B3), or restore a terminal refund's ledger tree after reissue (B1). V15b checks a direct credit_issued tree, not B2's inherited arrival tree. Add B1–B4/S1, including their negative controls and intended first-failure attribution.

N170 is labelled “a refund_reissue credit posts a credit_issued row”, but it drops `customer_credits_reissue_check` and expects an APPLY invariant failure. It does not remove the ledger writer's prohibition on issuing a refund_reissue credit. That prohibition deserves its own behavioral case and mutation; [11-reissue-arrival-and-pending-reader.sql](codex-r4-probes/11-reissue-arrival-and-pending-reader.sql) supplies the negative case.

The APPLY branch still matches its phrase anywhere in stderr, unlike the behavioral branch's first-failure attribution. Do not describe every APPLY catch as proof of the named behavioral failure. N164 removes the chosen-time arrival-order branch, but the fallback retry branch remains; V14 can detect the changed SQLSTATE without an unsafe row being admitted. This is a useful diagnostic contract check, not a substitute for a missing-lock/visibility race. Similarly N146 is attributed to S7c, before a bounce, rather than demonstrating the bounce arithmetic. No mutation execution or score is certified here.

### S3 — executed source finding / predicted reader behavior: pending-payment wording remains inaccurate

The payment reader's comment still says “nothing while pending” (1357–1359 and 1390), while its SQL reads the posting tree without that status filter. Fable r3 N1 remains open as documentation. The meaningful distinction is arrival-row existence; a pending payment with its arrival row already written can read received money. Probe 11 prints that case. State the atomic posting workflow assumption explicitly.

## Round-3 disposition, item by item

**Predicted** unless explicitly marked executed. “Closed” is limited to the reported path, not certification of every adjacent composition. Probe [00-frozen-battery.sql](codex-r4-probes/00-frozen-battery.sql) is the frozen battery with full caught-error notices added; named V/S/R checks below refer to that delivered probe. It has not been run. Probe 09 extends donation closure to multi-row and writable-CTE statements.

| Codex r3 item | Disposition | Evidence / qualification |
|---|---|---|
| B1 donation correction skips cap; donation undo after escheat | **Closed for both reported paths** | Donation descendants call check_cash_source with donation/undo by sign; V8, V5; probe 09. |
| B2 pending/posted refund after escheat | **Partly closed** | V6 prevents pending-refund escheat; V7 supplies normal reissue. B1/B3/B4 above prevent general closure of the returned-refund model. |
| B3 draw before arrival money date | **Closed for reported payment and credit paths** | V10/V10a/V10b use the arrival entry's date in the cap; this preserves delayed ACH settlement. |
| S1 prior K-10 deficit vetoes a later draw | **Closed for reported path** | V11; cap filters dates on/after p_on. New S1 above concerns parent/credit accounting, not an old date. |
| S2 missing tests, COPY, race/mutation qualifications | **Partly closed (executed inventory)** | V section, CR18/18b/19 and N141–170 added; multi-row/CTE donation and COPY supplied here; new S2 remains. |
| N1 K-10 and status vocabulary | **Partly closed as implementation** | Original direct example retained; overpayment V1/V2 added; B3 prevents composition with reissue. Vocabulary decision retained. |
| N2 caps/locks/statement shapes | **Partly closed** | Donation and positive parent-bounce paths now participate; B1/B2 remain missing writer participation. Probes 07/09/10. |
| N3 invariants/test provenance | **Partly closed (executed source)** | New trigger/index/constraint definitions pinned; function-body logic is expressly outside invariant coverage; N170/APPLY caveats above. Older diff unchanged. |
| N4 residual decisions | **Closed as scoped decisions (executed judgment)** | Assessment below; no residual authorizes B1–B4. |

| Opus r3 item | Disposition | Evidence / qualification |
|---|---|---|
| B1 O1 donation undo after escheat | **Closed** | V5 and the donation descendant guard. |
| B1 O2 escheat with pending refund then cancel | **Closed** | V6 prevents the initial escheat. |
| B1 O3 posted refund returns after escheat | **Partly closed** | V7 closes the simple case; B1/B3/B4 qualify it. |
| B2 O4/O5 arrival for voided payment/cancelled refund | **Closed for reported paths** | V9/V9b, source lock then pending check; CR19 source coverage; probe 08 COPY. |
| B3 overpayment credit blocks parent bounce | **Closed for original bounce path** | V1/V2 and both status/ledger legs; B3 above is the later refund-return composition. |
| S1 recorded order misses arrival descendants | **Closed for original path** | V14; check_cash_source scans ledger_tree_ids(v_entry). |
| S2 test coverage | **Partly closed (executed inventory)** | New V/race/mutation coverage, with S2 above remaining. |
| N1 give-back blocked by existing draws | **Closed for original active-source path** | V12; B2 shows the missing ended-child check. |
| N2 unbound ledger labels | **Not closed; retained scope note** | No new claim of universal ledger-to-source binding; r4 arrival branches remain conditional on recognized labels. This review does not promote that earlier accepted boundary into a new blocker. |
| N3 vocabulary/reader consumers | **Closed as vocabulary source review; no new consumer certification** | Retired labels remain excluded in patch CHECKs. |
| N4 no double-counting in cap | **Partly closed** | B1 is an uncounted restored payout; new S1 identifies reader/cap disagreement. |
| N5 lock order | **Partly closed** | Payment-before-overpayment ordering corrected; B2 give-back lacks the child's handshake. See N2 below. |
| N6 residuals | **Closed as scoped decisions (executed judgment)** | Below. |
| N7 mutation mapping | **Partly closed (executed inventory)** | New entries mapped, but N170 label/operation mismatch and APPLY caveat remain. |

| Fable r3 item | Disposition | Evidence / qualification |
|---|---|---|
| B1 paid-out overpayment prevents bounce | **Closed for reported parent-bounce path** | V1/V2; what is held reduces with parent arrival-tree net. Subsequent reissue has B3. |
| S1 ended arrival | **Closed for claimed ended-source paths** | V9/V9b/V13b; broader unbound-label suggestion remains outside the implemented claim. |
| S2 give-back unnecessarily blocked | **Closed for reported active-source path** | V12; negative source-arrival corrections skip outstanding-draw veto. |
| S3 never-issued credit cannot exit | **Closed** | V13/V13b: void with no cause, no late issuing row. |
| S4 credit-leg tests absent | **Partly closed (executed inventory)** | V3/V3b/V16 and CR18/18b added; composed paths still absent. |
| N1 pending received/comment | **Not closed** | S3 above; probe 11. |
| N2 terminal payment reinstated by ledger | **Closed for original incoming payment** | V15; refund-tree analogue remains B1. |
| N3 negative refund's own position | **Retained reader contract note** | Do not interpret all payment rows as independent incoming-source balances; probe 01 inspects the refund tree separately. |
| N4 dated cap ordering | **Closed for original path** | Baseline date-boundary tests retained; arrival-date V10 added. |
| N5 reverse lock order warning | **Closed for named payment/credit pair** | Credit void now takes payment advisory lock before credit; no claim of all-transaction deadlock freedom. |
| N6 K2 indirectly protects status move | **Closed for original path** | V3 plus source cap; V16 also exercises move guard. |
| N7 residuals | **Closed as scoped decisions (executed judgment)** | Below. |
| N8 vocabulary | **Closed (executed source)** | Payment and credit status CHECKs retain Ryan's decision. |
| N9 role/history exceptions | **Partly closed** | Owner history path needs B4. Catalog probe 07 checks installed role invariants; no current server role attributes were queried here. |

Opus r2 N2's actual two-transaction, app-stamped historical-reader assertion remains deferred in the plan. CR13b checks ordering; it is not that exact reader test (**executed test inventory**).

## Notes

### N1 — executed authority assessment / predicted implementation: rulings

K-10's independent refund movement, cancel-pending-refund-first rule and utility-configurable return hold are retained. Ryan's removal of refunded/donated lifecycle statuses is retained. The simple full-bounce cases through a credit now place the paid-out debt on the credit position and zero the parent's held allocation (V1/V2). That is consistent when the payment and credit positions are read together. A parent position alone no longer contains all such debt. The partial parent take-back case additionally needs S1's cap agreement.

One live overpayment credit per payment is a recorded r4 decision, not a reviewer-invented restriction. I found no concrete authorized operation in the cited design requiring two simultaneous live credits; splitting one holding would require an ordering rule. This does not justify either stranding money on an ended credit or double-counting the take-back in the parent cap.

The arrival-date solution faithfully preserves ACH settlement dates instead of forcing payment_date equality. Ryan's reissue decision is represented by a new pointer, exact amount, one-per-refund index, no separate arrival and refusal to void back to an escheated source. Its commit-time implementation is **not complete**, for B1/B3/B4. Probe 00 covers the straightforward cases, probes 01–05 the compositions, probe 11 the no-arrival guard.

### N2 — predicted: concurrency, roles, isolation and statement shapes

Source inspection finds the intended main orders: ledger head → tree → payment → overpayment credit for a take-back; head → source → line for applications; credit void's parent payment → credit; reissue void's originating credit → reissue. Refund exits take their own payment lock and then the refunded source lock. The named overpayment-void/bounce advisory inversion is addressed. The update's row lock still precedes these advisory locks; arbitrary batches and transactions doing multiple acts still cannot be promised deadlock-free. I have no new proven single-act lock cycle to report.

That is not a certification that every money change participates: B1's refund-tree restoration never takes the refunded source's lock, and B2's parent give-back never takes its overpayment credit's lock. Both are single-session defects already; their absence from the handshake also invalidates an unconditional concurrency-completeness claim. Fixes must preserve head/tree/source ordering and recorded-order checks, not only add a terminal-status SELECT.

The draw and status-move entry points pin READ COMMITTED; probe 10 requests REPEATABLE READ/SERIALIZABLE rejection with otherwise legal void transitions. Probe 07 prints the installed writer bodies and exact trigger definitions so the author can compare lock paths and ALWAYS settings. Probe 06 repeats B1–B3/S1 under tally_app, rather than relying solely on superuser behavior. Probe 09 exercises multi-row/CTE donation correction; probe 08 covers COPY. No inference here establishes safety for **every** statement shape or isolation mode; the requested universal conclusion is already false on the explicit predicted paths above. No two-session experiment was run or claimed.

### N3 — executed source assessment: invariant and test limits

The new reissue trigger, FK/CHECK and unique indexes are included in the invariant inventory. The inventory explicitly checks installed definitions and selected configuration/grants, not function bodies. It cannot discover B1–B4 while all those objects remain installed exactly as frozen. Probe 07 supplies the baseline catalog/invariant read, not an assertion that the invariant proves cash correctness.

The older-tests diff has the same MD5 as r3: r4 adds no older-test edits. The earlier attribution caveat remains: its -19 dispute-field hunk is explicitly associated with -25, so this file is not evidence that all of its contents were caused solely by -23. The cancelled-refund-before-bounce adjustment follows K-10; the lineage/sign/date adaptations follow the changed contracts.

The brief's strict-apply-twice, 252 checks, 29 race results, 170 mutation catches and 49 CI steps are **author-reported**, not executed results from this review. In particular, reading and copying the frozen battery into probe 00 does not reproduce those numbers.

### N4 — executed review judgment: residuals R1–R16

| Residual | Blocking? / assessment |
|---|---|
| R1 depth 1000 / complexity | No; accepted explicit bound. No timing measurement here. |
| R2 fixed recorded coordinates | No as a model; subject to valid writer participation and history coordinates. B4 is a concrete guard flaw, not an accepted residual. |
| R3 paid/partial app lifecycle | No; separate from the derived money position. |
| R4 applications survive bill void | No; explicit undo/rebill responsibility. |
| R5 repeated charge-type list | No; maintenance obligation. |
| R6 core classifies source-less lines | No; accepted boundary. |
| R7 allocation/floor/notification | No; accepted core boundary; no new policy ruling inferred. |
| R8 earlier-test adaptations | No; provenance qualification in N3. |
| R9 tariff service/system matching | No; accepted explicit boundary. |
| R10 deposit-refund multiplicity | No; retained -15 responsibility. |
| R11 long statements / timeout | No; accepted operational requirement, unmeasured here. |
| R12 refund undo before status exit | No for the atomic workflow. B1 occurs after both writes and a valid reissue; B3 cannot finish them lawfully. |
| R13 one-click cancel | No; UI responsibility under K-10. |
| R14 utility return-window hold | No; explicit K-10 decision. |
| R15 withdrawals wait for draws | No as stated conservative policy. It does not authorize restoring money to an escheated derived source. |
| R16 one live overpayment credit | No; accepted r4 decision. Reader/cap agreement still needs S1. |

None of these scoped residuals excuses B1–B4 or changes the verdict independently.

### N5 — executed: probe delivery and static verification

| Probe | Requested evidence; all database results predicted |
|---|---|
| 00-frozen-battery.sql | All frozen regression cases, with full caught-error notices. |
| 01-ended-refund-tree.sql | B1 restored old refund plus spendable reissue. |
| 02-escheated-overpayment-giveback.sql | B2 positive remainder restored through parent payment. |
| 03-reissue-after-parent-bounce.sql | B3 full and partial take-back variants, forced deferred checks. |
| 04-parent-position-cap.sql | S1 displayed 60 versus refused 60 draw. |
| 05-superuser-settlement-clock.sql | B4 future exit timestamp, no successor, forced deferred check. |
| 06-app-role-paths.sql | B1–B3/S1 as tally_app inside an owner session. |
| 07-catalog-and-invariants.sql | Installed triggers/functions and role/cash invariant checks. |
| 08-copy-arrival.sql | COPY late arrival for voided payment; native verbose error, no LAST_ERROR_SQLSTATE inference. |
| 09-donation-statement-shapes.sql | Round-3 donation correction in multi-row and writable-CTE shapes. |
| 10-isolation-pins.sql | Separate rolled-back REPEATABLE READ and SERIALIZABLE transactions. |
| 11-reissue-arrival-and-pending-reader.sql | Reissue cannot have credit_issued; pending arrival reader wording. |

An `ADMITTED SQLSTATE=00000` notice reports statement acceptance, not correctness. Compare positions, named errors and deferred-check results with the predictions. The probes are source-reviewed but unexecuted; an unexpected fixture/setup failure must be reported as such, never counted as confirmation of a finding.

## Probe outputs (run by the author, 2026-10-21, fresh clone of tally with frozen r4 strict-applied)

Codex's run stopped at its usage limit after writing this file and its probes. B1, B2, B3 (both variants), B4 and S1 reproduced (executed); 08–11 behave as predicted.

### 01-ended-refund-tree
```
NOTICE:  B1 ADMITTED SQLSTATE=00000: restored old refund entry b585ea8c-53af-468a-b8b1-2af0961b2b43, refund status reversed, tree remaining 30.00
NOTICE:  B1 reissue position={"amount":30.00,"issued":30.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":30.00}
NOTICE:  B1 second refund from reissue ADMITTED SQLSTATE=00000
```

### 02-escheated-overpayment-giveback
```
NOTICE:  B2 give-back ADMITTED SQLSTATE=00000
NOTICE:  B2 credit status=escheated position={"amount":100.00,"issued":100.00,"applied":0,"refunded":0,"given_up":80.00,"carried":0,"remaining":20.00}
```

### 03-reissue-after-parent-bounce
```
NOTICE:  B3 parent take-back=100 old credit position={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":-70.00}
NOTICE:  B3 take-back=100 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit cdf31868-8704-4a45-9774-055c3d8b0728: on 2026-03-18 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 200.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
NOTICE:  B3 take-back=100 settlement CAUGHT SQLSTATE=23514 MESSAGE=refund 07fcfc83-aca7-440d-afd3-33220a21b652 of credit cdf31868-8704-4a45-9774-055c3d8b0728 came back (reversed): -70.00 is back on a credit that was escheated — carry it to a new credit (origin refund_reissue, naming the refund) in the same transaction (Ryan, 2026-10-21; v5.4.2-23)
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
NOTICE:  B3 parent take-back=30 old credit position={"amount":100.00,"issued":70.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":0.00}
NOTICE:  B3 take-back=30 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit f25ca63f-263c-4a25-9107-3f8f70eaf8ac: on 2026-03-18 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 130.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
NOTICE:  B3 take-back=30 deferred settlement ADMITTED SQLSTATE=00000, reissue count=0
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
```

### 04-parent-position-cap
```
NOTICE:  S1 payment position={"amount":100.00,"received":80.00,"applied":0,"credited":20.00,"refunded":0,"remaining":60.00}
NOTICE:  S1 credit position={"amount":40.00,"issued":20.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":20.00}
NOTICE:  S1 CAUGHT SQLSTATE=23514 MESSAGE=payment d9bb0f7e-9eaf-46c0-8ef3-6cff12ce18d7: on 2026-03-16 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 120.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
```

### 05-superuser-settlement-clock
```
NOTICE:  B4 no-reissue settlement ADMITTED SQLSTATE=00000
NOTICE:  B4 position after future stamp={"amount":100.00,"issued":100.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":30.00}; reissue count=0
```

### 06-app-role-paths
```
00000000-0000-4000-8000-0000000023b1
NOTICE:  B1 ADMITTED SQLSTATE=00000: restored old refund entry 7aa657e5-76d6-4170-8477-d12dea845dc3, refund status reversed, tree remaining 30.00
NOTICE:  B1 reissue position={"amount":30.00,"issued":30.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":30.00}
NOTICE:  B1 second refund from reissue ADMITTED SQLSTATE=00000
NOTICE:  B2 give-back ADMITTED SQLSTATE=00000
NOTICE:  B2 credit status=escheated position={"amount":100.00,"issued":100.00,"applied":0,"refunded":0,"given_up":80.00,"carried":0,"remaining":20.00}
NOTICE:  B3 parent take-back=100 old credit position={"amount":100.00,"issued":0.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":-70.00}
NOTICE:  B3 take-back=100 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit 47e1a762-38d8-4093-ba97-e6b62cb0a7b3: on 2026-03-18 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 200.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
NOTICE:  B3 take-back=100 settlement CAUGHT SQLSTATE=23514 MESSAGE=refund a851b042-6a1b-4f38-a60b-2ef69f5b2494 of credit 47e1a762-38d8-4093-ba97-e6b62cb0a7b3 came back (reversed): -70.00 is back on a credit that was escheated — carry it to a new credit (origin refund_reissue, naming the refund) in the same transaction (Ryan, 2026-10-21; v5.4.2-23)
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
NOTICE:  B3 parent take-back=30 old credit position={"amount":100.00,"issued":70.00,"applied":0,"refunded":0,"given_up":70.00,"carried":0,"remaining":0.00}
NOTICE:  B3 take-back=30 reissue CAUGHT SQLSTATE=23514 MESSAGE=credit eb29809f-e4fd-4af0-ad20-480d65a2037e: on 2026-03-18 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 130.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
NOTICE:  B3 take-back=30 deferred settlement ADMITTED SQLSTATE=00000, reissue count=0
NOTICE:  B3 variant cleanup SQLSTATE=P0099 MESSAGE=rollback probe variant
NOTICE:  S1 payment position={"amount":100.00,"received":80.00,"applied":0,"credited":20.00,"refunded":0,"remaining":60.00}
NOTICE:  S1 credit position={"amount":40.00,"issued":20.00,"applied":0,"refunded":0,"given_up":0,"carried":0,"remaining":20.00}
NOTICE:  S1 CAUGHT SQLSTATE=23514 MESSAGE=payment a8de95fe-236a-48d1-9534-f99ccfcb1eaf: on 2026-03-16 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 120.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
```

### 08-copy-arrival
```
COPY probe: expected native ERROR 23514 (still pending); the following error is the probe result, not LAST_ERROR_SQLSTATE.
ERROR:  23514: account_ledger 117ed156-45d3-477a-8197-776663e75e5d posts payment copy-voided, which is voided: a posting row is written for a payment still pending, before its move to posted (R-05, v5.4.2-23)
CONTEXT:  PL/pgSQL function enforce_ledger_reversal() line 56 at RAISE
LOCATION:  exec_stmt_raise, pl_exec.c:3897
error: ERROR:  23514: account_ledger 117ed156-45d3-477a-8197-776663e75e5d posts payment copy-voided, which is voided: a posting row is written for a payment still pending, before its move to posted (R-05, v5.4.2-23)
CONTEXT:  PL/pgSQL function enforce_ledger_reversal() line 56 at RAISE
LOCATION:  exec_stmt_raise, pl_exec.c:3897
```

### 09-donation-statement-shapes
```
NOTICE:  donation multi-row CAUGHT SQLSTATE=23514 MESSAGE=credit 85891264-1cc6-4689-8d9d-cb9751158422: on 2026-03-15 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 200.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
NOTICE:  donation CTE CAUGHT SQLSTATE=23514 MESSAGE=credit 85891264-1cc6-4689-8d9d-cb9751158422: on 2026-03-15 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 200.00, more than its 100.00 (R-06 cap, K-10; v5.4.2-23)
```

### 10-isolation-pins
```
NOTICE:  payment move CAUGHT SQLSTATE=25000 MESSAGE=payment 92872303-2f7d-48f7-904d-896d5f9a4af3: a status move is written at READ COMMITTED (this transaction is repeatable read): it must see every draw committed while it waited (CI-013, v5.4.2-23)
NOTICE:  credit move CAUGHT SQLSTATE=25000 MESSAGE=customer credit 7c4854d9-04e2-4248-8bbc-e73fe1290c82: a status move is written at READ COMMITTED (this transaction is repeatable read): it must see every draw committed while it waited (CI-013, v5.4.2-23)
NOTICE:  draw pin CAUGHT SQLSTATE=25000 MESSAGE=a row drawing on credit 7c4854d9-04e2-4248-8bbc-e73fe1290c82 is written at READ COMMITTED (this transaction is repeatable read): its cap must see every row committed while it waited (R-06, v5.4.2-23)
NOTICE:  payment move CAUGHT SQLSTATE=25000 MESSAGE=payment 3ac1be76-02e5-402a-a113-9df68fcb533c: a status move is written at READ COMMITTED (this transaction is serializable): it must see every draw committed while it waited (CI-013, v5.4.2-23)
NOTICE:  credit move CAUGHT SQLSTATE=25000 MESSAGE=customer credit f6db3cee-1e4b-41af-8ae3-a80f9218eb6c: a status move is written at READ COMMITTED (this transaction is serializable): it must see every draw committed while it waited (CI-013, v5.4.2-23)
NOTICE:  draw pin CAUGHT SQLSTATE=25000 MESSAGE=a row drawing on credit f6db3cee-1e4b-41af-8ae3-a80f9218eb6c is written at READ COMMITTED (this transaction is serializable): its cap must see every row committed while it waited (R-06, v5.4.2-23)
```

### 11-reissue-arrival-and-pending-reader
```
NOTICE:  reissue credit_issued CAUGHT SQLSTATE=23514 MESSAGE=account_ledger 9001e6b2-ce47-4412-b563-5bb0d04c6c7b issues refund_reissue credit 63d05a44-e6ef-4466-95df-4533ca2f2c2d: an overpayment or refund_reissue credit posts no ledger row — its money is its payment's or its returned refund's, already on the ledger (R-06, v5.4.2-23)
NOTICE:  pending payment status=pending position={"amount":40.00,"received":40.00,"applied":0,"credited":0,"refunded":0,"remaining":40.00}
```
