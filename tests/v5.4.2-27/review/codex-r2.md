# Codex — v5.4.2-27, review round 2

Verdict: **not yet**.

Source-only review, 2026-11-05. **Executed** below means a checksum, source inspection/comparison, or reading the explicitly permitted author-run output. It never means I executed SQL. **Predicted** means an unexecuted database result, with a probe in `codex-r2-probes/`. No Docker, psql, CI, race script or mutation runner was run. No `opus-*.md` or `fable-*.md` was read. Only this review and that probe directory were written.

## N1 — executed: freeze and authority

All five frozen hashes and the brief hash matched before source review:

| File | MD5 |
| --- | --- |
| review-brief-27-r2.md | 30a0fc2a826ff8c2e555cbc6a06328cd |
| patch-27-frozen-r2.sql | 79e7e66ec056021ca25ea2fb1f6e0572 |
| battery-27-frozen-r2.sql | 649c6819e6bae52a1a9df0282ebad621 |
| shortfall-27-frozen-r2.sh | 23de66442939d138e9136063fd99ec82 |
| mutations-27-frozen-r2.py | 8bad2a3cb325357e3b87a8d057ea2b26 |
| r1-to-r2.diff | 0e91aa155354216727ef9a665cd15f51 |

The first matches `review-brief-27-r2.md5`. Authority: -27 design, especially section 9; merged r2 plan; tally-utility DECISION-LOG's -27 design and r1 rulings; AC-44 and wave-2 inventory; gas-billing-memory's Kyle rulings of 2026-10-21 and 2026-10-30. The later explicit decisions control the older inventory/design descriptions.

## B1 — predicted: a history-loaded carry can be born escheated while holding the returned money

Evidence: frozen patch `enforce_shortfall_reissue`, lines 1248–1294, checks the **old** credit's status, the undo, depth, date, size and source cap. It never checks the **new** credit's status or settlement. `enforce_shortfall_reissue_rows` guards a credit's UPDATE, not its INSERT (lines 1363–1367). The inherited `enforce_cash_birth` explicitly returns early for a superuser (`sql/tu.sql`, lines 45144–45146). The new deferred check reads only `NEW.customer_credit_id`, the undo's old source (patch lines 1303–1322).

[06-carry-history.sql](codex-r2-probes/06-carry-history.sql) constructs the ordinary E fixture using normal triggers: a 50 credit pays 30 of a bounced payment's shortfall, remits its other 20 and ends escheated. As the owner/superuser, undo the 30, record the refund's return, and INSERT the 30 `shortfall_reissue` with `status='escheated'` and a finite status time. Force all deferred constraints.

Prediction: accepted, with old remaining 0 and new remaining 30, although the new credit is terminal and has no remittance. The probe prints both readings and the new status, or the actual refusal's SQLSTATE/message. No guard is disabled, no role is changed, and the final transaction rolls back. This is specifically the supported superuser history-load path, not the general observation that a superuser can disable enforcement.

That strands the very money Ryan's carry ruling is intended to preserve. A historical status is allowed by the inherited birth function, but that exemption does not establish settlement of a newly introduced carry. Require a valid birth/settlement for this origin, including history loads: either require active birth and record its ending through the normal checked transition, or validate an imported terminal state with its actual money movements. Add an invariant-backed guard and regression.

The same probe separately tries birth as `voided`. Prediction: the INSERT itself is admitted, but the old-credit settlement check rejects this ordinary positive-remainder case. **That second case is not claimed to be a committed money bypass.** It shows why the UPDATE-only “never voided” rule is not by itself a universal birth invariant. The omitted voided-reissue reader branches are justified only once this origin's never-voided property holds for history loads too.

## N2 — executed: disposition of my r1 findings

- **r1 B1: fixed for the reported sequence.** The permitted `01-latest-date-hole.author-run-r2.txt` reports 23514 at March 13 and no undo rows. r2 uses the first positive repayment's date and projects each corrective undo back to its own repayment for a leaving move. The reproduced r2 request is [01-latest-date-hole.sql](codex-r2-probes/01-latest-date-hole.sql); it is not a new execution by me.
- **r1 S1: fixed.** The permitted r2 rerun of probe 02 reports 0LP01 for all three changes. Source now independently requires app SELECT/INSERT and core SELECT, and forbids core REFERENCES/TRIGGER and forbidden column grants. [02-invariant-privileges.sql](codex-r2-probes/02-invariant-privileges.sql) preserves the author-run reproduction.
- **r1 S2: fixed in the recorded-order helper's control flow.** `begun()` gives both handshakes deadlines, keeps B marked while A exists, checks B's exit before waiting for A, and calls `reap()` on failure. The main session command has a 30-second statement timeout. This is source evidence, not an executed race. The comment “every session” is slightly broader than the implementation: the direct monitoring/termination psql commands do not use the timed `PSQL` array. Their database queries are simple, but their clients have no independent process deadline.
- **r1 N1–N5:** freeze/authority refreshed here; function comparison updated in N3; behavior/statement-shape probes refreshed in N4; concurrency and test limitations updated in N5/S1; residual assessment updated in N6. No r1 note is being treated as an unexecuted r2 pass.

## N3 — executed: carry implementation, reissued functions and -23 integration

I extracted and diffed the last definitions of all five newly reissued functions against `sql/tu.sql`.

| Function | Executable difference |
| --- | --- |
| `reissue_generation` | Follow either refund or shortfall-undo ancestry. |
| `overpayment_root` | Same new ancestry branch. |
| `overpayment_family` | Add the downward shortfall-undo/carry leg. |
| `customer_credit_position_as_of` | Treat a non-family shortfall reissue's issued amount like a refund reissue's. |
| `cash_drawn_at` | Add source shortfall applications, target repayments and carry draws. |

No unrelated executable change appeared. `cash_drawn_at` changes more than just the carry branch, as the merged plan expressly requires. The three recursive walks retain their plan settings, common depth bound and explicit over-depth error. Existing refund-reissue constraints and the new origin/link equivalence keep the two parent kinds mutually exclusive.

The ordinary carry code follows the ruling: tenant/customer-qualified undo FK; one carry per undo; old source must be an escheated credit; undo date and depth checks; size from old own remainder plus the new credit's original amount less its recorded share; source check with purpose `reissue`; deferred old-credit settlement; no issuing ledger row; fixed key; forbidden UPDATE to voided. Its size expression preserves -23 r9's use of issued amount rather than the new credit's remaining after its draws. B1 is the missing birth-state qualification.

`cash_source_draws`, `customer_credit_draws_as_of`, and `cash_drawn_at` each have the carry leg. The family cap excludes internal credit amounts and counts external draws. The unchanged share/cover routines consume the extended family and draw readers. The two omitted voided-reissue legs and the credit-issued-tree exclusion have the stated rationale; the latter has a new INSERT ledger guard. I found no further missing live-reader branch in the `refund_reissue` references inspected in `tu.sql`.

## N4 — predicted: behavioral probes and statement shapes

All probes are standalone owner-session scripts for a fresh clone with frozen r2 applied; fixtures and any role switches are local, no role DDL, and each ends in ROLLBACK. Caught errors print full SQLSTATE and message. COPY prints its own verbose error and `\errverbose`, never relying on `LAST_ERROR_SQLSTATE`.

- [00-baseline.sql](codex-r2-probes/00-baseline.sql): frozen r2 battery with error notices added. It supplies the requested reproducible predictions for its ordinary caps, target exclusions, cover, shares, chosen-time history, carry, append-only/RLS and privilege checks. It is **not** evidence of another 116-check pass.
- [04-statement-shapes.sql](codex-r2-probes/04-statement-shapes.sql), [05-copy.sql](codex-r2-probes/05-copy.sql): refreshed r1 multi-row/writable-CTE and COPY over-cap cases, predicted refusal. Application cases run as tally_app after owner setup; COPY runs as owner.
- [07-two-undos.sql](codex-r2-probes/07-two-undos.sql): queue two partial undos, first show deferred refusal without carries, then insert both correctly sized carries in one multi-row statement. Predicted old remainder 0, new credits 10 and 20, deferred checks satisfied.
- [08-mixed-family.sql](codex-r2-probes/08-mixed-family.sql): extend E13 before the family's bounce into overpayment → shortfall_reissue → refund_reissue → shortfall_reissue. Predicted generations 2 and 3 for the last two credits, common root/family, and a later take-back reaching the final carry. This tests both mixed directions, including a refund returned after the shortfall reissue itself escheats.
- [09-boundary.sql](codex-r2-probes/09-boundary.sql): add a genuinely partial undo of the later repayment; predict refusal of the earlier refund's return. After the correct undo/return, retain C4's refusal of a back-dated replacement and predict acceptance of a March 20 replacement. Thus the strict repayment check can refuse historical placement without necessarily trapping a current correction.

A separate transaction cannot normally defer the old credit's positive remainder past the first transaction's constraint check; E3/07 exercise that boundary via SET CONSTRAINTS rather than committing fixtures. I have not reproduced an actual two-transaction carry sequence. A carry before an existing undo, and a carry from an active source, have explicit source/FK checks, but no dedicated new execution is claimed here. Nor do the supplied multi-row probes establish every possible writable CTE that creates and immediately spends a carry.

## S1 — executed: the test deliverable is narrower than the brief and merged plan

The frozen E section stops at E14c. It does **not** contain the promised invoice application of a carry, escheated invoice-application undo refusal, or refund_reissue of an escheated shortfall_reissue. It also has no reverse mixed-chain case. Probe 08 supplies an author-run candidate for the two mixed directions; fold suitable cases into the battery.

C2 undoes **all 20** of the later repayment, not part of it. The brief describes a partial-undo variant; probe 09 supplies one. E7c's label claims unchanged customer balance but its assertion only checks that no ledger row references the new credit. Compare the before/after account balance as K3b does, or narrow that label.

The omitted invoice-application undo on a repaid family shares `check_cash_source(..., 'undo', ...)` with donation undo, so U2/M15 cover that callee. They do not establish that the invoice writer continues to call it with the correct source/purpose. I would retain the plan's small caller-level regression, especially the escheated-source refusal: r2 intentionally grants a new exception to shortfall undo only.

The 58 mutation definitions do not cover literally every new rule: the old source's escheated-status requirement, the new carry's depth check, and a carry's birth status lack dedicated mutations. M47 checks the carry term in `cash_drawn_at`, not its new source-shortfall and target-repayment terms independently. Add focused coverage rather than presenting 58/58 as exhaustive. The runner does require the named first failing check; I found no specific frozen mutation demonstrably credited for the wrong reason from source alone. M38 being caught at E3 for the wrong refusal is intentional: the helper checks the expected SQLSTATE **and** guard text.

## N5 — executed: locks, isolation and invariant scope

The new carry takes its source family's payment lock, then the old credit lock, matching `check_cash_source`; an ordinary same-transaction undo already holds target then source-family locks. The size read follows those source locks. The pre-lock source-status lookup is a potential stale observation in isolation, but a normal escheated status is terminal, and the subsequent source checker rereads under lock. I found no additional unlocked cap read in the new ordinary writer paths. The deferred check relies on the undo's transaction-held source lock.

Across different families the target-first/source-family-second order can form cycles; this is the documented retry boundary, not a claim of deadlock freedom. Same-family order remains payment then credit. No concurrency result was executed by me. SR9 adds the family-refund-return race; the new carry has no dedicated race of its own in this frozen harness.

The shared writer checks explicitly require READ COMMITTED. SR7 tests REPEATABLE READ; there is no separate SERIALIZABLE case. The source comparison supports the intended shared rejection branch, not an independently observed SERIALIZABLE result.

The invariant now includes exact new trigger definitions/ALWAYS flags, validated constraint definitions, the unique index, RLS policy and privileges. It is a definition invariant, not a proof of function semantics or existing data validity, and correctly disclaims body checks. It will not discover B1: the expected definitions themselves omit carry-birth settlement. Similarly, comments saying an ended family “never” holds money need the documented R5 qualification; that is not what the historical position readers universally promise after correction.

## N6 — executed: residuals and acceptance boundary

R1–R4 remain authorized divisions of responsibility: core ordering and customer-wide refund netting, per-jurisdiction pre-escheat policy, ended-payment targets, and the customer's one-pot display. They are not independent blockers.

R5 is an explicit section-9 design choice. The leaving-move check projects undos back; the readers and new-repayment check retain each row's money date. That distinction is visible in C4, and probe 09 tests a forward-dated continuation. I found no additional concrete date-boundary bypass beyond the documented interval from this source review; this is not an exhaustive proof over sequences. R5 does not justify money stranded on a newly born terminal carry in B1.

The author's stated strict apply/twice, battery, -23 regression, race, mutation and CI results were not reproduced. The permitted r2 author-run outputs resolve my original B1/S1 examples; the new B1 remains **predicted and awaiting author execution**. Resolve that history-load path and address the test omissions before acceptance.
