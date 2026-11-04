# Codex — v5.4.2-23, round 10

Verdict: **ready**.

**Executed: source review only.** The eight frozen MD5s were checked first and matched. No Docker, psql, apply, CI, race, mutation runner or database experiment was run. Neither `opus-r9.md` nor `fable-r9.md` was read. The r10 brief's top section governs this review. Reviewed the frozen patch, the changes from r8 through r10, relevant battery/race/mutation sources and older-test adaptations, all three r8 reviews, the design/inventory, r9 plan, DECISION-LOG, AC-44 and the supplied Kyle rulings. `tests/ci.sh` was read to check the vacuum placement; it was not run and is not a frozen artifact here.

**Predicted** below means behavioral analysis from source, with author-run probes supplied. **Executed** means file/hash/source inspection, never a database result. The reported 409 battery checks, 51 race results, mutation results, strict applies and timings remain author evidence. Readiness is a source-review judgment, not independent certification of those runs.

## Frozen files — executed

| File | MD5 |
| --- | --- |
| patch-23-frozen-r10.sql | 9529d1f0a416f12ab7f49199b1ec3742 |
| battery-23-frozen-r10.sql | 9127ab84d20c118e893aa9d15673e56a |
| cash-23-frozen-r10.sh | b77dba8b96637d66100e684af6405237 |
| mutations-23-frozen-r10.py | 912628a1f71984536ac611f47ade5d9d |
| older-tests-23-frozen-r5.diff | be99c2f963ab9f2177c9f059a4de7e5c |
| patch-23-r8-to-r9.diff | 89767fea98e8c239debc75b2f37321cd |
| patch-23-r9-to-r10.diff | a0c77469fcb2775071887b17ce82d6a1 |
| tests-23-r9-to-r10.diff | 6f869eeadec6cee184781f31f579e974 |

## Blocking items

None identified. In particular, I do not carry forward Codex r8 B1 or Opus r8 B1/B2 as blockers.

## Round-8 findings, item by item

Probe abbreviations refer to files in [codex-r10-probes](codex-r10-probes/): **00** bounded battery; **01** leaving-history; **02** order-privileges; **03** same-instant-share; **07–10** retained catalog, COPY, statement-shape and isolation controls. All database outcomes in these tables are **predicted**.

| Codex r8 item | Disposition | Evidence |
| --- | --- | --- |
| B1 mandatory carry rejected by existing family deficit | **Closed — predicted** | `check_cash_source` exempts exactly `reissue` and `overpayment_credit` from the family cap, after the own-source cap and all earlier checks. 00 U1–U1f retains the 60 take-back case: required 20 carry, deferred settlement and external-cent refusals. N227 targets removal of the exemption; N228 targets widening it to refunds. |
| S1 planted Z6 described as full-history evidence | **Closed — executed** | Z6 now explicitly labels the planted ancestors and guarded endpoint. Z7 separately constructs 20 generations with posting/return rows and constraint flushes. 00 retains Z7; it deliberately omits Z6 to avoid the known long-running statistics case. No 999-generation full-history or timing claim is made. |
| S2 exact-cap header and misleading descendant COMMENT | **Closed — executed** | Header 128–134 marks the old equality promise withdrawn. `enforce_ledger_reversal` now says descendants hold up the bounce the same way. The credit immutable COMMENT also names the payment lock on escheat. |
| N1 rulings and reissue sizing | **Closed for the identified issue — predicted** | 00 Q4/Q5 and U1–U3 cover own-side settlement and carry; the 11-04 decision resolves the exemption. 03 retains the equal-instant qualification. |
| N2 locks, roles, isolation and statement shapes | **Closed as scoped review — predicted** | The new leaving calls use the payment lock already acquired. 01, 07–10; actual concurrent waiting remains the frozen race suite's author-run evidence. No universal deadlock-freedom claim. |
| N3 invariants/mutation attribution | **Closed for the identified coverage — executed** | Exact-cap assertions restored in agree_side; N232/N233 added, N207 re-anchored; r10 additionally covers the order helpers' grants/existence. Predicted catalog checks: 02/07. |
| N4 R1–R24 | **Closed as accepted scope — executed** | R17 repaired, R21 qualified, R22–R24 retained. The earlier table's R19 description was my error: R19 concerns supplied status timestamps, not reissue-lineage immutability. |
| N5 probe provenance | **Closed — executed** | New r10 files are unexecuted; earlier author-run files are not represented as current results. |

| Opus r8 item | Disposition | Evidence |
| --- | --- | --- |
| B1 J, old-stamped return moves share off escheated sibling | **Closed — predicted** | New leaving-order call on refund void/nsf/reversed, after source locks; 01 reproduces J with chosen instants and checks the diagnostic and subsequent valid return. CR27 supplies the actual transaction-start schedule. |
| B2 payment/overpayment own caps not tested | **Closed — predicted** | agree_side attempts exact `least(own,pool)` and a cent above it for each eligible side. N232/mA and N233/mB target the two missing legs. 00 Y0d/Y7j/U4a exercise them. |
| S1 one-statement reissue sized after subtracting its own draw | **Closed — predicted** | `enforce_cash_draw` adds amount minus recorded share, not new-credit remaining. 00 U2 rejects 15 plus draw 5; U2a admits 20 plus draw 5. N231 restores the defect. |
| S2 statistics sensitivity | **Closed as documentation/test setup; performance unverified — executed** | R21 withdraws statistics independence and records the failed extra-pin experiment. The frozen mutation runner vacuums three tables; live ci.sh 124–127 does likewise before the battery. This does not solve all bad-statistics latency, nor claim to. |
| S3 comments, escheat lock and R17 | **Closed — executed** | Both named comments revised; R17 replaces acceptance of retroactive return attribution with retry. Its same-instant exception still matters (N3 below). |
| N1 lock order and multi-act cycle | **Closed as retained limitation — executed source assessment** | The new helper acquires no new lock. Existing multi-act/row-lock inversions remain within the retry contract; source inspection does not certify all transaction compositions. |
| N2 own helper / legitimate settlement | **Closed for named shapes — predicted** | 00 Q4a, Z4f, Q5 and U1; no blanket claim that every imaginable workflow is admitted. |
| N3 overcarry/stranding | **Closed for identified statement shape — predicted** | 00 U2/U2a and U3; issued-side term retains the share subtraction (03). |
| N4 residuals | **Closed — executed** | R17's identified cross-transaction exception is removed. R21–R24 are explicit limits, not hidden guarantees. |
| N5 mutation gaps | **Closed — executed** | N232/N233 address the missing cap legs; first-failure attribution remains in the runner. Their outcomes are not independently measured. |
| N6 role/isolation observations | **Closed as scoped observation — predicted** | New helper is STABLE, invoker-rights, PUBLIC revoked, app EXECUTE; caller guards still require READ COMMITTED. 02/07/10. |

| Fable r8 item | Disposition | Evidence |
| --- | --- | --- |
| S1 exact payable cap at every agree site | **Closed — predicted** | 00's agree_side checks the exact cap and cap-plus-cent as well as position, pool, sign and conservation properties. N232/N233 and N207 anchor at agree sites. |
| S2 P-G active-credit reissue | **Closed — predicted** | 00 U3–U3f records the own-40/covered-30 distinction, rejects 30, carries 40, and checks the later escheat refusal. |
| N1 locking/FR1 | **Closed as retained scoped observation — predicted** | Source locks retained; 01 covers a sibling escheat followed by a return, 00 covers deferred settlement. Fable's earlier actual FR1 run is historical evidence only. |
| N2 own-side helper admits legitimate cases | **Closed for named shapes — predicted** | Q4a/Z4f/Q5/U1 in 00. The absolute “nothing legitimate” wording is not a universal proof. |
| N3 new reissue has no share/draws at insert | **Partly closed / qualified — predicted** | Ordinary distinct-instant creation has no prior share. Same-statement draws are precisely what U2 fixes; equal-instant take-backs can affect a new reissue, so “no share at insert” is not unconditional. 03 tests this. The code correctly retains the share subtraction; no new blocker. |
| N4 pinned set/invariant | **Closed as source correspondence — executed** | Nine named cash walk functions retain their pins and catalog checks; customer_credit_draws_as_of is deliberately unpinned. 07 is the author-run catalog control. |
| N5 roles/isolation/shapes | **Closed as scoped observation — predicted** | 00 U2 and 07–10; no new definer or ordinary-writer bypass introduced by the exemption. |
| N6 mutations | **Closed — executed** | Existing anchors retained/revised and new exact-cap anchors supplied. First-failure logic is preserved. |
| N7 R23/R24/AC-44 | **Closed as accepted contract — executed** | Per-jurisdiction escheat setoff, absent-rule default and -27's future closing application remain explicit. |
| N8 SET CONSTRAINTS quirk | **Closed in test sequencing — executed** | hback_settled defers before performing the return/carry; Z7 restores deferred mode between generations. Predicted execution: 00. |
| N9 residuals | **Closed — executed** | No newly discovered blocker in their accepted boundaries. |
| N10 container count | **Not a patch finding — executed** | No container inspection or count asserted. |

## Should-fix items

### S1 — executed: stale test inventory and statistics comment

Frozen patch 450–452 still advertises **390 checks, CR1–CR26/40 results, 225 mutations**. The r10 brief reports 409/51/233. The mutation runner's introduction still labels its race range CR1–CR25, and its comment before VACUUM calls that state “the worst statistics,” despite R21 explaining the worse pages-present/zero-estimate state. Update these descriptions to the current inventory and the actual purpose of VACUUM. This is documentation only and does not block readiness. No runtime counts were measured here.

## Notes and remaining review questions

### N1 — executed authority comparison; predicted enforcement: the rulings and internal-move exemption

K-10 remains two distinct limits: bank reversals use their tree cap, while external draws use source and family caps. The pending-refund hold-up remains; the cancellation screen and return-window policy stay outside -23. Kyle's 10-30 one-pot ruling is implemented within a payment, with customer-wide presentation/netting delegated to AC-44. Option A expressly allows a line's attributed position to be lower than its next payable amount. Ryan's 10-21 own-money settlement and 11-04 exemption are mutually compatible now. Probes: 00 V/W/Y/Q/U.

The exemption is narrow in code: it sits inside the non-undo branch and skips only the family aggregate. It neither skips the predecessor's own cap nor changes a refund/application/donation/remittance purpose. A reissue can therefore record the internal carry despite an existing family deficit, while a subsequent external draw still faces that deficit. U1 supplies the specific formerly impossible return and external-cent controls.

Including `overpayment_credit` follows the explicit 11-04 call. That amount is excluded from the family aggregate just as a reissue is; its payment-side cap still counts it. On the normal first-hold path, the payment's own cap already measures the relevant cash, so the extra exemption is largely redundant rather than a new allowance to pay out. A voided old root cannot have retained ordinary draws under the void guard; creating another hold does not erase external payouts. These conclusions are scoped to guarded histories, not arbitrary owner-planted inconsistent rows. 00 C1/R7/W controls exercise those boundaries.

### N2 — predicted: leaving-order coverage and retry viability

Patch 2499–2507 and 2627–2635 call the new helper under the payment mutex. The helper (3141 onward) compares the move's stamp against **every descendant** of the payment's arrival entry, not just direct take-backs. The existing reversal guard takes the same payment mutex before its share-dependent checks. No new lock rank is introduced.

The share inputs were traced individually:

- Refund cancellation/return changes whether a refund counts at an earlier instant: new payment-status call.
- Family-credit void changes the predecessor's carried draw and credit lifetime: new credit-status call, with the old no-share and active-predecessor checks retained.
- Application undo and donation undo are append-only rows: both already call check_cash_source with purpose `undo`, which still invokes check_cash_order against the family's payment arrival entry before skipping arithmetic caps.
- Remittance is a new draw and already ordered by that path. The escheated label itself does not remove that draw or the credit from the share calculation. No separate remittance-undo path is introduced here.

01 supplies old chosen-time return/void refusals, valid later moves, own-zero assertions on escheated siblings, and the transaction-start 40001 branch using an owner-stamped, already-reached later wall clock. It does **not** prove snapshot refresh after a concurrent wait; CR27/CR28c are the actual concurrent source fixtures. Ordinary retry advances transaction start past the already-finite recorded rows. A chosen historical time deliberately stays invalid until corrected; that is 23514, not an endlessly retryable 40001. No future-time row admitted by these guards was found to make ordinary retry permanently impossible.

CR28c improves N230's evidence materially: the voided sibling carries no share, so the old share-bearing-void restriction is not the reason for refusal. CR28 remains useful separately: after retry its void is still substantively invalid. This distinction is faithfully documented in the race source. The 01 V analogue verifies the new diagnostic rather than accepting any refusal.

### N3 — predicted: exact caps, statement shapes, roles and the remaining equal-instant boundary

The payment formula in agree() uses received minus applied/refunded minus the live overpayment credit's original amount plus **all family shares as recorded**, with cover disabled. That corresponds to the payment-side cap's subtraction of `amount - absorbed` for tree rows. A voided root contributes no held amount/share; a payment not posted is assigned zero drawable capacity. This is an end-of-fixture oracle, where the proposed refund date follows the fixture's cash dates; it is not a general arbitrary-date quote API. The existing cap continues checking every relevant date. Probe 00 preserves these assertions and date controls.

A non-posted payment with a positive historical ledger reading is not thereby drawable: agree()'s zero payable allowance must not be read as changing lifecycle eligibility. Likewise the helper's single 23514 expectation for negative tests is not proof of the precise refusing guard; its positive exact-boundary attempts and the targeted mutations are important complementary checks.

A new reissue's share is not universally zero at insert. The share walker includes credits whose recorded time is **equal** to the take-back's, and AFTER triggers can see another modifying CTE's row. Probe 03 predicts a 20 reissue plus same-statement take-back of 5 will fail the size check with only 15 on the issued side. Its separate two-statement control demonstrates a share of 5 on the newly made reissue at the shared instant. This is R17's existing same-instant/one-act-per-transaction qualification, not the U2 reissue-plus-refund bug. Do not simplify the repaired term to original_amount alone.

The new leaving guard uses `>`; it does not establish a total order within one recorded instant. Consequently the final “shares ... fixed once recorded” sentence in R17/helper comments must be read with R17's explicit same-instant exception. It is the cross-transaction retroactive return/void defect that this round closes, not every possible grouping of acts at equal timestamps.

07–10 supply invoker/grant/catalog, COPY-arrival, multi-row/CTE donation and REPEATABLE READ/SERIALIZABLE controls. The last two isolation levels are deliberately refused for these writes. Owner history stamps remain a privileged input path and are time-checked; deliberately disabling guards is outside ordinary enforcement. No new role escalation or cap bypass was identified by source inspection. This is bounded coverage, not a proof over every role, statement shape or arbitrary multi-act transaction.

### N4 — executed source assessment; predicted catalog checks: invariants and mutations

The r10 order-helper invariant safely tests existence with to_regprocedure before asking for privileges. It checks PUBLIC, tally_core and tally_app for both signatures. 02 supplies all eight perturbations (each helper missing/renamed, PUBLIC grant, core grant, app revoke), with rollback of each perturbation and a restored-baseline check. N234 covers the leaving-helper core-grant leg in the frozen runner; it does not alone cover the entire matrix.

The invariant remains a catalog-definition/settings/privilege check, not a check of helper bodies or arithmetic equivalence. The COMMENT states that boundary. N227–N233 target the intended changes; N232/N233 match the two previously escaping mutations, and the earlier agree anchors explain N207's relabel. The runner retains first-failure matching and does not credit a behavioral mutation merely because application failed. I found no specific wrong-reason attribution in the new legs from source; I did not reproduce their first failures.

The older-test diff includes some explicitly marked -25-related adaptations as well as the cash changes. It is an integration diff, not evidence that -25 is needed to run this review's r10 probes. No earlier-battery or CI pass is claimed here.

### N5 — executed scope assessment: R1–R24 and AC-44

| Residual | Assessment |
| --- | --- |
| R1 | Accepted ledger-depth/cost bound; no fresh timing claim. |
| R2 | Recorded-coordinate/open-transaction model retained; temporal controls in 00. |
| R3 | Paid/partial invoice labels remain application lifecycle. |
| R4 | Undo/rebill application workflow remains the core's. |
| R5 | Repeated charge-type list remains a maintenance obligation. |
| R6 | Source-less line classification remains the core's. |
| R7 | Allocation, floor decisions and notices remain outside these guards. |
| R8 | Earlier-test adaptations explicit; integration execution not reviewed as a fresh result. |
| R9 | Tariff service/system matching remains delegated. |
| R10 | Deposit-wide event cap remains earlier deposit machinery's scope. |
| R11 | Long statements and timeout policy remain operational limits. |
| R12 | Refund-return ledger row/status belong together; U1 now provides the previously missing settlement path. |
| R13 | Pending-refund cancellation UI remains application work. |
| R14 | Return-window hold remains utility policy. |
| R15 | Pending refund/application hold-up includes family descendants; 00. |
| R16 | One live overpayment root retained; 00/07. |
| R17 | Cross-transaction retroactive leaving moves repaired; same-instant exception retained, 01/03. |
| R18 | Mistaken terminal refund-return correction limitation accepted. |
| R19 | Supplied status-time validation/stamping retained; 00 W10/Y controls. |
| R20 | Option A remains the chosen attribution contract. |
| R21 | Statistics sensitivity and depth cost disclosed; no latency certification. |
| R22 | Share-bearing reissue void restriction remains accepted; 00 Z5. |
| R23 | Customer-wide netting is core work, per-jurisdiction before escheat; -27 records it. |
| R24 | Permanently netted active credit and -27 closing act remain explicit; 00 U3e. |

None is independently blocking under the decisions supplied. AC-44 still requires one customer-facing net number, an application rather than an invented charge to record shortfall netting, and full own-money reporting where the state's setoff rule is absent or disallows it. This is comparison with the project's approved contract, not a new legal opinion or certification that the future core/-27 implementation exists.

### N6 — executed: probe delivery and limits

Eight SQL files are supplied. Run each independently as owner on a fresh clone with frozen r10 strictly applied and clone TEMP revoked from PUBLIC, tally_app and tally_core. No probe creates, drops or alters roles; 02 changes only function names/ACLs transactionally. Every file ends in ROLLBACK. Probe 10 has two independently rolled-back isolation transactions.

00 is the frozen battery with the planted Z6 block omitted, every caught error given a SQLSTATE/message NOTICE, and a 180-second statement timeout. Its result is **not** a reproduction of all 409 frozen checks. Z7 remains the guarded 20-generation history control. 01/03 use extracted frozen history helpers with enabled guards, not concurrent sessions. 02 tests the new catalog invariant. 07–10 retain earlier controls with r10 provenance. COPY prints its native verbose error and `\errverbose`; it never relies on LAST_ERROR_SQLSTATE. P0099 in 00 is the intentional rollback sentinel, not a guard refusal. An unexpected setup error, cancellation or timeout is not a pass.

Only this review and files under codex-r10-probes were written. All predicted conclusions remain subject to the author's probe execution.
