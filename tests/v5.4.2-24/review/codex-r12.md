# Codex — v5.4.2-24, review round 12

**Verdict: ready.** No blocking production defect found in this source review. The r11 blocker and born-posted defect are addressed. One nonblocking should-fix remains in S4c: its new pending operand double-counts a pending payment that already has its posting entry. Thus **Codex r11 S1 / r10 S2 / r9 S1's general conservation-coverage concern is not fully closed**, although the specific nested-NSF, missing-reference and date-window counterexamples are repaired.

All database outcomes here are **predicted**, not executed by Codex. This verdict covers the additive record patch within its stated limits, not operational collections readiness or certification of the reported test runs.

## N1 — executed: identity and review scope

Checked the brief against `review-brief-24-r12.md5`, then all six frozen files before proceeding. All seven match:

| File | MD5 |
|---|---|
| review-brief-24-r12.md | 64cf3366ec3a915300c68edfab3e3ba2 |
| patch-24-frozen-r12.sql | 37630681b0dd63235ca3ab5c11b0b326 |
| battery-24-frozen-r12.sql | 96b21ecde4ab064aef61eb7285c0afa7 |
| suspense-24-frozen-r12.sh | 360dea4db148825d696134bfa30e0502 |
| mutations-24-frozen-r12.py | 87d1bec061a3ae71c64d20f335525f8e |
| ci-24-frozen-r12.diff | ec30f74364228bf3f325a1958583d01b |
| r11-to-r12.diff | ecb5feb6ae0fe7f9360bc6e4f002e186 |

Read the r12 plan first after verification, then the changes, relevant frozen source, inherited -23/-27 source, design, source inventory, DECISION-LOG, supplied CI-053/CI-056 and workflow rulings. Consulted my r11 review, my earlier probe sources and permitted author-run evidence, including 08b. No `opus-*.md` or `fable-*.md` was read. Other reviewers' finding IDs below come from the brief and plan.

Source-only checks: **33 matching embedded function-body hashes**, **352 battery assertion call sites**, **169 mutation entries**, and exactly one occurrence of each M168–M175 replacement anchor. These are not database test passes. No Docker, psql, CI, races or mutation runner was executed, and no work was delegated. Mutation inspection used AST parsing and literal-string counts, without importing or executing that module.

Only this review and [codex-r12-probes](codex-r12-probes/) were written. The 13 SQL files are independent: run each as owner on its own fresh clone with frozen r12 applied, following the brief's TEMP revocation. Each ends in ROLLBACK. Each caught error prints SQLSTATE and message via RAISE NOTICE. COPY controls catch the server-side COPY itself, including its own SQLSTATE/message, rather than consulting psql LAST_ERROR_SQLSTATE. They use a fixed generated `printf` payload through COPY FROM PROGRAM in the owner's privileged scratch environment. An unexpected ON_ERROR_STOP abort requires rollback/disconnection.

## B — predicted: none found

No concrete remaining bypass of the revised production ending rule was found. This is a scoped source conclusion, not an exhaustive proof over every history or concurrent schedule.

## S1 — predicted: the pending operand makes S4c count the same 100 twice

**Source:** frozen battery lines 1859–1860; `sql/tu.sql` final `payment_position_as_of` definition at 48206 and inherited `enforce_ledger_reversal` at 43009. **Probe:** [01-pending-conservation.sql](codex-r12-probes/01-pending-conservation.sql).

S4c adds both `sum(payment_position_as_of(...).received)` and the full amount of every currently pending receipt payment. But `received` is ledger-derived **whatever the payment's status**. A posting entry is deliberately inserted while its payment is pending; the status moves afterwards. The frozen battery itself uses this state in D7, then moves the payment to posted before S4c runs.

The probe creates an actual deposit payment from a receipt of 100 and extracts S4c's exact expression into a diagnostic query, changing only its output columns and removing the final inequality filter. Expected readings at March 10:

| State | Receipt held | Ledger received | S4c pending operand | S4c total |
|---|---:|---:|---:|---:|
| Pending, no posting entry | 0 | 0 | 100 | 100 |
| Pending, posting entry present | 0 | 100 | 100 | **200** |
| Same entry, moved to posted | 0 | 100 | 0 | 100 |

No trigger is disabled and no production function is replaced. The middle state follows the supported posting sequence. This is a false positive in the oracle, not evidence that production spent the receipt twice or lost money.

**Should fix:** count only pending money not already represented by the posting entry at the sampled coordinates. For example, use the pending amount less its ledger-received amount at those coordinates, or explicitly exclude pending payments whose posting entry is visible there. Preserve checks for both pending-without-entry and pending-with-entry states, including deposits. Do not fix this by excluding all pending payments from the ledger operand without considering the dates being sampled.

The revised first-NSF traversal itself fixes the reported r11 double counting: it starts once at the posting root and counts each descendant once. Link-only NSF rows are now included. The date set includes each receipt's own date and the expression runs after the history fixtures. These repairs are real; the new pending defect is why I still would not treat S4c as a general reconciliation oracle. Its label now correctly says business dates **read now**, not a full recorded-time equality grid.

## N2 — predicted: closure and the new code rule

Evidence: [00-frozen-battery-coverage.sql](codex-r12-probes/00-frozen-battery-coverage.sql), [02-code-shapes-and-births.sql](codex-r12-probes/02-code-shapes-and-births.sql), and 08–11/13 below.

| Round-11 item | Assessment |
|---|---|
| Fable B1: code over rows under the named reversal's undo | Closed for the reported case: P23 refuses it; P23b–c retain the uncoded return plus receipt bank-return route. Probe 02 extends the tree another level and varies the dates. |
| Fable S1: receipt payment born posted | Closed: the INSERT branch permits only pending or voided. O7c covers owner history load; probe 02 adds multi-row and COPY births. Earlier born-reversed/NSF controls O7/O7b remain. |
| Fable S2 / Opus S1 / Codex N3: deposit coverage | Closed in the permanent battery for the five identified walks: D1–D8 and D4b, with M171–M175. This does not close accepted agency-deposit refund limit L5. |
| Codex S1 / Fable N1 / Opus N2: S4c | Specific r11 shapes repaired by P24/P24b and the new traversal; the general concern remains as S1 above. |
| Opus N1: lock dependency comments | Added at both relevant checks. The inherited invariant suite, not just -24's manifest, protects the inherited triggers. |
| Remaining operational notes summarized in the plan | Still scope/application contracts: pending lifecycle, return-date reuse, deposit-event linkage. No new production fix claimed for these. |

The new rule is sufficient for the examined tree shapes because it composes with -23:

- The cause must be a direct, non-NSF reversal of the posting entry, and that entry must be wholly reversed. A cause typed NSF fails the inherited status transition check before the r12 predicate; probe 02 pins that refusal.
- Where the misposted share is nonzero, the cause's **own amount** must cover the payment and it must have **no immediate child**. Every deeper descendant needs such a child, so recursive search is unnecessary for this prohibition. Negative children, children later in business time and additional levels do not evade it. Probe 02 exercises each shape.
- A whole direct leaf remains usable even if an unrelated earlier branch was reversed and undone. Probe 02 uses the fresh leaf as the cause after refusing the old non-leaf cause. No rule forbids all historical activity elsewhere in the tree.
- Where share is zero and all money is represented as typed bank take-backs, a code remains allowed. Probe 02 includes an NSF grandchild beneath the named reversal's undo. The existing untyped-under-NSF prohibition still runs first; a zero share alone is not sufficient to bypass it.
- A later negative child of a successfully ended payment fails -23's ended-source rule. Probe 02 checks this. Positive rows cannot alone exceed the root cap, and a compensating multi-row write still encounters the negative-row ending guard. 08 and 13 cover statement-shape controls.

The deliberately stricter route is any attempt to label a non-leaf cause with a code while a nonzero misposted share remains, even if the operator considers the whole sequence a bank return. The prescribed uncoded return followed by receipt `bank_returned` remains available. I found no additional stranded-money case caused by that restriction.

Earlier reported production fixes remain in the unchanged source and regression probes: r10 coded mixed reversals, late code and untyped take-backs (00 P17–P22, 02/08/13); r9 historical share/undo interval (09–11); r6 full-tree business/recorded bounds (00 O and 09–10); receipt cap, provider namespace, pinned instruments, exact return, NaN, tenancy and helper-grant checks (00, 03–07). No earlier production finding was found reopened. Prior author runs support those historical controls but are not r12 executions.

## N3 — executed source inspection; database outcomes predicted: deposits and mutations

| Mutation | Named check | What makes the check discriminating |
|---|---|---|
| M171: final share omits deposit | D2 | Actual deposit root; final share must be 60. |
| M172: untyped walk omits deposit | D8 | Untyped positive descendant below a deposit bounce's undo must prevent NSF ending. |
| M173: pending guard omits deposit | D7 | A real pending deposit root is present; its attempted reversal must fail at the new ledger guard. |
| M174: return-date walk omits deposit | D4b | Return of the correct 60 is dated March 11, before the March 12 NSF row; the failure must identify the last-row date guard. |
| M175: as-of share omits deposit | D2 | Due is 60 on March 11 and absent on March 10. |

`fromr(p_deposit)` writes `is_deposit` at INSERT, and `post()` selects the deposit ledger kind. D1 checks the resulting row; these are not plain-payment fixtures renamed as deposits. D3/D4/D5/D6 additionally cover ending classification, exact amount and successful return.

The replacement anchors are unique. M172's removal leaves share zero and would otherwise admit the NSF ending, so its specified message is meaningful. M174's omitted tree leaves the date maxima NULL; the receipt cap alone does not replace the missing date check in this fixture. I found no concrete wrong-reason catch in these five changes. Runtime mutation outcomes remain unverified; probe 00 supplies the unmutated fixtures for author execution.

M118/M129/M138 at D2 respectively discriminate a zero-share listing, a posted partial reversal omitted from the queue, and future business-date share leaking into an earlier reading. M143 at P24b discriminates counting the direct link-only NSF as misposted. M168/M169 remove distinct components of the non-leaf rule but deliberately share P23. M170 targets O7c. These source mappings agree with the plan's re-anchoring; I did not rerun any mutant.

## N4 — predicted: design, bypass inventory and limits

Evidence: probe 00's U/P/X/A/L/G/S/T/O groups, [03-statement-shapes-and-roles.sql](codex-r12-probes/03-statement-shapes-and-roles.sql), 04–05 isolation controls, and [07-composition-controls.sql](codex-r12-probes/07-composition-controls.sql).

The patch remains additive U/L records pointing at payments. No matching function guesses a customer, no receipt automatically becomes revenue, and payments carry required resolution evidence. The database cannot establish the truth of an operator's explanation. CI-053's holding and return mechanisms match the supplied design; CI-056's dated queues supply inputs to the core and -26, rather than executing a disconnect pause themselves.

| Attempt | Defense / probe coverage |
|---|---|
| Receipt spent twice, including payment plus disposition | Datewise cap under receipt lock; 00 P/X/O, 03 multi-row/CTE/COPY. |
| Before-receipt payment date, late effective date, missing reason/user, other tenant | Explicit guards, CHECKs, immutable provenance, composite keys and RLS; 00 P/T/O. |
| Duplicate provider transaction, including late assignment | Shared provider namespace lock and update check; 00 U/P, 03–05. |
| Pledge paid by wrong agency/customer or without its bill restriction | Identity and restriction checks; 00 L. |
| Pledge ended twice, early lapse or paid after recorded-in-error | Unique ending, pay-by/date checks and payment/event handshake; 00 L, 03's two dependent CTE directions. |
| Agency money refunded to customer/other agency, or customer money to agency | Typed lineage through payments, overpayment/refund/shortfall reissues; 00 G, 07. |
| Agency revived or agreement terms edited | Irreversible retirement and immutable terms; 00 A, 03 owner controls. |
| Core write or privileged load bypass | ACL controls in 00/03/06/08; owner history and replica controls in 00/02/08. |

The database chooses agreement/pay-by, permits real agency money above the pledge, and gives paid-in-full precedence in the position reader (00 A/L). Stronger-isolation rejection is covered by 04/05 and the battery's isolation cases. Ordered statements are the supported history-load path; writable CTE siblings are not a promise of application-selected execution order.

I do not promote L1–L6 to blockers: candidate quality (L1), jurisdictional protection evaluation (L2), remittance batching (L3), close snapshot integration (L4), agency deposit returns (L5), and untyped credit origins (L6) remain explicit boundaries. Ryan's November 7 DECISION-LOG entry expressly accepts L5/L6 while retaining the core's agency-refund duty. The deposit fixtures test payment-tree handling, not payee enforcement on deposit events. Likewise, a passing database suite would not certify operational CI-056 escalation or disconnection prevention.

## N5 — predicted: -23/-27 composition, concurrency and invariants

Evidence: 00, 02–08 and 13; [06-catalog-contract.sql](codex-r12-probes/06-catalog-contract.sql) prints actual order, effective privileges, relevant live definitions and runs the four applicable invariant functions. These are single-session probes, not execution of a concurrent schedule.

-24 reissues no existing -23/-27 function. Ordinary payment/ledger lineage, caps and recorded-order guards continue to participate. Probe 07 retains the paid-out-refund/debt composition control; returning a misposted share does not erase money already paid out. The CI diff ports the -23 agency fixture to supply agency identity, rather than weakening its cash assertions.

Trigger order matters: `enforce_payment_immutable` precedes `enforce_payment_suspense_pledge`, validating the status cause and holding the payment source lock before the new tree reads. `enforce_ledger_reversal` precedes `enforce_ledger_suspense_posted`, taking the corresponding source lock before that pending check. -27's shortfall guard also participates in ledger processing. The new pending check adds no lock acquisition and reads the parent first, returning for a non-payment charge before attempting payments SELECT. Probe 08 uses the author-validated literal-ID fix for the `tally_void` branch, avoiding the old probe's missing helper permission.

Receipt-cap write callers hold the receipt lock; dispositions check the cap after their statement's rows exist. Provider uniqueness and pledge/event writers retain their own lock handshakes and READ COMMITTED pins. I found no newly introduced cap write path reading its projection without its ordering lock. Helpers exposed for reads are not independent authorization to write.

The ending checks hold the payment source lock without newly taking the receipt lock. A return disposition takes the receipt lock and requires an already-ended source; inherited terminal/tree restrictions supply the stable share. An uncommitted ending can cause immediate refusal and retry, as the frozen SU14/SU14b source expects. SU13 and SU15/SU15b cover the other changed-rule interleavings in source. I did not execute them and make no claim to have independently reproduced the author-reported 29 race results. Arbitrary multi-object transactions still need the documented 40P01/40001 retry discipline; this is not a universal deadlock-freedom claim.

The -24 invariant verifies its listed exact trigger definitions/ALWAYS state, required constraints and indexes, RLS/FORCE RLS and policy shape, grants, NOT NULL fields, function bodies and attributes, and required helper execution. The patch tail calls inherited invariant functions too; -24's own manifest is not a standalone pin of every inherited trigger. Probe 00 I deliberately damages catalog contracts within caught subtransactions; 06 reports the combined suite. The claim should remain “the listed guards,” not a semantic proof or an exhaustive whitelist of every possible database object. No new mismatch in the changed function-body manifest was found.

## N6 — predicted: probe map and verification boundary

| Probe | Purpose |
|---|---|
| 00 | Frozen r12 battery with SQLSTATE/message notices added to caught errors; all 352 assertion sites preserved. |
| 01 | New pending-with-posting-entry S4c counterexample, with before/after controls. |
| 02 | Whole leaf, negative child, deeper/later descendants, all-NSF subtree, NSF cause, owner replica, multi-row/COPY born-posted controls. |
| 03 | Cap statement shapes, COPY, core permissions, agreement/retirement and pledge/error CTE controls. |
| 04–05 | REPEATABLE READ and SERIALIZABLE refusal controls. |
| 06 | Catalog, inherited invariants, trigger order and writer privileges. |
| 07 | Refund/deposit/shortfall composition regressions. |
| 08 | Pending root/reversal multi-row and COPY, ordered owner load, late code, `tally_void` and core branches. |
| 09–11 | Historical business date, recorded time and omitted-history regressions. |
| 13 | Dependent NSF-ending/return CTE and duplicate-return COPY. |

The carry-forward probes retain historical labels where they describe the original regression; they target fresh frozen-r12 clones now. Some are diagnostic observation probes that print accepted/refused outcomes rather than asserting every result. Their output must be compared with their expected labels, not counted as a pass merely because the script reaches ROLLBACK.

Strict apply twice, 352 passing checks, 29 race results, 169 caught mutations and 61 CI steps remain **author-reported**, not executed by Codex. The source-only verdict leaves one should-fix in test coverage, S1, and no demonstrated production blocker.
