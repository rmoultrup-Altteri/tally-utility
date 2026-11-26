# Codex — v5.4.2-25, round 5

**Verdict: not yet.** Two predicted blockers remain: the combined record can omit the law's binding-final flag, and the must-pay ordering mishandles withholding fractions above one. The specific round-4 subject, mixed-deadline, lost-stage and incomparable-scalar examples have source fixes; reverse reading-move coverage is now present.

This is a whole-patch **source-only** review. **Executed** means filesystem/source inspection, never database execution. All database outcomes below are **predicted**, with runnable SQL in [codex-r5-probes](codex-r5-probes/). I ran no Docker, psql, CI, race, mutation, migration or terms runner. I read neither `opus-*.md` nor `fable-*.md`. Author transcripts are historical evidence, not my execution or fresh-r5 verification.

## B1 — predicted: the law's final flag is copied only when another stage difference triggers merging

**Evidence:** [patch comparator](patch-25-frozen-r5.sql:1865), [combination dispatch](patch-25-frozen-r5.sql:2726), [final assignment](patch-25-frozen-r5.sql:2777); r5 plan “As built,” item 1 and application contract.

The comparator accepts a tariff whose first two stages match the law's deciders and have equal or stronger deadlines, followed by an extra governing-body appeal. It deliberately ignores `final`. Because L2d allows a document's final flag only on its last stage, that valid tariff marks its regulator `final:false`, whereas the law marks the regulator `final:true`.

`dispute_terms_combined` enters the stage merge only if `dispute_tariff_compare_sections` returns a `stages` finding. With these otherwise compliant stages it returns none, so the assignment that copies the law's final flag is never reached. The combined record retains `final:false` at the regulator. Tightening an unrelated section, such as blocks, does not fix this. Tightening the regulator's decision deadline does: that happens to activate the stage merge.

The core contract says to use the combined stages, and the plan explicitly says that the law's final decision remains binding regardless of a subsequent tariff appeal. The combined data must carry that fact consistently. This is not an objection to admitting the trailing appeal; that settled allowance should remain.

**Probe:** the new B1 block in [00-contract-battery.sql](codex-r5-probes/00-contract-battery.sql) writes the valid three-stage tariff, closes the old law, inserts the successor law, writes a determination and enters the added appeal. Three independent subtransactions compare:

| Successor law | Predicted combined regulator flag | Required |
|---|---|---|
| Same stage terms, no overrides | false | true |
| Only an additional block | false | true |
| Regulator decision tightened from 15 to 10 days | true | true |

Each case prints its result and rolls back. These use `st3`, `tight2_sql` and `det2_sql` from the frozen r5 battery, preserving its real insertion/citation path.

**Fix:** synthesize the law's stage-final metadata even when stage deadlines and placement need no correction. Keep the tariff appeal and its identifiers. Add regressions for no stage finding and an unrelated-section finding; D9a currently checks `final` only while also tightening the regulator, and M167 tests removal of that reached assignment. Neither detects this skipped branch.

## B2 — predicted: `undisputed_charges` is not always more protective than `withhold_cap`

**Evidence:** [must-pay ordering](patch-25-frozen-r5.sql:1944), design sections L2/L6, the supported governmental fixture's fraction `1.1`, and battery X8/N7d/N7e.

The first must-pay branch treats a tariff asking for `undisputed_charges` as no looser than **any** law strategy. The reverse branch calls any other tariff strategy `looser` when the law asks for undisputed charges. That is incorrect for a withholding fraction greater than one, which both schemas support and the test suite expressly exercises.

Under the design's definition, a customer may withhold up to `fraction × disputed amount`. For a $100 bill with $40 disputed, undisputed charges are $60; a 1.1 withholding cap permits withholding $44, leaving $56 to pay. Thus:

- Tariff `undisputed_charges`, law `withhold_cap(1.1)`: the comparator is predicted to report no must-pay defect and the combination to keep the tariff's less protective payment term.
- Tariff `withhold_cap(1.1)`, law `undisputed_charges`: it is predicted to report `looser` and replace the tariff's stronger promise with the law's $60 term.
- A fraction of exactly 1 is equivalent on this comparison, yet the second direction is still classified `looser`.

This assumption predates r5 and is also written in the design's ordering paragraph. It conflicts with that same design's explicit fraction semantics and 1.1 example. Correct the assumption and its documentation together. This review does not reinterpret the statute or request implementation of the deferred governmental customer class. The problem is already in the implemented general strategy comparator and combined document.

**Probes:** [11-withholding-and-subjects.sql](codex-r5-probes/11-withholding-and-subjects.sql) validates both documents, checks both directions at fractions 0.9, 1 and 1.1, and prints structured verdicts and combined must-pay terms. The B2 supplement in [00](codex-r5-probes/00-contract-battery.sql) runs as `tally_app` against the existing X8 special-district fixture: an undisputed-charges tariff is predicted to be admitted, an equivalent cap of 1 to be refused for `must_pay`, and cap 1.1 to be admitted. Each insert is undone independently.

**Fix:** compare undisputed charges to withholding caps using the fraction, preserving the more protective term in either direction. If the intended payment semantics include additional conditions that defeat a universal order, classify the pair as not comparable and retain both under Ryan's ruling. Do not narrow away the supported 1.1 fixture to hide the ordering defect. Add insertion and later-law combination tests in both directions.

## S1 — predicted: list-section verdicts overstate dominance

**Evidence:** patch `:1803–1806` defines `looser` as the law protecting more for every customer; subjects at `:1888–1895` and stages at `:1877–1884` do not establish that proposition.

The crossed-subject example from round 4 still emits `subjects / looser`: law admits calculation plus meter accuracy; tariff admits deposit plus meter accuracy. The law does not protect a deposit disputant more. Likewise, the mixed-stage example has a stronger tariff employee deadline and a stronger law regulator deadline, yet emits `stages / looser`. Missing law codes in blocks/duties can also coexist with additional tariff codes.

The **current merge handles these list sections specially**, so this is not a second instance of the old wholesale-replacement defect. Nevertheless the new structured result does not meet its stated universal-dominance contract. Qualify the API contract as a missing-law-requirement finding for lists, or represent crossed/incomparable lists accurately while retaining their dedicated merge. Do not let another consumer infer wholesale dominance from this verdict.

**Probes:** [09-combination.sql](codex-r5-probes/09-combination.sql) now prints structured findings as well as combined sections; [11](codex-r5-probes/11-withholding-and-subjects.sql) adds all four subject-kind orientations. Expected unions are protective even where the verdict is too strong.

## N1 — executed: freeze, scope and static checks

All ten frozen MD5s and the brief's own MD5 matched **before source review**:

| File | Expected = observed MD5 |
|---|---|
| review-brief-25-r5.md | 3bef277f07de4af2432f970791f81491 |
| patch-25-frozen-r5.sql | 138f6770f5bf2205a98ff28a3940f68b |
| battery-25-frozen-r5.sql | 20b101e9a8deaeacde48f8b352639e34 |
| disputes-25-frozen-r5.sh | a5ad8111c4506c1b27c8565ba513ad49 |
| mutations-25-frozen-r5.py | 5e4713574105fa5900af1201e9d13bad |
| terms-25-frozen-r5.py | 83d1484349ef8c3ad654eb40f2264eb6 |
| migration-25-frozen-r5.py | 55d80759b4066f5a037acc3bd104be20 |
| fill-manifest-25-frozen-r5.py | 33802a5b696602534f9b1b521981fc5d |
| dispute_platform_defaults-frozen-r5.yaml | deb668299bc3bd44d1eb72a1aeb117d4 |
| dispute_platform_defaults-frozen-r5.seed.sql | 3832a44f5ae4c788a8451479390906ec |
| r4-to-r5.diff | f27103988ea36cbd005e540f3b67930f |

Reviewed the whole patch and frozen harness sources, my round-4 review and every round-4 probe with its author output, the entire r5 plan including As built, design, inventory D/Q1, relevant DECISION-LOG entries and the supplied GBM November 5 rulings. Ryan's November 26 keep-both ruling supersedes my round-4 request to refuse incomparable combined scalar terms.

All **32 function-body MD5 pins** match the corresponding frozen function bodies. Both committed schema texts and the frozen default seed are embedded verbatim. All four frozen Python files parse as ASTs; none was imported or executed. These checks establish source consistency, not successful strict application or runtime behavior.

## N2 — executed source disposition; predicted runtime: round-4 findings and every prior probe

| Prior finding/probe | Round-5 disposition and fresh probe |
|---|---|
| B1, crossed subjects | Source fix: union of admitted subjects, including any/listed exclusions. Reissued 09; new 11 checks all four kind pairings. |
| B1, mixed stage deadlines and lost trailing stage | Source fix: independently wider filing/quicker decision, retained tariff-only stages. 00 retains the old real-row case; 09 retains the helper case; D9a/b cover the new implementation. The broader binding-final promise remains half-done as B1 above. |
| B1, incomparable scalar replacement | Superseded by Ryan's keep-both ruling, implemented as `either`. Reissued 09 predicts both alternatives, not refusal. 00 includes D9e–h component/end acceptance and refusal controls. B2 is a separate ordering hole. |
| S1, reverse reading move | Fixed in test source: DR16 is close-first; DR17 adds note-update then amount. Reissued 10-A/B and new 12-A/B provide independent scheduled probes. |
| 00, full battery/supplements | Rebuilt from frozen r5 with caught-error notices. Retains successful governing-law tariff citation, dependent line-after-close CTE, and old B1 real-row stage case; adds both new blockers. |
| 01, cross-table UUID reuse | Sequence guard remains; equal-ID and distinct-ID amount/determination cases are predicted to refuse with D2e/D4k. |
| 02-A/B, two closes of one reading | Reading serialization and post-lock sibling read remain. Predicted second release refusal 23514/T2c. |
| 03, stage comparison | Slow decision and shorter filing window still predicted to produce findings; equal terms remain a control. |
| 04, owner COPY | Withdrawal followed by escalation predicted to refuse 23514/D5f. Prints COPY's own verbose error. |
| 05, roles/isolation/history | Direct app/core status writes predicted 42501; empty identity close predicted 22P02; owner replica-mode close with identity predicted success; explicit repeatable read, serializable and read uncommitted predicted 25000 at the dispute mutex. |
| 06, catalog invariants | Reissued against r5: registration, privileges, FKs and patch-tail invariants. Source pins are consistent; database checks await author execution. |
| 07-A/B, FK lock upgrade | `FOR NO KEY UPDATE` remains. Predicted two successful release checks, without the former key-share upgrade deadlock. |
| 08, stage boundaries | Equal/wider filing controls, short/different-anchor windows, unlimited decisions and repeated deciders retained. |
| 09, combination | Predicted corrected union/mixed-deadline/keep-both results. Structured verdict output also exposes S1. |
| 10-A/B, close-first inversion | Predicted one 40P01, survivor completes after rollback; now represented in frozen DR16 too. |

The author's r4 logs support the historical sequence: 09 and the live 00 case exposed lost protections; 10 produced a deadlock; 07 released successfully. They do not prove that these fresh-r5 probes pass. No earlier FK-upgrade or hidden-tariff-fixture defect was found reintroduced in source.

## N3 — executed source assessment; predicted behavior in 00, 09 and 11: merges and `either`

Subject union branches are set-correct for valid documents: two `any` sections intersect exclusions; one `any` removes exclusions admitted by the listed side; two lists union admitted codes. Skipping the merge when the tariff already contains the law's admitted set retains that union. L2a separately rejects listing and excluding the same subject. Vocabulary-dependent recomputation remains explicitly documented.

When stage merging is reached, positional same-decider matching preserves tariff IDs, takes the wider filing window and quicker decision, and appends unmatched tariff stages in order. Different-anchor filing windows retain both. A conflicting law ID receives `law:`; valid input IDs cannot already contain that colon, and each input's IDs are unique. D9b3 and D9i in 00 cover changed deciders/collisions and real stage-event lookup. The event guard uses the common combined helper and checks ID, decider category and user presence; it does not enforce stage progression or calculate filing windows. B1 concerns when the merge is skipped.

For valid combined must-pay alternatives, D4g accepts an ID belonging to either component and refuses an unrelated ID. Colliding law IDs are renamed. It checks component membership, not the arithmetic amount: that remains the core's job. For end alternatives, D4t retains a successful match across the loop: resolution/regulator-close accepts no last day, while a counted end accepts a nonnull day at or before the inclusive limit with a known anchor. D4o independently forbids a date before receipt. D9f/g/h and their negative controls in 00 cover these branches. I found no valid-row route that fits neither represented end but passes this new loop.

The loop's fallback accepts an unruled end, but the law's unruled section does not create an incomparable alternative, and tariff schemas forbid unruled. Arbitrary hand-crafted helper JSON is not a stored-valid-document bypass. The shelter readers use recorded figures/end dates; they do not parse `must_pay` or `shelter_ends` as scalar strategy objects. The core must implement the documented alternatives, including stage filing alternatives; a database probe cannot certify that external evaluator.

## N4 — executed source assessment; predicted runtime in 00–08, 10 and 12: guards, roles and concurrency

The whole-patch paths retain immutable identities, tenant/coordinate checks, issued-bill/date checks, amount and line caps, same-transaction line completion, a single live determination chain, correction links, outcome shapes and append-only records. The AFTER close guards cover amounts, lines, determinations and events; lines resolve the parent dispute. Assigned record sequences override supplied values. Probes 00/01/04 cover multi-row INSERT, writable CTE, UUID reuse and COPY rather than relying on single-row inserts alone.

App writes remain invoker-guarded and tenant-isolated; core is a reader; the status move is the narrowly granted `tally_dispute` definer. Owner history loads need tenant identity for that move. ALWAYS guards still run in replica mode, but ordinary FKs do not thereby become ALWAYS: H17 is a targeted invoice tenant check, not proof that every malformed superuser history load is impossible. Probes 00/05/06 preserve that distinction.

Dispute writers acquire the advisory mutex before checking open status. Lines rely on the parent's same-transaction insert retaining it. Determinations take citation locks before consuming governing terms. The deferred reading-release check uses `FOR NO KEY UPDATE`, then a separate sibling-status query. The r5 header correctly generalizes the reverse order to **any reading-row write followed by a dispute lock**, including a notes edit. 10 and 12 probe the resulting deadlock; 02 and 07 probe the distinct visibility and FK-lock controls. I found no additional concrete lock bypass beyond these documented transaction-order cases. This is not a proof that arbitrary transactions touching multiple disputes/readings cannot deadlock.

One stale comment remains at patch `:3699`: the release function's catalog comment still says “Two deadlocks remain” and describes the reading's own move, while the header now states the broader rule. Update that comment to match the rule and DR17. Its runtime witness is 12-A/B; the documentation mismatch itself is an executed source finding.

The no-tariff lookup remains an unlocked absence read under the explicit R6 boundary. DR11 is sequential, not a concurrency proof. The frozen default citation race still lacks a close-first companion; I do not infer a new integrity defect from that missing test alone. Readers retain both temporal coordinates, recorded supersession, close-date termination, inclusive last-day treatment and cumulative allocation rounding (00's reader checks).

## N5 — executed source comparison; preservation predicted in 00/06: template, seal and invariants

No -17 template function is replaced. The default remains a separate registered law-role table, with explicit delegation/tariff/default citation alternatives. Its two municipal class rows, date and blocks follow the November 22 ruling.

Compared the latest base definitions in `sql/tu.sql` with the carried bodies: `assert_seal_role_invariants` adds the dispute move owner, exact grants and role-loop entry; `enforce_reading_validation_workflow` removes the six obsolete dispute fields and updates the hint. Existing consumed-reading/void restrictions are retained in source.

The dispute invariant pins trigger definitions and ALWAYS state, validated constraints, valid unique indexes, function bodies/attributes/ACLs, NOT NULLs, table ACL/RLS/owner, sequence settings, column grants and exact policies. The new structured comparator is pinned. These are catalog-drift checks, not semantic proofs; a correct hash of B1/B2's implementation cannot detect those defects. The accepted unlisted-trigger limitation and lack of historical sequence audit remain. 00's H controls and 06 provide author-run checks.

## N6 — executed: test strength and reported results

The frozen battery now contains the missing round-4 within-section and keep-both cases. DR16 genuinely reverses the move/close schedule; DR17 broadens it. The mutation runner requires the first failure to name the expected check and distinguishes expected apply failures; source inspection found no specific listed mutation demonstrably credited to an unrelated failure. I did not reproduce or certify the author's 178/178 result.

The material omissions are B1's no-stage-finding branch and B2's cross-strategy fraction boundaries. M167 reaches the final-copy line, so it does not test whether the line is always reached when needed. N7d/e test cap against cap, not undisputed charges against cap. Add independent mutants for these cases, not merely another mutation that removes the entire merge.

Other labels retain their limits: battery S2 checks schema IDs/hash format, not committed-file equality; migration P1 compares selected counts, not complete catalog identity; DR11 is sequential. The frozen Python copies resolve repository roots relative to their original locations, so they are review snapshots rather than scripts to launch directly from `review/`. The reported DR2 polling miss and initial -24 CI failure are author-reported; I observed no runtime flake because I ran no races or CI.

## N7 — executed scope assessment; predicted boundaries covered by 00/05/06/09/11: residuals R1–R9

None of the declared residuals independently blocks this scoped patch. Neither new blocker is excused by them.

- **R1:** no governmental class; its shape remains test-only. B2 concerns a supported strategy and valid tariff/law shapes, not adding that class.
- **R2:** conditional-law shapes remain explicitly excluded.
- **R3:** eligibility, classification, figures and due-process evaluation belong to the core. Supplying it a weaker combined document is still a database-layer defect.
- **R4:** decider category is checked; the person's authority is external.
- **R5:** a reading-only dispute lacks an issue-date bill anchor. Immutable identity does not permit attaching a bill later by update.
- **R6:** a later backdated policy creates an audit obligation, not serialized absence.
- **R7:** owner history loads require identity for the RLS-bound status move.
- **R8:** due-date eligibility, no-amount whole-bill fallback, and next-regular-bill due-date workflow remain core integration obligations under the rulings.
- **R9:** incompatible stage lists across classes can prevent one tariff satisfying both; the plan records this policy-model limitation. It does not excuse failing to retain the final flag for one otherwise compatible law/tariff pair.

## Probe handoff — predicted, not executed

There are **17 SQL files** in [codex-r5-probes](codex-r5-probes/). Run independent files or each scheduled A/B pair as owner on a fresh throwaway clone with frozen r5 applied. Every file ends in `ROLLBACK`; no probe creates, drops or alters roles. A files commit shared fixtures for their partner sessions; 02-A also commits its first close to test post-wait visibility. Dispose of those scratch clones afterward. Caught errors print SQLSTATE and message with `RAISE NOTICE`; 04 prints COPY's own `\errverbose` error and does not rely on `LAST_ERROR_SQLSTATE`.

Before ready: fix B1 and B2, add their independent regression controls, and have the author execute the probes. S1's verdict contract should also be corrected. The settled default and keep-both decisions need no reopening.
