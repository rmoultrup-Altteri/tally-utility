# v5.4.2-25 — Codex review round 6

**Verdict: ready.** Source review finds the two round-5 blockers fixed and no new blocking defect. Two nonblocking should-fix items remain below. This is not a certification of database execution: every runtime conclusion is **predicted**, with fresh-r6 probes for the author. No Docker, psql, CI, races or mutation runner was executed.

## B — executed source assessment

**No open blocking item identified.** Round-5 B1's skipped stage merge and B2's withholding comparison are corrected in source. Round-5 S1's structured verdict is corrected. B2's requested documentation correction and N4's stale catalog comment remain half-done (S1 below).

## S1 — executed: reconcile the design and catalog prose with the implemented contract

[Design L6](../../../../application/wave3-build-2026-10-18/v5.4.2-25-design.md) still says `undisputed_charges` asks no more than **any** other strategy. Its start-order bullet also puts `within_days` below `before_delinquency` without the anchor qualification. These are not the r6 ordering. The relevant lines are 66–68.

The comparator catalog comment at [patch line 1997](patch-25-frozen-r6.sql:1997) retains the old unconditional undisputed-charges sentence and appends the correct r6 exception. Rewrite the original sentence so readers need not resolve the contradiction. The structured comparator comment at line 2011 also describes “another strategy against a law of undisputed_charges” as looser without restricting it to the remaining cases after the withholding comparison.

The release function's comment at [line 3723](patch-25-frozen-r6.sql:3723) still says “Two deadlocks remain” and describes only the reading's own move and opposite reading order. The header correctly includes any reading-row write followed by a dispute mutex, and opposite acquisition of two dispute mutexes. Update the catalog comment to match it. Round-5 N4 therefore remains open as documentation, even though the operational header is improved again.

These inconsistencies do not change the source behavior. Predicted witnesses are [00](codex-r6-probes/00-contract-battery.sql), [11](codex-r6-probes/11-withholding-and-subjects.sql), [13](codex-r6-probes/13-r6-matrices.sql) and [12-A](codex-r6-probes/12-a-note-then-amount.sql)/[12-B](codex-r6-probes/12-b-note-then-amount.sql). No new policy ruling is needed.

## S2 — executed source finding; predicted witness: some merge assertions accept NULL

D9j's embedded DO block uses `IF NOT (conjunction) THEN RAISE`. If one selected JSON field is absent while the other predicates hold, the conjunction is NULL and the exception is skipped. D8j and D9a use the same assertion style. The shared `pg_temp.ok` correctly uses `IS DISTINCT FROM true`, but these DO blocks bypass it.

The additional S2 block in [00](codex-r6-probes/00-contract-battery.sql) takes the actual combined stages, removes only the regulator's `final` from a **local JSON value**, and applies D9j's exact predicate. Predicted output: NULL predicate, `rejected=false`, `strict_rejected=true`. It does not alter a function or run a mutation runner.

Use `IF (predicate) IS DISTINCT FROM true` and compare the complete expected stages, or their complete non-final projections plus the final flags. D9j's label promises that the rest remains as the policy has it, but checks only selected fields. A missing decision/file property could evade that promise too. Current source explicitly writes `final`, and M173 tests the actual skipped-merge regression with a false flag, so this is a test-strength issue, not evidence the r6 implementation loses that flag. Body pins also detect unrefilled body changes; they do not replace semantic assertions.

## N1 — executed: freeze, scope and static verification

All ten frozen hashes and the brief's own checksum matched **before source review**:

| File | Expected = observed MD5 |
|---|---|
| review-brief-25-r6.md | e2d650ec169f03f45707b17e6da32499 |
| patch-25-frozen-r6.sql | 2e98f5d5789c534924e154f456908aa8 |
| battery-25-frozen-r6.sql | a5204e30bc67641effaef4c7c96e2108 |
| disputes-25-frozen-r6.sh | ba77a03997a856bd00d90d3c0e7fcb88 |
| mutations-25-frozen-r6.py | 77d92d300ddaf8c553d7b2e67e9cbedc |
| terms-25-frozen-r6.py | 83d1484349ef8c3ad654eb40f2264eb6 |
| migration-25-frozen-r6.py | 55d80759b4066f5a037acc3bd104be20 |
| fill-manifest-25-frozen-r6.py | 33802a5b696602534f9b1b521981fc5d |
| dispute_platform_defaults-frozen-r6.yaml | deb668299bc3bd44d1eb72a1aeb117d4 |
| dispute_platform_defaults-frozen-r6.seed.sql | 3832a44f5ae4c788a8451479390906ec |
| r5-to-r6.diff | 7d40f73f7c1893ea5b3fe0740879f20d |

Reviewed the whole frozen patch and harness sources, the entire r6 plan including As built, my round-5 review and probes with the author's results, the design, inventory D/Q1, relevant DECISION-LOG rulings, and the GBM November 5 scenario rulings. No `opus-*.md` or `fable-*.md` was read. The November 22 platform default and November 26 keep-both ruling remain settled.

Independent source checks: all **32 function-body MD5 pins match**; both committed schema texts and the frozen default seed are embedded verbatim; all four frozen Python files parse as ASTs. No repository Python module was imported or executed. Compared the carried seal and reading-validation function bodies with their latest definitions in `sql/tu.sql`.

## N2 — executed source disposition; predicted runtime: round-5 closure

| Round-5 item | r6 disposition and author-run evidence |
|---|---|
| B1, final flag omitted without a stages finding | Fixed: merge is outside the findings loop. D9j/j2 cover no finding and unrelated block finding; M173 reinstates the conditional behavior. 00 reissues all three prior real-row cases and the trailing appeal control. |
| B2, undisputed versus withholding fraction | Fixed: compare as fraction 1 in both directions. D9k covers 0.9/1/1.1 both ways; k2–k6 exercise filing and later-law component checks; k7 retains the stronger tariff cap. 00 adds all six filing orientations; 11 and 13 validate input shapes and print combinations. Documentation remains S1. |
| S1, list verdict overstates dominance | Fixed: all four list sections return `lacks`. D9s covers all four; 09/11 show crossed sets and mixed deadlines with protective unions. |
| N4, overly narrow release comment | Header improved; catalog comment still stale (S1). 12-A/B retains the notes-update inversion witness. |
| Other notes and residuals | No source regression identified; limitations below remain explicit. |

The author's r5 results are historical evidence, not r6 execution: 00 reproduced the missing final flag without a stage finding, 11 reproduced the wrong withholding verdicts at 1 and 1.1, 09 showed correct unions but `looser` labels, and 10/12 reported the documented deadlocks. The changed r6 predictions are stated explicitly in the new probes.

## N3 — executed source analysis; predicted in 00, 08, 09, 11 and 13: combination and ranking

**Always-run stages.** With no stage finding, every law position already has the same decider, a tariff filing window at least as wide, and a tariff decision window at least as prompt. Each merge choice therefore retains those tariff windows. It preserves the tariff ID and other stage properties, copies the law's `final`, and appends unmatched tariff stages in original order. It does not invent a different-anchor alternative on this no-finding path, because differing finite anchors would already produce a finding. With no law stages, all tariff stages are appended unchanged. Whole-document byte identity is not promised: blocks and duties were already sorted/deduplicated unions.

The new 13 control uses valid documents with a law `final:false`, tariff `final:true`, a wider tariff filing window and a quicker tariff decision. It prints the combined false flag and equality of all non-final properties. Under the standing stage contract, finality records the law's binding endpoint; it is not a scalar monetary protection ranking. False preserves nonfinal recourse rather than shortening a deadline, removing an appeal or reducing shelter. I find no independent customer-protection regression from following that contract. This conclusion does not invent authority for the core to overturn a favorable decision; actual authority and resolution remain outside the stage metadata check. Valid inputs prohibit a final stage before the last, but do not require the last to be final.

When a finding exists, positional matching, independent wider/quicker windows, both finite anchors, collision-safe `law:` IDs and retained tariff-only stages remain intact. Input IDs cannot contain `:`, so a prefixed law ID cannot collide with a valid original ID. The common determination helper is also used by the stage-event guard. D9r now tests the displaced `law:s2` on the actual record path.

**Must-pay.** Let U be undisputed charges, W(f) a withholding cap and A an average cap. Against U, W is ordered by f versus 1; two W terms compare their fractions. Equal fractions have no finding and retain the tariff. Against A, U remains no more demanding under the implemented strategy contract; A versus U is looser. W versus A remains customer-dependent and `not_comparable`, both directions. Equal A parameters have no finding; unequal parameters retain both in a combination and are refused at filing. A tariff full bill is looser than a substantive protective law strategy; a law full bill or unruled imposes no additional restriction. An unruled tariff is not a valid stored tariff document; helper defensive branches do not make it admissible. 13 prints the valid six tariff variants against seven law variants, and 00/11 cover the targeted real paths and parameter differences.

A looser scalar takes the law's section. An incomparable scalar retains `either`, with a distinct prefixed law must-pay ID if necessary. Filing still refuses every finding through the text comparator. The database checks that a recorded component/end fits an alternative; it does not calculate which alternative is most protective for this customer. That division follows Ryan's ruling and requires a compatible core consumer.

**Starts and ends.** `any_time` is admitted against every start kind, including `on_regulator_complaint`; any narrower substantive start against law `any_time` is looser. Finite windows compare days only on the same anchor; unrelated starts remain incomparable. D9q/q2 and 13 exercise these directions. The end loop accepts only named kinds: resolution/regulator-close requires no last day; counted ends require a known anchor and a nonnull day at or before the inclusive limit; D4o separately prevents a date before receipt; unruled is explicitly named. Valid stored schemas and the combination's alternative construction cannot produce an unnamed end kind. Thus the new fail-closed fallback is defensive, not a newly rejected valid-document path. D9g4/g5 cover day 60/61; D9l covers resolution versus a counted end.

**`lacks` consumers.** The text wrapper returns all finding messages without filtering `looser`; filing therefore still refuses missing list requirements. The combination uses `not_comparable` only for scalar alternatives and dispatches list sections separately. Subject merges retain the union in all four any/listed orientations; blocks/duties are unions; stages run regardless of verdict. No in-repository consumer found treats `lacks` as success or wholesale dominance. D9s and 09/11 are the runtime probes; the external core is not certified by a database review.

## N4 — executed source analysis; predicted in 00–08, 10 and 12: guards and concurrency

The record paths retain immutable identity, tenant/customer coordinates, issued-bill/date restrictions, amount and positive-charge caps, same-transaction line completion, determination supersession checks, correction links, outcome shapes and append-only history. Both time coordinates remain required by the readers; recorded supersession, closing events, inclusive last-day handling and cumulative rounding remain represented by 00's reader controls. Retirement of `pending_dispute` and removal of the obsolete reading dispute columns remain deliberate T1/T2 changes.

The statement-level close protection still covers amounts, lines, determinations and events. Assigned sequence values replace caller values; no cross-table equal-UUID exemption remains. Multi-row INSERT, dependency-forced writable CTE, lines after close and COPY are represented by 00/01/04. This is stronger evidence than a single-row-only review, but no runtime result is claimed here.

App writes are tenant-isolated; core remains a reader; the status transition uses the narrowly granted `tally_dispute` definer. 05 predicts direct app/core status writes fail 42501, empty-identity owner close fails 22P02, and replica-mode owner close with identity succeeds. ALWAYS triggers cover history loads, but ordinary FKs do not thereby become ALWAYS: H17's explicit invoice coordinate check does not prove every malformed superuser history row impossible. Superuser ability to disable or replace enforcement is not an app-role bypass.

The dispute mutex rejects explicitly named isolation levels other than READ COMMITTED. Lines depend on their same-transaction parent retaining that mutex. Determinations lock cited law and tariff/default rows before consuming them. The deferred reading-release guard locks the reading with `FOR NO KEY UPDATE`, then performs a separate sibling-status query. The post-wait visibility and compatible FK key-share cases are separate probes (02 and 07).

There is no universal transaction lock order: reading-row write then dispute lock can invert close then reading lock; opposite multi-dispute acquisition can deadlock too. The header correctly requires retry of 40P01. 10 and 12 schedule two concrete inversions, and 14-A/B schedules opposite acquisition of two dispute mutexes, rather than asserting that the patch is deadlock-free. I found no new concrete read/check race beyond the documented boundary. The no-tariff absence lookup remains an unlocked absence read under R6, and DR11 remains sequential. The default citation race lacks a complementary close-first test; this is missing coverage, not demonstrated corruption.

## N5 — executed source comparison; predicted in 00/06: -17, -23 and invariants

No -17 template function is replaced. All three dispute rule tables use registration and the template checks. The separate default table and its delegation/tariff/default selection remain consistent with the November 22 ruling, including the two municipal class seeds and effective date.

The latest carried seal invariant differs from the base by the dispute status-move owner, its exact grants, and its role-loop entry. Existing seal/void/close restrictions remain. The carried reading-validation body removes the six obsolete dispute fields and updates its hint; its consumed-reading and void restrictions remain. This is a source comparison, with runtime catalog checks in 06 and battery H controls in 00.

The dispute invariant checks required exact trigger definitions/ALWAYS state, validated constraints, valid unique indexes, body hashes, function attributes/owners/ACLs, NOT NULLs, table ACL/RLS/owners, sequence configuration, column grants and exact policies. It pins the new comparator. It does not reject every possible extra trigger or audit all historical sequence values, and a hash of a semantically wrong body cannot diagnose the semantic defect. These established limits do not contradict its useful catalog-drift protection. 00's H16/H18 alterations are rolled back and contain no role DDL.

## N6 — executed source assessment: tests and mutations

The new regressions address the prior functional omissions: no-stage-finding final synthesis, both withholding directions, looser scalar branches, finite/unlimited stage windows, alternate anchors, actual displaced stage IDs, and inclusive day boundaries. D9k checks all six fraction directions directly; filing has only three targeted directions in the frozen battery, so 00 adds the full six. The law-false no-finding control is additional coverage in 13. S2 qualifies the completeness claim for merge assertions.

M173 independently restores conditional stage merging; M174–M176 target the withholding assumptions; M177–M186 target end/start/merge branches; M187 checks the blocks `lacks` label. D9s covers four list labels, but the suite does not independently mutate each of the other three label assignments. M158's retarget from D9g3 to D9g is consistent with the now fail-closed unread `either` object: the mutant refuses a fitting record earlier. That is a relevant failure, not evidence of a valid document reaching an unknown-kind branch.

The runner suppresses the patch-tail dispute invariant for behavioral mutants and requires the first failure to name the expected check. A later H16 body-hash failure alone is not credited. Expected apply failures are checked separately by their named phrase. No concrete wrong-reason credited mutation was identified in source; this is not a reproduction of 193 results. The author's strict apply, 342 battery checks, race repeats, mutation results and CI totals remain author-reported.

Other labels retain their limits: S2 in the battery checks schema ID/hash format, not committed-file equality (independently checked statically here); migration P1 compares selected counts, not complete catalog identity; DR11 is sequential. DR2's longer hold/poll budget reduces timing pressure without proving all environments reliable. The frozen Python copies calculate roots relative to their original source locations and are review snapshots, not scripts to launch from this directory.

## N7 — executed scope assessment; predicted boundaries in 00/05/06/09/11/13: R1–R9

None independently blocks this scoped database patch:

- **R1:** governmental customer class remains absent and the 1.1 law shape test-only; the general fraction comparator is nevertheless corrected.
- **R2:** conditional-law shapes remain explicitly outside the supported schema.
- **R3:** classification, eligibility, calculated figures and due-process evaluation remain core responsibilities. Correct combined data is still required and has been reviewed here.
- **R4:** the database checks stage decider category/user presence; actual authority remains external.
- **R5:** a reading-only dispute has no bill issue-date anchor; immutable identity cannot attach a bill later by update.
- **R6:** later backdated tariff insertion creates an audit obligation, not serialized protection of absence.
- **R7:** history status moves require identity even for the owner because the transition runs with restricted RLS-bound rights.
- **R8:** due-day eligibility, no-amount whole-bill fallback and next-regular-bill due-date handling remain core integration obligations under the rulings.
- **R9:** incompatible class-specific stage prefixes can prevent one tariff satisfying both; the documented policy-model limitation remains.

## N8 — predicted, not executed: probe handoff and every prior probe

All 17 prior SQL files are reissued for frozen r6; 13 and 14-A/B are new, for **20 files** total. 00 is rebuilt from the frozen r6 battery, with SQLSTATE/message notices on its exception handlers, prior supplements and new controls.

| Probe | Prediction / purpose |
|---|---|
| 00 | Frozen battery plus B1 real-row controls, corrected B2 app filing, successful governing-law tariff citation, line-after-close CTE, six filing pairs and S2 NULL witness. |
| 01 | Same-ID and different-ID cross-table rows after close refused 23514/D2e or D4k. |
| 02-A/B | Serialized two closes: second release fails 23514/T2c after the first commits. |
| 03 | Equal stages pass; slower decision/shorter filing produces a finding. |
| 04 | COPY withdrawal then later event fails 23514/D5f; prints COPY's own verbose error. |
| 05 | App/core privilege, owner identity/replica-mode, and RR/serializable/read-uncommitted 25000 controls. |
| 06 | Registration, grants, FKs and patch-tail catalog invariants. |
| 07-A/B | FK key-share/release checks complete without the old lock-upgrade deadlock. |
| 08 | Stage equality, wider/narrower/different-anchor/unlimited boundaries and repeated deciders by position. |
| 09 | Crossed subjects, mixed deadlines, scalar alternatives, blocks/duties unions; list verdicts now `lacks`. |
| 10-A/B | Close-first reading inversion: one 40P01; other transaction can finish. |
| 11 | Six withholding comparisons/combinations, four subject-kind unions, core helper invocation. |
| 12-A/B | Reading notes update then amount versus close: one 40P01; survivor can finish. |
| 14-A/B | Opposite acquisition of two dispute mutexes: one 40P01; survivor can finish. |
| 13 | Validated pairwise must-pay matrix, `any_time` both ways against every substantive start, law-false/no-finding stage preservation. |

Run each independent file or scheduled A/B pair as owner on a fresh throwaway clone with frozen r6 applied. Schedules are at the top of each pair. A files commit shared fixtures; 02-A also commits its first close to expose the post-wait state. Every file ends in `ROLLBACK`; discard scratch clones afterward. No probe creates, drops or alters roles. Caught errors print SQLSTATE and message with `RAISE NOTICE`; 04 uses `\errverbose` and does not rely on `LAST_ERROR_SQLSTATE`. Observe the printed results: exploratory cases that catch unexpected errors are not automatic pass/fail tests.

Static checks of the handoff verified terminal ROLLBACKs, absence of role DDL, notices at catch sites and parseable case JSON. SQL and database execution remain for the author. Only this review and `codex-r6-probes/*.sql` were written.
