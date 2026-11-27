# v5.4.2-25 — Codex round 8

**Verdict: not yet.** One sentence in R10 still needs qualification before the wording is frozen. No new behavioral blocker was found. This verdict concerns the requested wording signoff; it does not reverse round 7's assessment of the implementation.

## B — executed source assessment: none

Reviewed only the two deltas and the source context needed to assess them, the complete r8 plan, the r7 plan's “Round 7 reviewed” section, my r7 review and the relevant finality probe/transcript. No other reviewer's files were read. No database commands, Docker, CI, races, mutation runner or manifest filler were executed. All database predictions below have r8 probe files; author-reported test totals are not independently reproduced here.

## S1 — executed wording finding; predicted database witness: R10's seed assurance remains too broad

At [patch lines 185–188](patch-25-frozen-r8.sql:185), the new conclusion says:

> No seeded law row has a stage that is not final where a policy's could be

That does not follow from the seed or the newly expanded scenario (a). The frozen patch's protected-law seed at line 2042 has a nonfinal `designated_employee` first stage and a final `regulator` second stage. A hypothetical shorter older policy can end finally at that first position. It is precisely the older-policy/longer-later-law shape that R10 now correctly includes. A final last law stage does not exclude it.

[02-seeded-finality.sql](codex-r8-probes/02-seeded-finality.sql) uses the actual seeded law unchanged and a schema-checked, one-stage tariff document derived from it, ending finally at the designated employee. Predicted: the helper replaces that flag with false and supplies the regulator stage. This is a combination witness, **not** a claim that this shorter policy passes new filing against the already-effective seeded law, nor evidence that an affected historical policy actually exists. The seed alone cannot establish the quoted exclusion across the historical-policy scenario.

Suggested replacement for the final two sentences:

> No seeded law row has a nonfinal last stage. That excludes the last-stage example for the current seeds, not the shorter-older-policy example above. Any such finality conflict comes back to Ryan under his 2026-11-26 ruling.

This preserves the known seed fact without treating it as proof that all policy-final/law-nonfinal conflicts are absent. Alternatively, delete the seed assurance and state the escalation obligation directly. My round-7 S1 is substantially addressed, but its seed qualification is still open in this sentence.

## N1 — executed source assessment; predicted witnesses: the rest of R10 is accurate

The changed text correctly covers both unequal Boolean directions at a matching stage: policy-final/law-nonfinal and policy-nonfinal/law-final. The unchanged merge at lines 2805–2833 takes the law's flag at matched positions and appends unused policy stages. Nonmatching positions use the law stage and retain the displaced policy stage afterward. Equal flags introduce no third flag-change direction. I found no additional flag direction requiring another residual in this diff.

[01-finality-scope.sql](codex-r8-probes/01-finality-scope.sql) reissues the two schema-valid round-7 cases against r8: earlier policy finality replaced, and a final law stage followed by the retained policy appeal. Its r7 author transcript matched those predictions; r8 execution remains pending. Preservation of appeal rights still depends on the stated core contract: final binds the utility and does not terminate an appeal the combined record retains. This source review does not establish that an external core implements that contract.

## N2 — executed source assessment: comparator and release comments agree with their source

The comparator's “no start is wider than it” now expresses `any_time` as maximal, consistent with its existing branch and documented regulator-complaint premise. Naming `undisputed_charges` and withholding of at least one removes the ambiguous “either”; the corresponding average-cap comparison branch returns `looser`. These are comment corrections, not new ordering rules or new legal conclusions.

The release comment at line 3746 now matches the header at lines 126–134: it includes any reading-row write followed by a dispute lock, including a clerk's note, and retains the opposite-order multiple-dispute/multiple-reading qualifications and retry instruction. This is a textual consistency finding; no new concurrency experiment or runtime claim is offered.

## N3 — executed test inspection; predicted execution: D9t4 is the right exact assertion

The battery's `avg('m1')` builds the policy average cap; `wcap(0.9,'m2')` builds the law term, including its citation. The combination branch at patch lines 2776–2783 constructs `[tariff term, law term]`; these different IDs do not enter the collision-renaming branch. The proposed expected array therefore matches the source, including order and complete objects.

[03-d9t4.sql](codex-r8-probes/03-d9t4.sql) uses the exact frozen battery constructors and checks the ordered combined alternatives. It also checks that the new predicate rejects either single remaining term, reversed terms, a duplicate policy term and SQL NULL. All are predicted, not executed. `IS NOT DISTINCT FROM` addresses missing-value acceptance as well as replacing the old length-only check.

Round-7 N7's D9t4 gap is closed by the source change. D9u remains a synthetic direct-helper test by explicit r8 plan decision; that acknowledged limitation is not a new blocker. Probe 01 retains schema-valid finality supplements.

## N4 — executed filesystem checks: scope and frozen inputs verified

The eleven frozen MD5s were checked first, together with the brief's own checksum. All twelve matched:

| Input | MD5 |
|---|---|
| patch | 8f430bce8324b17d0a96b86bd29da94a |
| battery | 772c6a71dc7fef67220e318a87032cef |
| disputes | ba77a03997a856bd00d90d3c0e7fcb88 |
| mutations | 68ee1252a020b63f67c522e05c120eeb |
| terms | 83d1484349ef8c3ad654eb40f2264eb6 |
| migration | 55d80759b4066f5a037acc3bd104be20 |
| fill-manifest | 33802a5b696602534f9b1b521981fc5d |
| defaults YAML | deb668299bc3bd44d1eb72a1aeb117d4 |
| defaults seed | 3832a44f5ae4c788a8451479390906ec |
| patch diff | 4b4514ef1ba4830ddf4b5687d18911ef |
| battery diff | d014313ed8462aaf8b318e1fc0268726 |
| brief | 04247fcb818429a371a417a201847a8c |

Independently regenerated both diffs from frozen r7/r8 files and matched their complete hunks. All **34 function bodies** are byte-identical, including both invariant functions and their manifest lists. Independently recomputed all **32 pinned body MD5s** from source; all match. The seven other frozen artifacts are byte-identical to r7. Nothing outside comments and the D9t4 label/assertion changed in these frozen inputs.

## N5 — executed probe hygiene; predicted execution handoff

Three focused SQL probes are in [codex-r8-probes](codex-r8-probes/). Run each as owner on its own fresh clone with frozen r8 applied. Each starts a transaction and ends in `ROLLBACK`; none creates, drops or alters roles. Every caught error prints SQLSTATE and message through `RAISE NOTICE`. No COPY probe is needed for this diff. Inspect notices for unexpected errors: caught failures may leave the client exit status successful.

Only this review and these three probes were written. No broad round-7 battery or race reissue is required for this diff-only review.
