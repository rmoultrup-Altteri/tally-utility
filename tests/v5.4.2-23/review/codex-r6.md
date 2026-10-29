# Codex review — v5.4.2-23, round 6

Verdict: **not yet**.

**Executed:** read the brief and checked its six MD5s before substantive review. All matched. Reviewed frozen patch source, the round-5 reviews (including the author's appended results in Codex r5), the design/inventory, r6 plan/as-built record, DECISION-LOG, and the applicable supplied rulings. Inspected the frozen battery, race and mutation coverage relevant to the findings and retained contracts. Did not read `opus-r6.md` or `fable-r6.md`. Did not run Docker, psql, CI, races, mutations, an apply, or a database experiment. Only this file and `codex-r6-probes/` were written.

**Predicted:** every database outcome, closure assessment and concurrency conclusion below. “Executed source” means inspection of text, not execution of SQL. The reported strict applies, CI pass, battery/race counts, mutation catches and timings are not independently reproduced here.

| Frozen file | Executed MD5 |
|---|---|
| patch-23-frozen-r6.sql | 76424e4b63d27c2bd86dfa09ab76ff11 |
| battery-23-frozen-r6.sql | bf8d6bb8df6334bcc7aae7348e6d4fc4 |
| cash-23-frozen-r6.sh | 5025bdc372669d4096f604e2fc6aa251 |
| mutations-23-frozen-r6.py | 7d9b762f4599b8eca516bfc0ccd4146d |
| older-tests-23-frozen-r5.diff | be99c2f963ab9f2177c9f059a4de7e5c |
| patch-23-r5-to-r6.diff | 34d977827ba501d7fe1ffe00bfefe57a |

References to patch lines mean frozen r6. All database claims are paired with author-run probes below. Each starts in an owner session on a fresh clone with frozen r6 applied, ends in ROLLBACK, and prints SQLSTATE and message for caught errors. Revoke clone TEMP from PUBLIC, tally_app and tally_core first. No role DDL is requested. A setup failure is not confirmation of a finding.

## Blocking items

### B1 — predicted: the cover does not cover deficits between members of the credit family

**Source:** `overpayment_absorbed_as_of`, 1844–1867, sums all family remainders into `v_f`, then covers only between that aggregate and the payment. It never covers one credit's deficit with another credit's positive holding. The per-credit cap and aggregate pool at 3024–3090 can consequently refuse the positive remainder displayed by the reissue.

Concrete path, each act at a distinct recorded instant, all guards enabled:

1. Payment P 100, overpayment credit K 100.
2. Refund 30 from K, post it; remit 70 and escheat K.
3. Return the refund, move it to reversed, carry 30 into active reissue K2, and flush deferred checks.
4. Take back 80 under P's posting entry. P is only partly returned and remains posted.
5. Correct 20 of that take-back with a −20 child row.

Predicted positions:

| Reading | P remaining | K remaining | K2 remaining |
|---|---:|---:|---:|
| After the 80 take-back | 0 | −50 | 0 |
| After the 20 give-back | 0 | −50 | **20** |

The 80 takes K2's held 30 and puts the remaining 50 on K. The give-back restores K2's share first. Since `v_p = 0`, neither cover branch runs, even though a credit holds +20 beside another's −50. The give-back's escheated-credit guard admits it: K itself is still negative. Forced deferred checks do not repair the positions.

A refund of K2's displayed 20 is then refused by the pool, as is 0.01: the payment has 40 standing and 70 already remitted, so the family owes 30 and has nothing drawable. The refusal is correct; the displayed 20 is not. This is the round-5 reader/cap discrepancy inside the newly introduced family, not an earlier payout that K-10 permits to stand.

**Probe:** [01-family-deficit.sql](codex-r6-probes/01-family-deficit.sql). Prints positions and shares, forces deferred checks, and separately attempts 20 and 0.01 after the give-back. Predicted refusal: 23514 mentioning the payment and its overpayment credit.

**Required direction:** define and enforce the deficit treatment across individual family members, not only payment versus the family's sum. Preserve the pool cap. Recheck both position/cap agreement and conservation with multiple positive and negative family members; merely clamping a displayed remainder or relaxing the pool is insufficient.

### B2 — predicted: the 1,000th reissue loses its payment root and can refund after the payment has returned in full

**Source:** `overpayment_root`, 1544–1556, starts depth at **1** and stops recursion at 1000, silently returning NULL if the overpayment ancestor has not been reached. `overpayment_family`, 1566–1580, starts depth at **0** and includes descendants through 1000 edges. No reissue-insert check rejects exceeding either traversal's bound. The NULL is treated as a genuine non-overpayment lineage by the position and cap, rather than an incomplete walk.

Concrete path, all guards enabled:

1. Payment 1, held in overpayment K0.
2. Refund K0's 1, post it, return it and move it to reversed, then reissue it as K1.
3. Repeat refund/post/return/reissue through K1000, with no external money outstanding. Each reissue transfers the same 1.
4. Fully return the original payment and move it to reversed.
5. Refund and post 1 from K1000.

Predicted: generation 999 still resolves to K0; generation 1000 resolves to NULL, while `overpayment_family(K0)` still contains 1001 credits including K1000. Its creation succeeds because sizing and `check_cash_source` check its predecessor K999, whose root is still found. At step 5, the cap's lookup for K1000 finds no payment, takes no payment lock and skips both its take-back share and the pool. A refund_reissue is allowed to have no arrival entry. Its position also falls back to original amount. The new payout is admitted after the underlying 1 has wholly returned.

This is a fail-open lineage limit, not the accepted bound on **ledger reversal trees** in R1. Every refund's ledger tree here is shallow. Raising 1000 by one only moves the escape.

**Probe:** [02-reissue-depth.sql](codex-r6-probes/02-reissue-depth.sql). Builds the real sequence with ordinary transaction-start stamps, no disabled triggers, no fabricated born-returned refunds, prints roots at generations 1/999/1000, then attempts the final payout and forces deferred checks. It may be slow; no timing is predicted. Predicted final outcome: admission, SQLSTATE 00000.

**Required direction:** an incomplete traversal must raise, and insertion must enforce any supported reissue-lineage bound consistently with every reader, cap and bounce guard. Alternatively traverse the complete valid lineage. Do not equate “bound reached” with “not descended from an overpayment.”

## Round-5 disposition, item by item

**Predicted** closures are scoped to the reported path, not a proof over all compositions. `00` below means [00-frozen-battery.sql](codex-r6-probes/00-frozen-battery.sql), the frozen r6 battery with complete caught-error notices added. Its Y/W labels provide runnable closure probes; none was run here.

| Codex r5 item | Disposition | Evidence / remaining limit |
|---|---|---|
| B1 reissue before parent bounce | **Partly closed** | 00 Y7–Y7h/Y7m cover the original active/escheated paths, pending-refund blocking and shared pool. New B2 defeats the broader “any number of reissues” contract. |
| B2 give-back leaves surplus beside deficit | **Closed for the reported pair; partly closed as a family rule** | 00 Y3/Y3a covers payment 60 / credit 20 / direct refund 40 / take-back 30 / give-back 20. New B1 is the same discrepancy between credits. |
| B3 UUID ordering of tied corrections | **Closed** | Tree depth precedes UUID; 00 Y4–Y4d checks both UUID orders and a date between parent and child. |
| B4 same-status past timestamp edit | **Closed for the reported writer** | Both immutability functions reject it for every role. 00 Y6–Y6d includes chosen-time move controls. |
| S1 stale durable comments | **Not closed** | Reissue amount and bounce wording remain, S3 below. |
| S2 coverage and first-failure attribution | **Partly closed** | Y checks, agree(), CR23/24 and N192–N211 address the original cases; new compositions and the APPLY attribution caveat remain, S2 below. |
| N1 rulings | **Partly closed** | Shallow family now stays with its payment; B2 is still a K-10 escape. |
| N2 locks/roles/shapes | **Partly closed** | Payment-first leaving refund added; S1 and B2 prevent a universal claim. 00 plus regression probes cover the retained controls. |
| N3 invariant scope | **Closed as a scoped note** | Definitions are distinguished from function bodies; catalog probe retained. No certification of live catalog results. |
| N4 residuals | **Partly closed** | Tie ordering and timestamp-only correction addressed; see R17/R20 and B1/B2 below. |
| N5 probe delivery | **Closed as an executed delivery fact** | R5 author outputs remain r5 evidence; r6 probes are supplied unexecuted. |

| Opus r5 item | Disposition | Evidence / remaining limit |
|---|---|---|
| B1 fixed shortfall after payment refund returns | **Closed for P1/P2; partly closed as a family rule** | 00 Y1/Y2, agree(); new B1. |
| B2 take-back begun before draw | **Closed for reported draw/credit paths** | Payment lock then `check_cash_order` over payment and family; 00 Y5–Y5c chosen-time controls; CR23 source supplies the concurrent retry test. |
| S1 future created_at | **Closed for named tables** | Birth, application and remittance checks; 00 Y9–Y9d. App stamps are retained. |
| S2 give-back belonging to payment refused | **Closed for P5** | Positive-remaining predicate replaces status alone; 00 Y8/Y8a. |
| S3 missing tests | **Partly closed** | Named original paths added; S2 below identifies new gaps. |
| N1 no lock cycle | **Partly closed / superseded** | Fable's reported cycle is addressed, but S1 below remains in the expanded family. |
| N2 ordinary leaving times | **Closed as retained transaction-time model, not a universal fixed-share proof** | R17 remains explicit; chosen times now additionally checked. 00 W12/Y0c and Y6; no new ordinary-time violation claimed here. |
| N3 reissue sizing depends on split | **Partly closed** | `x.remaining + y.issued`, 00 W6a–W7; B1 means family positions are not generally reliable sizing inputs. |
| N4 one instant | **Closed for reported interpretation** | Depth order and revised R17; 00 W12/Y4. Pool remains load-bearing within the supported lineage. B2 limits that last qualification. |
| N5 terminal refund-tree rule | **Closed as retained policy** | 00 W1 variants; R18 explicitly acknowledges an erroneous return's correction limitation. |
| N6 cost | **Closed as documentation, unverified measurement** | R21 records author timing; none reproduced here. |
| N7 residuals | **Partly closed** | R17 corrected; new family limitations below. |
| N8 mutations | **Partly closed** | New named legs present; S2. |

| Fable r5 item | Disposition | Evidence / remaining limit |
|---|---|---|
| B1 take-back recorded before draw/credit | **Closed for RR-A/RR-B/P7b paths** | 00 Y5 and payment/family checks; CR23 source. B2 prevents claiming complete arbitrary-depth lineage. |
| S1 return/move/reissue deadlock | **Closed for RR-D** | Leaving refund now takes payment before source credit; CR24/N211 specifically target it. S1 below is a different pair. |
| S2 cancellation of escheated deficit refused | **Closed for P11** | 00 Y8b–Y8d, positive-remaining test. |
| S3 agree() and missing tests | **Partly closed** | Helper added and original shapes covered. B1 is an omitted family shape. |
| N1 one instant | **Closed as retained contract** | Revised R17 and 00 W12/Y0c/Y4; not an exemption from B2. |
| N2 escheat versus take-back | **Closed as retained scoped observation** | No new unsafe outcome claimed for that specific pair. Source still takes only credit on the escheat move. No concurrent execution certified. |
| N3 erroneous refund return | **Closed as documentation** | R18 states it. 00 W1 covers terminal-tree refusal. |
| N4 app status time | **Closed as documentation** | R19 states validation before stamp; 00 W10/Y6 covers time restrictions. |
| N5 mutations | **Partly closed** | New legs present; S2. |
| N6 pool never stricter/missing | **Partly closed as a general assertion** | Original W/Y shapes retained in 00. B1 correctly refuses a false displayed balance; B2 omits the pool. |
| N7 active predecessor reissue | **Closed for original path** | 00 Y7 active-predecessor variant; it remains an internal carry. |
| N8 residuals | **Partly closed** | R15/R16 retained, R17 corrected; new R20 implementation gap B1. |
| N9 r5 red-against-r4 report | **Closed as a provenance note** | No red report or mutation result reproduced in this source-only review. |

## Should-fix items

### S1 — predicted: reissue void versus give-back has opposite credit-lock order

The as-built justification “a void takes no further lock” is not true of the reissue path. At 2354 it locks the refund's source credit K, and at 2363 it locks the reissue K2. The give-back at 804–808 locks **every** nonvoid family credit in UUID order after taking P. If K2's UUID sorts before K's, these are opposite orders.

Concrete valid shape: active K, an unused active reissue K2 from a returned refund, and a partial take-back under P that can be corrected. A void of K2 is allowed back onto active K. A give-back need not see either credit escheated to acquire this family lock list.

Interleaving: A (void) holds K; B (give-back) holds P and K2 and waits for K; A waits for K2. Predicted 40P01. This is one void versus one give-back, not arbitrary transactions taking two independent cash actions in opposite order. PostgreSQL's victim rollback protects money, so this is should-fix rather than another money blocker.

**Probes:** [03-lock-topology-A.sql](codex-r6-probes/03-lock-topology-A.sql), [03-lock-topology-B.sql](codex-r6-probes/03-lock-topology-B.sql), in two owner sessions on the same fresh clone. These deliberately test the extracted advisory-lock topology without committed cash fixtures; they are **not** represented as a full end-to-end trigger race. Start B during A's five-second notice window; one session should print 40P01. A 55P03 timeout is not confirmation. The author should add the actual trigger race alongside CR24.

Taking the lineage payment lock before either credit on a reissue void would serialize this pair. Alternatively establish one compatible family-credit order for both paths. Also retain the immediate-source lock that the next draw waits on.

### S2 — executed source: coverage and attribution claims remain broader than the checks

- `agree()` is a useful addition. Y7i/j has a shallow family with positive holdings, Y7e/h has an escheated deficit with its successor at zero. Neither supplies the **subsequent give-back** that turns the successor positive beside the deficit (B1). There is no 999/1000 reissue boundary case (B2), nor the void/give-back pair (S1).
- N192/N193 target take-back order; N194/N195 the two cover directions; N196 depth ordering within a ledger instant; N197–N199 status history; N200–N207 family membership, guards, sizing and shares; N208–N210 timestamps; N211 RR-D. Those are relevant, but changing a branch and catching a named example does not establish the complete family contract.
- The APPLY branch, around mutation runner 613–615, still accepts `phrase in a.stderr` following a failed apply. It does not parse the first diagnostic. The behavioral branch does enforce the first failure's named check. Thus “each at its named check as the first failure” remains stronger than the APPLY implementation. I make no claim that a particular frozen mutation actually passed for the wrong reason.
- The invariants check trigger/index/constraint definitions, selected grants, RLS and plan settings, not the arithmetic or completeness of helper bodies. In particular their walk-plan lists do not include `overpayment_shares`; nor does a catalog check enforce the correspondence of the two family traversal bounds. The claim must remain scoped accordingly.
- The frozen older-tests diff is unchanged from r5 and still includes the expressly labelled -25 dispute-fields edit. It is not exclusively -23 provenance. The cancellation-before-bounce, arrival, sign, date and cross-customer fixture adaptations follow the revised contracts; planted invalid histories such as C19 are defense tests, not ordinary writer evidence.
- The brief says 343 battery checks, whereas the patch header and plan as-built say 344. Reconcile the published count with the author's actual log; no database count is certified here.

**Probes for the database side of these assessments:** 00; 01/02 for missing behavior; 03 for the lock topology; [regression-07-catalog-and-invariants.sql](codex-r6-probes/regression-07-catalog-and-invariants.sql). Source/runner-text observations require no mutation execution.

### S3 — executed source: Codex r5 S1's durable descriptions remain stale

`reissues_refund_id`'s column comment at 1464 still says its amount is the refund's; `enforce_cash_draw`'s COMMENT at 3345 still says “exactly” the returned refund, despite remainder-based sizing. `enforce_ledger_reversal`'s COMMENT at 919 still lists being “held as a credit” as a bounce blocker. Revise these to the final family/remainder contracts. R15 also speaks only of the overpayment credit, while r6's guard includes reissue descendants. The introductory r5 bullets are historical, but durable function comments and the residual rule should describe current behavior.

## Notes

### N1 — executed authority review; predicted implementation: rulings

K-10 keeps refunds separate from payment reversal trees, permits the real bank return after payouts, blocks a bounce while a refund waits, and leaves return-window policy to the tenant. Ryan's recorded status and escheat decisions retain forward-only lifecycle, derive refunded/donated amounts, and carry returned escheated-credit money into a new credit. The r6 drafting direction is consistent with these authorities; the remainder refinement and R20 attribution are explicitly recorded drafting choices, not new rulings.

The ordinary original r5 paths now have source-level fixes and runnable controls in 00. However B2 still permits an actual new payout after a full return, directly contrary to K-10. B1 still displays money that cannot be drawn. The choice of credit-first attribution need not itself be rejected to fix either; its implementation must preserve complete lineage and the promised family position contract. No new ruling from Ryan is needed to refuse a traversal that silently loses the source.

### N2 — predicted: concurrency, roles, isolation and statement shapes

Within a completely resolved family, `check_cash_source` takes the payment lock before the credit and reads the cap afterward. Applications then take their line lock. Reversal trees take their root lock before the cash source. Returning/cancelling a credit's refund now takes its lineage payment then source credit; the overpayment void still takes payment then credit. The reissue void retains its immediate-source lock, but S1 exposes its incompatible family order. B2 loses the payment lock and pool altogether.

The take-back's new checks cover live draws and leaving moves on the payment and each traversed family credit. A draw in flight is not itself a reason for permanent refusal: it waits on the payment lock, then an older transaction-start instant receives the documented retry; a chosen past history instant receives 23514. The reported CR23/24 results remain author evidence, not my executions.

The same-status timestamp rejection applies to owner and app. `cash_lineage_recorded` includes arrival trees, current draw rows and leaving timestamps across the resolved family; it is substantially stronger than the old finite-past-only check, but inherits B2's incomplete-walk limitation. I do not certify every history-load composition from Y6 alone.

Source pins reject stronger snapshot isolation for draws, arrivals, reversals and status changes. Catalog and grant inspection is not proof that every deployed role is configured correctly. Author-run coverage is supplied by 00 (owner and app paths), regression-07 (catalog/grants), [regression-10-isolation-pins.sql](codex-r6-probes/regression-10-isolation-pins.sql) (REPEATABLE READ/SERIALIZABLE controls), and [regression-09-donation-statement-shapes.sql](codex-r6-probes/regression-09-donation-statement-shapes.sql) (multi-row and data-modifying CTE controls). There is no universal “every role/isolation/statement shape safe” verdict while B1/B2 remain.

[regression-08-copy-arrival.sql](codex-r6-probes/regression-08-copy-arrival.sql) checks the voided-payment arrival path through COPY. It prints the native verbose COPY error and `\errverbose`, rolls back its savepoint, then ends in ROLLBACK. It does **not** treat psql's LAST_ERROR_SQLSTATE = 00000 as success.

### N3 — executed review judgment; predicted behavior: residuals R1–R21

| Residual | Assessment |
|---|---|
| R1 ledger depth bound | Not blocking as an accepted limit; B2 is a distinct, unenforced credit-lineage limit. |
| R2 fixed recorded coordinates | Same-status correction hole closed for the reported writer (00 Y6). Supported history loads and open-transaction qualifications still matter; no universal immutability proof claimed. |
| R3 invoice paid/partial lifecycle | Not blocking as explicitly separate from derived balances. |
| R4 undo bill applications after void | Not blocking as retained workflow responsibility. |
| R5 duplicate charge-type list | Not blocking; maintenance obligation. |
| R6 source-less line classification | Not blocking; explicit core boundary. |
| R7 allocation/floor/notifications | Not blocking; no new policy inferred. |
| R8 older-test changes | Not blocking; provenance qualification S2. |
| R9 tariff service/system matching | Not blocking as retained core responsibility. |
| R10 deposit refund caps | Not blocking as retained -15 responsibility. |
| R11 long statements/timeouts | Not blocking as an operational limitation; no timing reproduced. |
| R12 refund return plus status move | Not blocking for the atomic workflow. Both new blocker probes include the move. |
| R13 one-click cancel | Not blocking; UI requirement. |
| R14 return-window hold | Not blocking; explicitly tenant policy under K-10. |
| R15 withdrawal restrictions | Intended rule retained; descendant wording should be updated (S3). |
| R16 one live overpayment | Not blocking by itself. Reissues are now additional members of that holding, not independent new money. |
| R17 one instant | Tree ordering fixes original UUID defect (00 Y4). The pool remains necessary, and must actually cover every descendant (B2). |
| R18 erroneous refund return | Explicit workflow limitation, not a new blocker; 00 W1 provides the refusal controls. |
| R19 app status timestamps | Explicit validation/stamping contract, not blocking; 00 W10/Y6. |
| R20 share attribution | Attribution is a defensible drafting choice. It does not authorize B1's surplus beside a family deficit or B2's detached source. |
| R21 measured cost | Not independently measured. No new performance blocker asserted; depth stress probe is correctness evidence to obtain, not a benchmark. |

### N4 — executed delivery; predicted results

Nine SQL files are delivered. `00` is the frozen battery plus diagnostic notices; 01/02 are full behavioral reproductions; 03-A/B are explicitly limited lock-topology probes; four retained regressions cover catalog, COPY, statement shapes and isolation. Run each standalone probe on a fresh r6 clone; run the 03 pair concurrently on the same fresh clone. Isolation regression has two separately rolled-back transactions. No probe commits fixtures or alters cluster roles. No probe result should be recorded as executed until the author actually runs it.
