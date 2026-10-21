# Codex review — v5.4.2-23, round 3

Verdict: **not yet**.

**Executed:** source review and file/hash checks only. All six frozen MD5s matched before substantive review. No Docker, psql, CI, race script, mutation runner, or database experiment was run. I did not read Opus's or Fable's round-3 reviews. **Predicted:** every database outcome and behavioral closure assessment below. Probe files are author-run evidence requests, not execution results.

| Frozen input | Verified MD5 |
|---|---|
| patch-23-frozen-r3.sql | 52044407233e3e574910cfcd2d0b976d |
| battery-23-frozen-r3.sql | 9a616cf494c39d142a28f340765120eb |
| cash-23-frozen-r3.sh | 844f988b8ee4117842c805b667a22c5c |
| mutations-23-frozen-r3.py | 8add02abaee5184fd0667827ba6f68ea |
| older-tests-23-frozen-r3.diff | be99c2f963ab9f2177c9f059a4de7e5c |
| patch-23-r2-to-r3.diff | 08f4867cd3c5d0fca52f580cd65dc9da |

**Executed:** authority checked against Kyle's October 21 K-10 answer, the r3 plan, October 21 DECISION-LOG entries, and the cash design/inventory and earlier rulings. Read all three round-2 reviews. References to patch lines below mean the frozen r3 patch. The design's explicit corrections section governs its superseded r1 statements. The depth-1000 decision and -23/-24 division remain accepted.

## Blocking items

### B1 — predicted: donation-tree corrections change the credit's draw without its source guard

**Source:** `enforce_ledger_reversal`, approximately 496–514 and 637–669; `cash_source_draws`, 1957–1964. The new reader includes **every descendant** of a donation. The writer calls `check_cash_source` only for the original `donation` row. A descendant takes its ledger-tree lock and checks X2, but the final source branches recognize only payment/deposit and credit_issued roots. A donation root reaches neither branch.

Concrete ordinary write sequence:

1. Issue credit 100, donate 100.
2. Undo that donation with an adjustment −100.
3. Reserve a refund of 100 against the restored credit.
4. Reverse the donation undo with an adjustment +100.

The final +100 is predicted to be admitted: the donation tree obeys X2, but the credit now has 100 refunded plus 100 donated against 100 issued. Its position reads **remaining −100**. This is not Kyle's payment bounce exception; it is two draws against a credit. The same omission admits multi-row and writable-CTE versions of step 4.

A second path: credit 100, donate 30, remit 70, move to escheated, then undo the donation. The undo is predicted to succeed and leave an **escheated credit with 30 remaining**. An application undo on that ended source is deliberately forbidden, but the donation correction has no equivalent check.

**Probes:** [01-donation-reversal.sql](codex-r3-probes/01-donation-reversal.sql), ordinary-role variants in [09-app-role-paths.sql](codex-r3-probes/09-app-role-paths.sql). Each prints the resulting position. Probe 06 prints the installed writer bodies for lock-path inspection.

**Fix direction:** recognize the donation root for every descendant; take its credit's source lock after the tree lock; enforce source eligibility, recorded order and the dated source cap for a correction increasing the draw. A correction reducing it still needs the ended-source and recorded-order checks. Do not classify every descendant as an uncapped undo: a reversal of an undo consumes money again. Add both correction directions and contention against refunds/applications/escheat to regressions. This is the remaining part of Codex r2 B5 and a new consequence of adding donation descendants to the draw set.

### B2 — predicted: cancelling or failing a refund restores money to a terminal escheated credit

**Source:** `enforce_payment_immutable`, 1588–1596, takes the refunded source's lock but no longer checks its state. `enforce_customer_credit_immutable`, 1696–1715, allows escheated when total draws exhaust the credit, including refundable/cancellable draws.

Concrete sequence:

1. Issue credit 100; reserve a pending refund of 30.
2. Remit the remaining 70 and move the credit to escheated, naming that remittance. The total draws are 100, so the new zero-remainder check passes.
3. Cancel the pending refund.

The cancellation is predicted to succeed. The credit remains **escheated with 30 available**, and a replacement refund is refused because its source is no longer active. The posted-refund variant has the same outcome: post the refund, escheat the other 70, then bounce the refund's own posting and move the refund to nsf.

**Probes:** [02-refund-after-escheat.sql](codex-r3-probes/02-refund-after-escheat.sql), plus the pending-refund application-role path in probe 09.

Ryan removed refunded/donated precisely to avoid stranding returned money. Escheated intentionally remains, but retaining it requires handling a **different outgoing act** failing after escheat; neither probe undoes the state's remittance. Simply refusing the real bank failure would recreate the rejected design. Prevent premature terminalization while other outgoing acts can restore a remainder, or supply a lawful add-only successor-credit path. Preserve the source lock already added. This is not covered by residual R12, which only permits the interval before the refund's own status move.

### B3 — predicted: the dated cap permits a draw before the source's ledger arrival

**Source:** `check_cash_source`, 2029–2034, 2061–2080 and 2132–2139. Its money-date floor is the payment's payment_date or credit's issued_date. Arrival validation checks existence and recorded time, but not the arrival entry's transaction_date. The dated cap adds arrival **descendants**, omits the arrival itself, and compares against a constant face amount at every date. The arrival-row validation at 453–491 likewise does not bind its date to the source date.

Concrete sequences:

- Payment 100 dated ten days ago; its correctly typed, signed and referenced posting entry is dated two days ago; post it normally. Insert refund 30 dated five days ago.
- Credit 100 issued_date ten days ago; its correct credit_issued entry is dated two days ago. Donate 30 dated five days ago.

Both draws are predicted to be admitted. At the draw's money date, the positions read **received/issued 0 and remaining −30**, with no bounce or withdrawal. These rows do not require a chosen recorded timestamp or malformed reference. Source-lock serialization cannot fix this single-session discrepancy.

**Probes:** [03-arrival-money-date.sql](codex-r3-probes/03-arrival-money-date.sql), with tally_app variants in probe 09.

**Fix direction:** either enforce the intended equality between the source's money date and its unique arrival date, or use the dated arrival amount as the available amount in the cap and eligibility check. Keep the new recorded-time floor too: the two coordinates solve different problems. Test payment and credit date mismatches, not only their recorded-time mismatches.

## Should-fix items

### S1 — predicted: an old, permitted K-10 deficit can veto a later affordable draw

**Source:** 2132–2146 checks every historic date for every new draw, even dates the new draw cannot affect.

Payment 50; independent posted refund 30; ledger adjustment +50 returns the payment; a later adjustment −50 reverses that return. Leave the payment's status posted throughout these ledger corrections. All these writes are predicted to succeed. Current received is 50, refunded 30, remaining 20. A new refund of **1**, dated after restoration, is nevertheless predicted to fail on the earlier date with used=80. That earlier deficit was expressly lawful under K-10 and is unchanged by the new refund.

**Probe:** [04-historical-deficit.sql](codex-r3-probes/04-historical-deficit.sql). Clarify the intended reuse rule and make the cap distinguish a newly caused/worsened deficit from a pre-existing permitted bounce deficit. If the intentional answer is that this payment can never be used again, document the required replacement route; the current positive remaining and posted eligibility otherwise promise money that the cap will never release. This is not a request to accept a refund while its money is still absent.

### S2 — executed source assessment: extend tests beyond the first donation undo and immediate escheat check

S9/S9b and N131/N132 prove that the **reader** includes a donation undo. They do not exercise another reversal after the returned money has been consumed or an undo after escheat. R12h–R12j check escheat with money left and a subsequent **application** undo; they do not exercise refund exits or donation corrections. S12/S12b test recorded-time arrival order, not B3's money-date discrepancy. Add B1–B3 and S1 as regressions with failures attributed to their intended guards.

CR13/13b, CR14–CR17 materially expand the handshake coverage, but there is no donation-correction/source contention case. Opus r2 N2's two-transaction position assertion through an actual app-stamped refund exit is still absent, as the r3 plan acknowledges. The frozen battery/races still contain no COPY probe; probe 05 supplies an owner COPY test with its own verbose native error.

The mutation runner's behavioral path checks the first FAIL/ERROR/FATAL/PANIC against the named test. That is useful attribution, not proof of safety completeness. Its APPLY path instead searches stderr for the expected phrase; it does not implement the same first-failure rule. Some mutations deliberately detect a changed refusal diagnostic rather than admission of a bad act: CR12/CR12b, for example, supply missing causes and require 25000. Removing the pin may expose the cause refusal and still fail the named test. Probes 07/08 supply a valid posting cause for the isolation check. No mutation outcome was executed or certified here.

## Round-2 findings, item by item

**Predicted** for behavioral closure; **executed** where explicitly identified as text/documentation inspection. “Closed” means the reported path is addressed, not that every adjacent path is safe. Probe 00 is the frozen r3 battery with full caught-error notices added; it supplies the named battery cases below. Probes 01–09 supply the additional paths/catalog checks. Race names below identify source coverage, not my execution.

### Codex r2

| Item | Disposition | Evidence |
|---|---|---|
| B1 pending refund/bounce | **Closed** | Payment-root reversal checks pending refunds under the payment lock; S4, CR15/15b. -19 cancels P-4 first. |
| B2 reference-based exemption/root mismatch | **Closed** | Exemption removed, canonical payment label/type/amount/account enforced, unique arrival index; S5/S6. |
| B3 multiple credit arrivals/stray void cause | **Closed** | Unique credit arrival plus write-time amount/account binding; S6e–S6f2. |
| B4 credit refund cannot post | **Closed** | Independent refund roots; goodwill and overpayment posting in S7/S7c. |
| B5 donation corrections | **Partly closed** | Reader and draw-set net the tree, and donated is removed; B1 above leaves correction writes unguarded. |
| B6 remittance freeze | **Closed** | BEFORE trigger, UTC day, head FOR SHARE before draw; S11, probe 06 invariant baseline. |
| B7 overpayment void/ended refunded payment | **Closed for reported path** | Refunded label removed; void takes parent payment lock; R7, CR17. B2 is the remaining terminal-credit analogue. |
| S1 test completeness | **Partly closed** | Refund posting, K2, reverse-order races and CR11 text fixed; S2 above lists remaining coverage gaps; probe 05 COPY. |
| S2 app EXECUTE/additional policy | **Closed for named facts** | Positive app privilege and exact policy count checked; probe 06 tests both drifts. |
| S3 stale design/comments | **Closed (executed)** | Explicit design corrections, narrowed X1 comment and both bill-reader caveats. |
| N1 tree arithmetic/seal | **Closed/no new X2 arithmetic finding** | Baseline X/void cases in probe 00; probe 06 seal check. B1 concerns a second, absent cap, not an X2 violation. |
| N2 lock/role/time assessment | **Partly closed** | Existing source-read order retained and parent exit locks added; B1 remains outside that handshake. Probes 06–09. |
| N3 tests/mutations/older edits | **Partly closed (executed source assessment)** | New S cases and N111–N140 address named gaps; completeness/diagnostic caveats remain as S2. |
| N4 residuals and K1/K2 conditions | **Closed as decisions; implementation qualified** | K-10 settles A/cancel-first/no schema hold; residual assessment below and B1–B3 remain. |

### Opus r2

| Item | Disposition | Evidence |
|---|---|---|
| B1 refund-labelled posting root | **Closed** | Canonical label at ledger write and posting move; S6c. |
| B2 forged exemption | **Closed** | No exemption remains; X1 prohibits a refund parent link. |
| B3 K2 missing | **Closed** | Pending-refund guard in ledger path; S4, CR15/15b, -19 fixture correction. |
| B4 failed refund under refunded source | **Closed for reported path** | Refunded removed; R8e–R8h exercise failure/freeing. Retained escheated has B2 above. |
| B5 credit/wrong-parent refund posting | **Closed** | Refund names no parent; S5b, S7/S7c. |
| S1 one arrival | **Closed** | Unique indexes and write-time binding; S6. |
| S2 missing posting/exemption tests | **Closed for rewritten contract** | S1/S5/S7 exercise independent posting; exemption deleted rather than preserved. |
| N1 posting by already-undone entry | **Closed** | Posting requires empty descendant set; S13. |
| N2 real app-stamped historical reader test | **Not closed (executed test inventory)** | Plan explicitly defers it; CR13b tests ordering, not that exact intermediate read. |
| N3 bill-reader caveat | **Closed (executed)** | Both SQL COMMENTs now include it. |
| N4 single-act lock-order qualifier | **Closed (executed)** | Header explicitly limits the ordering assertion and describes multi-act inversion. |
| N5 older-test adaptations | **Closed for named cash edits (executed)** | Birth/arrival fixtures retained; pending refund now cancelled. |
| N6 residuals | **Accepted with qualifications below** | No reopening of depth or core-allocation decisions. |

Opus's conditional K1-A checklist is incorporated: independent positive root, removed exemptions, full bounce, credit posting and corresponding tests are in source. Its proposed refunded-terminal guard was superseded by Ryan's decision; escheated needs the separate B2 treatment.

### Fable r2

| Item | Disposition | Evidence |
|---|---|---|
| B1 arbitrary reference exemption | **Closed** | Deleted; canonical arrival validation and X1 shape. |
| B2 overpayment credit refund cannot post | **Closed** | S7c posts its independent refund row. |
| B3 pending refund at bounce | **Closed** | S4 and CR15/15b; -19 correction. |
| S1 refund under wrong source entry | **Closed** | Refund may name no entry at all; S5b. |
| S2 stray credit issuance void | **Closed** | One exact issuance; S6e–S6f2. |
| S3 failed refund has no exit | **Closed for refunded source; partly overall** | Labels removed and R8e–R8h added; B2 remains for escheated credits. |
| S4 draw recorded before posting | **Closed for reported path** | Arrival/status recorded-time floor; S12/S12b, CR14/16. Money-date gap is separate B3. |
| S5 cross-customer donation/remittance | **Closed** | Donation account check and composite escheat FK; S10/S10b. |
| S6 three unpinned dependencies | **Closed** | Refund sign, credit positive amount, escheat stamp are pinned; probe 06 mutates each. |
| S7 bounced payment position | **Closed for reported path** | Received nets posting tree; S1e includes negative remaining for Kyle's example. |
| S8 no refund posting tests | **Closed (executed test inventory)** | New post helper and S1/S7/S7c. |
| N1 lock order | **Partly closed** | Header qualification is sound; B1's missing source participation remains. |
| N2 partial withdrawal kills credit forever | **Closed for reported arrival arithmetic** | Amount-based cap and S8/S8b replace the Boolean arrival. R15 retains a separate conservative writer restriction. |
| N3 multi-row refunded/void conflict | **Closed by superseding decision** | Refunded moves no longer exist; probe 00 status checks. B1 supplies new multi-row/CTE counterexamples. |
| N4 owner history exception | **Unchanged, documented** | Probe 06 shows terminal birth without a cause; not classified as an app bypass. |
| N5 residuals | **Accepted with qualifications below** | -19 K2 inconsistency corrected. |
| N6 free-standing escheat/credit_applied ledger labels | **Unchanged scope note** | No new claim that arbitrary ledger labels implement the credit subledger; arrival readers require canonical references. |
| N7 tally_void helper reach | **Unchanged/closed** | Void root is charge; no cash-table grants added to its seal list. Probe 06. |

## Notes and requested cross-checks

### N1 — executed source assessment / predicted behavior: K-10 and Ryan's vocabulary

The basic K-10 example is implemented faithfully: the refund root is separate and positive, the payment's reversal tree alone caps its full bank return, and the position can show −30 remaining. Probe 00 S1 tests the account balance as well as the source position. Pending refunds block a payment-root reversal under the source lock; a bounce-first history has no capacity for a later pending refund. No automatic cancel or return-window schema hold is introduced.

The live definitions in this patch remove refunded/donated from the relevant status checks and move functions, replace the deposit index that used the removed payment deposit_status, and rebuild credit aging on the derived position. The old base definitions of the replaced functions/checks are not surviving readers. Deposits' refunded and escheat events' donated remain intentionally separate vocabularies. The remaining problems concern allowed histories and guards, not a request to restore the removed labels.

Arrival recognition is internally consistent about labels: `cash_arrival_entry` and positions require the same canonical payment/customer_credit references that the write checks and unique indexes bind. A different or NULL reference is not treated by those readers as a source arrival. This does not prove all arbitrary ledger rows correspond to business objects, nor does it repair B3's unbound arrival date. Probe 00 S6 covers binding; probe 03 covers the date.

### N2 — executed source assessment / predicted behavior: caps, locks and statement shapes

The normal draw set contains applications (including negative undos), live overpayment credits, pending/posted refunds, donation trees and remittances. Donation roots cannot name a parent under X1, so ordinary donation trees are disjoint from arrivals. An independent refund's posting row is not counted a second time as an arrival descendant. Nested corrections net algebraically, rather than counting gross reversal amounts. The defect is that newly included donation descendants do not all invoke the credit cap.

Application undos still require a live source and are bounded by their original application under the source/line locks. Skipping the aggregate source cap for a strictly negative application undo does not itself increase consumption. Donation re-reversals are different and cannot inherit that exemption (B1).

The normal source checker takes the source lock before mutable source/eligibility/cap reads. Refund exits and overpayment voids now acquire the parent source lock, and the recorded-order scan includes their exit stamps. The remittance freeze takes the head first. However, not **every** money-freeing/consuming correction participates: B1 is a counterexample. Probe 06 exposes these installed paths; it is not a substitute for a two-session run. No runtime concurrency result is claimed here. Documented multi-object/multi-act deadlocks still require retries; I found no additional necessary lock-order redesign in the new parent-lock branches.

Probe 09 exercises B1–B3 as tally_app from an owner connection. Probe 06 reports app/core/void/close grants and seal assertions. Probes 07/08 test REPEATABLE READ and SERIALIZABLE refusals with valid posting causes and reversal/source checks; probe 00 covers ordinary READ COMMITTED operations. Owner history exceptions are explicit, not blanket resistance to a superuser changing timestamps or disabling guards. Probe 01 exercises single-row, multi-row and writable CTE forms; probe 05 covers owner COPY and prints the native verbose COPY error, never LAST_ERROR_SQLSTATE.

### N3 — executed source assessment: tests, invariants and earlier changes

The exact trigger/index/constraint checks now include the newly claimed dependencies, the approvals policy set and positive app EXECUTE. They expressly do not hash function bodies. Their presence therefore does not detect B1/B2's missing logic inside otherwise correctly installed functions. Probe 06 tests the named catalog drifts transactionally.

The -19 cancel-before-bounce change follows K-10, and the -22 CR11 emitted label now agrees with its two direct recoveries. Other cash adaptations follow birth/arrival, same-customer, opposite-sign and time rules rather than furnishing evidence against them. One provenance caveat: the frozen “older-tests” diff also includes -19 RW6's explicitly **-25** dispute-field removal. Attribute that hunk to -25 when interpreting a -23-only earlier-battery run; the diff is not exclusively -23 changes.

I do not certify strict apply twice, 216 passing checks, 49 CI steps, 26 race results or 140 caught mutations. Those are author-reported results. No new reproduction result is implied by copying the frozen battery into probe 00.

### N4 — executed review judgment: residuals R1–R15

| Residual | Assessment |
|---|---|
| R1 depth 1000/performance | Accepted explicit decision. No timing reproduction or request to lower the limit. |
| R2 fixed recorded coordinates | Accepted model, subject to valid history loads and the open-transaction caveat. Missing writer participation is B1, not resolved by declaring R2 closed. |
| R3 paid/partial lifecycle | Accepted separation from calculated money. |
| R4 applications survive bill void | Accepted core undo/rebill responsibility. |
| R5 repeated charge-type list | Nonblocking maintenance obligation. |
| R6 source-less regulatory class | Accepted core classification responsibility. |
| R7 allocation/floor/notification | Accepted scope; no invented resolution of Kyle's outstanding floor policy. |
| R8 older test changes | Cash changes justified; -25 provenance caveat in N3. |
| R9 tariff service/system matching | Accepted explicit core boundary. |
| R10 deposit refund multiplicity | Accepted -15 boundary. |
| R11 long statement locks | Accepted operational timeout requirement; no new performance claim. |
| R12 refund ledger undo precedes status exit | Acceptable for an atomic application workflow. Does not excuse B2 after **both** writes complete. |
| R13 one-click pending-refund cancel | Accepted UI responsibility. |
| R14 tenant-configurable return hold | Accepted K-10 decision; additive storage later. |
| R15 withdrawal waits for existing credit draws | Accepted stated conservative rule. Does not excuse outgoing donation corrections bypassing the source guard. |

None of the expressly scoped residuals alone changes the verdict. B1–B3 are violations outside those accepted boundaries; S1 is an additional cap usability problem to resolve or document concretely.

## Probe delivery

**Executed:** wrote and statically inspected the following files only, alongside this review. **Predicted:** all SQL results. Run each on an author-prepared fresh clone with frozen r3 strictly applied, as the owner; revoke clone TEMP from PUBLIC/app/core as the brief requires. No probe creates, drops or alters a role. All end in ROLLBACK; probe 09 contains three independent rolled-back transactions. Owner catalog mutations in 06 roll back. Caught errors use RAISE NOTICE with SQLSTATE and full message; COPY prints its own error.

| Probe | Purpose |
|---|---|
| 00-frozen-battery.sql | Frozen regression battery plus full caught-error notices. |
| 01-donation-reversal.sql | B1: re-reversal, multi-row, CTE and undo after escheat. |
| 02-refund-after-escheat.sql | B2: pending cancellation and posted-refund failure. |
| 03-arrival-money-date.sql | B3: payment and credit draws before ledger arrival date. |
| 04-historical-deficit.sql | S1: restored payment with affordable draw refused by old deficit. |
| 05-copy.sql | Owner COPY aggregate overflow; native verbose error output. |
| 06-catalog-contract.sql | Invariants, selected catalog drift, role reach, installed writer bodies, owner history exception. |
| 07-repeatable-read.sql | Valid posting, source and reversal isolation checks. |
| 08-serializable.sql | Same checks under SERIALIZABLE. |
| 09-app-role-paths.sql | B1–B3 through ordinary tally_app writes. |

“ACCEPTED SQLSTATE=00000” means admission of the attempted statement, **not** correctness. Compare resulting positions and errors with the predictions above. No author-run result is available in this review.

## Probe outputs (run by the author, 2026-10-21, on a fresh clone of tally with frozen r3 strict-applied)

Every predicted blocker reproduced (executed): B1 (donation correction, both paths), B2 (pending and posted refund after escheat), B3 (payment and credit draws dated before their arrival), S1 (historical deficit vetoes a 1.00 refund). Probes 05, 07, 08 behave as the source predicts.

### 01-donation-reversal
```
NOTICE:  B1 restore donation after refund ACCEPTED SQLSTATE=00000
B1 predicted refunded=100 given_up=100 remaining=-100|100.00|100.00|0|100.00|100.00|-100.00
NOTICE:  B1 multi-row restore donation ACCEPTED SQLSTATE=00000
B1 multi-row|100.00|100.00|0|100.00|100.00|-100.00
NOTICE:  B1 writable CTE restore donation ACCEPTED SQLSTATE=00000
B1 CTE|100.00|100.00|0|100.00|100.00|-100.00
NOTICE:  B1 undo donation after escheat ACCEPTED SQLSTATE=00000
B1 predicted escheated with remaining=30|escheated|100.00|100.00|0|0|70.00|30.00
```

### 02-refund-after-escheat
```
NOTICE:  B2 cancel pending refund after escheat ACCEPTED SQLSTATE=00000
B2 predicted escheated with remaining=30|escheated|100.00|100.00|0|0|70.00|30.00
NOTICE:  B2 replacement refund cannot use restored money SQLSTATE=23514 message=a row drawing on credit c0de0003-0000-4000-8000-000000000010 (escheated) for refund: money is drawn from a posted payment (a bill payment, unless it is a refund) or an active credit, and an undo only while its source has not ended (A3, R-06, K-05; v5.4.2-23)
NOTICE:  B2 failed posted refund after escheat ACCEPTED SQLSTATE=00000
B2 posted-refund variant predicted remaining=30|escheated|100.00|100.00|0|0|70.00|30.00
```

### 03-arrival-money-date
```
NOTICE:  B3 refund dated before ledger arrival ACCEPTED SQLSTATE=00000
B3 predicted received=0 refunded=30 remaining=-30 without a bounce|100.00|0|0|0|30.00|-30.00
NOTICE:  B3 donation dated before credit ledger arrival ACCEPTED SQLSTATE=00000
B3 predicted issued=0 given_up=30 remaining=-30|100.00|0|0|0|30.00|-30.00
```

### 04-historical-deficit
```
S1 predicted received=50 refunded=30 remaining=20|50.00|50.00|0|0|30.00|20.00
NOTICE:  S1 new refund of 1 with 20 currently available SQLSTATE=23514 message=payment c0de0003-0000-4000-8000-000000000010: on 2026-10-15 what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to 80.00, more than its 50.00 (R-06 cap, K-10; v5.4.2-23)
```

### 05-copy
```
00000000-0000-4000-8000-0000000023b1
COPY overflow probe: expected native ERROR 23514 containing more than the line
ERROR:  23514: line 0 of invoice B23-I1: on 2026-03-10 its applications would come to 65.00, more than the line's 60.00 (R-06 cap, v5.4.2-23)
CONTEXT:  PL/pgSQL function enforce_invoice_application() line 129 at RAISE
LOCATION:  exec_stmt_raise, pl_exec.c:3897
0
```

### 07-repeatable-read
```
NOTICE:  payment posting isolation pin SQLSTATE=25000 message=payment CX-10: a status move is written at READ COMMITTED (this transaction is repeatable read): it must see every draw committed while it waited (CI-013, v5.4.2-23)
NOTICE:  source pin SQLSTATE=25000 message=a row drawing on payment c0de0003-0000-4000-8000-000000000010 is written at READ COMMITTED (this transaction is repeatable read): its cap must see every row committed while it waited (R-06, v5.4.2-23)
NOTICE:  reversal pin SQLSTATE=25000 message=a reversal is posted at READ COMMITTED (this transaction is repeatable read): its cap must see every row committed while it waited (R-02, v5.4.2-23)
```

### 08-serializable
```
NOTICE:  payment posting isolation pin SQLSTATE=25000 message=payment CX-10: a status move is written at READ COMMITTED (this transaction is serializable): it must see every draw committed while it waited (CI-013, v5.4.2-23)
NOTICE:  source pin SQLSTATE=25000 message=a row drawing on payment c0de0003-0000-4000-8000-000000000010 is written at READ COMMITTED (this transaction is serializable): its cap must see every row committed while it waited (R-06, v5.4.2-23)
NOTICE:  reversal pin SQLSTATE=25000 message=a reversal is posted at READ COMMITTED (this transaction is serializable): its cap must see every row committed while it waited (R-02, v5.4.2-23)
```

### 09-app-role-paths
```
c0de0003-0000-4000-8000-000000000003
NOTICE:  B1 restore donation after refund ACCEPTED SQLSTATE=00000
B1 predicted refunded=100 given_up=100 remaining=-100|100.00|100.00|0|100.00|100.00|-100.00
NOTICE:  B1 multi-row restore donation ACCEPTED SQLSTATE=00000
B1 multi-row|100.00|100.00|0|100.00|100.00|-100.00
NOTICE:  B1 writable CTE restore donation ACCEPTED SQLSTATE=00000
B1 CTE|100.00|100.00|0|100.00|100.00|-100.00
NOTICE:  B1 undo donation after escheat ACCEPTED SQLSTATE=00000
B1 predicted escheated with remaining=30|escheated|100.00|100.00|0|0|70.00|30.00
c0de0003-0000-4000-8000-000000000003
NOTICE:  B2 cancel pending refund after escheat ACCEPTED SQLSTATE=00000
B2 predicted escheated with remaining=30|escheated|100.00|100.00|0|0|70.00|30.00
NOTICE:  B2 replacement refund cannot use restored money SQLSTATE=23514 message=a row drawing on credit c0de0003-0000-4000-8000-000000000010 (escheated) for refund: money is drawn from a posted payment (a bill payment, unless it is a refund) or an active credit, and an undo only while its source has not ended (A3, R-06, K-05; v5.4.2-23)
NOTICE:  B2 failed posted refund after escheat ACCEPTED SQLSTATE=00000
B2 posted-refund variant predicted remaining=30|escheated|100.00|100.00|0|0|70.00|30.00
c0de0003-0000-4000-8000-000000000003
NOTICE:  B3 refund dated before ledger arrival ACCEPTED SQLSTATE=00000
B3 predicted received=0 refunded=30 remaining=-30 without a bounce|100.00|0|0|0|30.00|-30.00
NOTICE:  B3 donation dated before credit ledger arrival ACCEPTED SQLSTATE=00000
B3 predicted issued=0 given_up=30 remaining=-30|100.00|0|0|0|30.00|-30.00
```
