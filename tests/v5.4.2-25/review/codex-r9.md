# v5.4.2-25 — Codex round 9

**Verdict: ready.** R10 resolves round-8 S1. No blocking or should-fix item remains in this diff-only review. This is source signoff, not an independent database run or verification of the external core.

## B — executed source assessment: none

## S — executed source assessment: none

## N1 — executed source assessment; predicted database witnesses: R10 is accurate within its stated core contract

Reviewed the [37-line diff](r8-to-r9.diff), the r9 plan, the r8 plan's “Round 8 reviewed” section, my r8 review and probe sources/author transcripts, and the unchanged source needed to assess this paragraph.

At [patch lines 175–189](patch-25-frozen-r9.sql:175), R10 now distinguishes the earlier-stage case from the last-stage case correctly:

- At matching law/policy positions, the merge explicitly takes the law's `final` value in either Boolean direction. At a position with a different decider or no policy stage, it emits the law stage itself. Thus “at each of the law's places” is accurate, including positions where no policy flag actually needs replacing.
- Before the law's last stage, the loop continues through every later law position in order. A policy's shorter stage list cannot truncate that loop. The seeded employee/regulator example is now an illustration of this case, rather than incorrectly excluded by the seed assurance.
- “The customer keeps every appeal the law gives” also holds when a policy stage displaces a law stage: a matched position has the same decider, a filing window at least as wide (or both anchors retained), the quicker decision deadline, and the law's final flag. The policy's ID may replace the law's ID; the wording promises the appeal, not byte-identical stage objects. An unmatched position retains the law stage, with an ID prefix if needed, and the unused policy stage is appended afterward. No law appeal position is omitted.
- At a hypothetical nonfinal last law stage, the policy's finality can be removed without any later law appeal supplied. The wording properly leaves the protection judgment customer-dependent and keeps this case subject to escalation. It does not claim the helper preserves both finality alternatives.
- Direction (b) remains accurate: the second loop retains unused policy stages after the law positions, including a policy appeal following a law-final stage. “Both rest on” continues to state the core contract: final binds the utility and must not terminate an appeal retained in the combined record. This review does not establish implementation of that contract in the external core.

Evidence: the unchanged [stage merge](patch-25-frozen-r9.sql:2807) and [function contract](patch-25-frozen-r9.sql:2725). The r7 plan's “Notes taken” records the nonfinal-last-stage escalation already carried by R10; r9 does not introduce a new ruling.

Database predictions are supplied in [01-finality-scope.sql](codex-r9-probes/01-finality-scope.sql), [02-seeded-finality.sql](codex-r9-probes/02-seeded-finality.sql), and [03-appeal-preservation.sql](codex-r9-probes/03-appeal-preservation.sql). Probe 01 reissues the earlier-finality and surviving-policy-appeal cases; 02 reissues the actual seeded employee-stage witness; 03 checks the seed endpoints, a law appeal represented by a policy stage with weaker timing, the different-decider branch, and a hypothetical nonfinal last law stage. **All r9 database results are predicted, not executed.** These are direct-helper witnesses, not claims that the hypothetical older policies could be newly filed under the effective law.

## N2 — executed source assessment; predicted seed verification: round-8 S1 is closed

The [four embedded law seed documents](patch-25-frozen-r9.sql:2044) support the revised sentence, “No seeded law row has a last stage that is not final.” The protected IOU/cooperative document ends in a final regulator stage after a nonfinal employee stage. The unprotected document has an empty stage list; the two municipal documents delegate and have no stage list. Those three have no last stage and are not counterexamples. This is a statement about the supplied seeds, not every possible future law document or an assertion that affected historical policies exist.

Probe 03 supplies the corresponding database check; probe 02 preserves the earlier-stage counterexample to the old wording. The r8 author transcripts report successful execution of the prior witnesses, consistent with the source; they are not r9 execution by this reviewer.

My r8 S1 was the only remaining requested correction. It is closed. The other r8 items were notes or closed findings; the unchanged comparator/release wording and D9t4 assertion are not reopened. No broader implementation review is implied.

## N3 — executed filesystem checks: all frozen hashes and the scope match

Checked the brief's checksum and all ten frozen MD5s before proceeding. All eleven matched:

| Input | MD5 |
|---|---|
| brief | `3f25c3cbfda07cc56d4127f6e6e08b04` |
| patch | `9dae050be1a905d5263d9293d8c83976` |
| battery | `772c6a71dc7fef67220e318a87032cef` |
| disputes | `ba77a03997a856bd00d90d3c0e7fcb88` |
| mutations | `68ee1252a020b63f67c522e05c120eeb` |
| terms | `83d1484349ef8c3ad654eb40f2264eb6` |
| migration | `55d80759b4066f5a037acc3bd104be20` |
| fill-manifest | `33802a5b696602534f9b1b521981fc5d` |
| defaults YAML | `deb668299bc3bd44d1eb72a1aeb117d4` |
| defaults seed | `3832a44f5ae4c788a8451479390906ec` |
| r8-to-r9 diff | `612c0f9ed6094a015956d19af8b7731c` |

Independently regenerated the frozen r8/r9 patch diff and matched its complete hunks. Its sole hunk changes R10's header comment. Removing standalone SQL line comments leaves identical source. All eight other frozen artifacts are byte-identical to r8. Nothing outside that comment changed in these frozen inputs, including function bodies, object comments and tests.

## N4 — executed probe inspection; predicted execution handoff

Run each of the three r9 probes as owner on its own fresh clone with frozen r9 applied. Each opens a transaction and ends in `ROLLBACK`, contains no role DDL, and prints SQLSTATE and message through `RAISE NOTICE` for caught errors. Inspect FAIL/error notices; catching an error can leave the client exit status successful. No COPY probe is needed for this comment-only diff.

No Docker, psql, CI, race, mutation runner or database command was executed. Author-reported suite totals were not independently reproduced. No `opus-*.md` or `fable-*.md` was read. Only this review and `codex-r9-probes/` were written.
