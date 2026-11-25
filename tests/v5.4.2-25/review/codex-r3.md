# Codex — v5.4.2-25, round 3

**Verdict: not yet.** The round-2 data-integrity blockers have source-level fixes. Two should-fix items remain: the new reading lock introduces an avoidable lock-upgrade deadlock beyond the status-move case, and the promised regression coverage is incomplete. I found no new blocking acceptance bypass. This verdict does not assert a failed database run.

This is a whole-patch, **source-only** review. No Docker, psql, CI, race, mutation, migration or terms runner was executed. No `opus-*.md` or `fable-*.md` was read. **Executed** means a filesystem/source check; **predicted** means a database result for the author to establish with the supplied probes. The round-2 author-run transcripts are historical evidence, not executions of r3.

## B — none identified

No remaining blocking defect was established by this source review. In particular, neither original B1 nor original B2 remains apparent in the frozen implementation. Runtime confirmation remains the author's work.

## S1 — predicted: FOR UPDATE adds an avoidable FK lock-upgrade deadlock

**Evidence:** `patch-25-frozen-r3.sql:2085` (`disputes_reading_fkey`) and `:3472` (`enforce_dispute_reading_released`). The latter requests `FOR UPDATE` even when the reading is not disputed.

The newly documented close-versus-reading-status-move deadlock is **not the only new deadlock shape**:

1. A and B each insert a different dispute naming the same existing reading. Each insert's foreign key obtains a KEY SHARE lock on the reading.
2. Each session inserts its own withdrawal. Their dispute mutexes differ.
3. Each forces the deferred release check. A's FOR UPDATE conflicts with B's retained KEY SHARE; B's FOR UPDATE conflicts with A's retained KEY SHARE.
4. One transaction must lose with 40P01, although neither actor updates the reading or its status, and the reading can be ordinary `active` throughout.

**Probes:** [07-a-fk-lock-upgrade.sql](codex-r3-probes/07-a-fk-lock-upgrade.sql), [07-b-fk-lock-upgrade.sql](codex-r3-probes/07-b-fk-lock-upgrade.sql). The schedule and expected diagnostics are at the top. This is a predicted availability/retry issue, not a claim that the race permits invalid state.

Use the weakest row lock that serializes release decisions against one another and against reading updates—`FOR NO KEY UPDATE` is the candidate to test here. It avoids conflicting with a mere foreign-key reference. Preserve the separate statement that reads the sibling statuses after acquiring the lock. Document the actual reading-first order of a reading UPDATE as well as the dispute-first order of a close; the header's numbered list is not a universal lock order for these two operations.

**Executed source coverage finding:** DR13 covers two closes of **previously committed** disputes. It does not cover the above insertion/close shape, either order of a close against the reading's status move, or an unrelated reading writer. The r3 plan explicitly requested both status-move orders, but the frozen race script contains neither. Add these cases and retain DR13 when adjusting the lock. The general “writers retry 40P01” rule protects correctness, but does not justify introducing unnecessary contention without testing it.

## S2 — executed (source): round-2 S2 is only partly closed

**Evidence:** `battery-25-frozen-r3.sql:851–864`; `mutations-25-frozen-r3.py:218–224`.

D4f2 now constructs a real foreign tariff and cites it as the owner. M65b removes the tenant comparison alone. This closes the central round-2 complaint that the only purported foreign-tariff test used a nonexistent fixture.

Two parts of the requested fix remain:

- D4f still names `…25ac`, which N1b creates inside `admits_undone`. It tests absence, not a real tariff hidden by RLS. Its new comment acknowledges “undone” but still describes that as invisibility.
- There are no independent owner-visible state, service or system mismatch cases, and no mutations removing those comparisons individually. The r3 plan's item 6 asked for all three.

Keep a real foreign tariff alive for the app-visible/invisible comparison, retain D4f2 for the owner-visible tenant mismatch, and add the three independent dimensional mismatches. This is a coverage/label finding, **not** an assertion that the frozen D4f guard accepts one of those mismatches. [00-contract-battery.sql](codex-r3-probes/00-contract-battery.sql) preserves the frozen tests and their fixture lifetimes, with caught-error diagnostics.

## N1 — executed: integrity and scope checks

All eleven checks matched **before source review**:

| File in this review directory | Expected and observed MD5 |
|---|---|
| review-brief-25-r3.md | cbd408125066db48dfef65b943958964 |
| patch-25-frozen-r3.sql | 9d2d3ed70656f1931df9e50c9b7b5ee6 |
| battery-25-frozen-r3.sql | 18fde97b141515e1b17059df9a690c45 |
| disputes-25-frozen-r3.sh | 0c13f9099548d3ae24b14ec21074f987 |
| mutations-25-frozen-r3.py | 99dbb3b568a9fff40d209644470bd7ad |
| terms-25-frozen-r3.py | 83d1484349ef8c3ad654eb40f2264eb6 |
| migration-25-frozen-r3.py | 55d80759b4066f5a037acc3bd104be20 |
| fill-manifest-25-frozen-r3.py | 2fe45983fc37c0973be9d420ae31ef20 |
| dispute_platform_defaults-frozen-r3.yaml | deb668299bc3bd44d1eb72a1aeb117d4 |
| dispute_platform_defaults-frozen-r3.seed.sql | 3832a44f5ae4c788a8451479390906ec |
| r2-to-r3.diff | fd6232e47e5a76bc9dfa5540215bc570 |

Read the complete r3 plan, including As built and Not changed; the r2 plan, design, inventory D/Q1, relevant DECISION-LOG rulings and GBM November 5 scenario answers; my r2 review and probes 00–06 with the author's transcripts. Reviewed the whole frozen implementation, supporting tests and generators, rather than treating the delta as the review boundary. The rulings were treated as the supplied product contract, not independently reinterpreted as legal advice.

Filesystem checks independently matched **all 30** pinned function-body MD5s to the frozen function bodies. Both committed dispute schema texts and the frozen platform-default seed are embedded verbatim. The four Python files parse as Python ASTs; this was parsing only, without importing or executing them.

## N2 — predicted: disposition of every round-2 finding and probe

| Round-2 item | R3 disposition and evidence |
|---|---|
| B1, cross-table UUID exclusion | Fixed in source: the exclusion is gone at `:3089`; strict sequence ordering excludes only records actually earlier than the close. D8a/D8b and M142 address the original exploit. Probe **01** repeats equal-ID and distinct-ID cases for amounts and determinations; all four should now refuse. |
| B2, two closes strand a reading | Fixed for the original schedule: the release check locks the common reading before its subsequent sibling-status query. DR13/M145 cover that change. Probe **02-a/02-b** supplies the complete schedule, replacing r2's one-leg advisory-lock witness. Lock choice and missing schedules remain S1. |
| S1, stage comparison | Fixed in source: increasing tariff ordinals, matching deciders, protective filing and decision comparisons. N9c–N9g and M149–M151 cover key directions. Probe **03** now predicts a nonempty comparison for the old 3,650-day/one-day example. Probe **08** adds finite filing boundaries, different anchors and repeated-decider multiplicity. |
| S2, phantom foreign tariff | Partly fixed: D4f2/M65b are meaningful; invisible-real-row and dimensional coverage remain S2 above. |
| 00, ordinary contract battery | Reissued against frozen r3 with SQLSTATE/message notices in every exception arm. It retains the author's assertions, rather than claiming independent coverage for all of them. Two clearly marked supplemental cases test a successful no-looser tariff citation under governing law and a dependent line-after-withdrawal CTE. |
| 04, COPY | Reissued. The owner COPY of withdrawal followed by escalation should still fail at the close guard. It prints COPY's own verbose error with `\errverbose`, not `LAST_ERROR_SQLSTATE`. |
| 05, roles/isolation/history | Reissued: app/core direct status updates, missing-identity owner close, valid replica-mode owner close, and literal isolation-level checks. |
| 06, catalogs/invariants | Reissued: registered rule tables, exact move-role grants, foreign keys and the invariant calls. |

Original probe 02's absent sibling advisory mutex is no longer evidence of a bug: r3 deliberately serializes on the reading instead. The historical author's r2 probe 01 and 03 successes demonstrate the old defects, not an r3 result.

## N3 — predicted: determination rules and statement shapes

**D4q/D4r.** The guard calls `rule_law_row_cite`, then fetches `r`, before comparing the tariff against `jsonb_build_array(to_jsonb(r))`. Thus the comparison is against the law row actually cited, under its shared citation lock. A supplied tariff first passes tenant/state/service/system/date checks and `rule_row_cite`. When the comparison is empty, omission is refused by D4q; when it is nonempty, citation is refused by D4r and law-only is available. Evidence: probe **00**, D4q, D8e/D8f and the supplemental successful tariff citation.

The omitted-tariff lookup itself takes no tariff citation lock. Its terms are immutable; a concurrent close can make an omission unnecessarily refused, and a concurrently inserted/backdated policy remains the disclosed R6 audit boundary. I found no new acceptance escape from D4q/D4r in the code, but do not claim this lookup is a serializable absence predicate.

**Stages.** A tariff filing window of `none` is widest; a law filing window of `none` cannot be replaced by finite days. Finite filing windows require the same anchor and at least the law's days. A law decision window of `none` accepts a finite or unlimited tariff decision window; a finite law decision window requires finite tariff days no greater. `j > v_pos` prevents reusing a tariff stage or moving backward. Choosing the earliest qualifying position leaves maximum room for later matches. Probe **08** exercises these additional boundaries; **00** retains reversal, unlimited-decision and wider-stage controls.

**Nothing after close.** All four child record tables have the ALWAYS AFTER guard. Amount lines receive a database-assigned sequence and resolve their dispute through their amount. Their parent amount must have been created in the current transaction, which supplies the dispute mutex already held by that amount's insert. Caller-supplied sequences are overwritten. Probe **00** includes both line ordering directions and a dependent CTE whose line carries the closing event's UUID and an attempted `record_seq = -1`; **01** covers both non-line table UUID collisions; **04** covers owner COPY; D5r/D5r2 cover multi-row events. No bypass was identified in those source paths.

**Other record rules.** The whole-patch pass retained the checks on issued bills, tenant/customer links, received dates, amount and line caps, same-transaction line completion, one live determination, outcome shapes, corrections and stage references. The readers require both coordinates, use recorded determinations/events, end shelter at the close date, and allocate line shares with cumulative rounding. Probe **00** carries their baseline checks, including history coordinates and end-day boundaries. These are predicted outcomes, not a claim of exhaustive runtime proof.

## N4 — executed source comparison; runtime preservation predicted: -17, -23 and invariants

The patch does not replace any -17 template function. Its default is a separately registered law-role table, not extra fields in a delegated document. That preserves the delegation branch and separates default applicability from statutory applicability. The seed, class coverage, start date and three blocks agree with the November 22 rulings. Probe **00**, groups P/D7/H, and probe **06** cover runtime registration/citation/invariant checks.

Compared the carried `assert_seal_role_invariants()` body directly with the last definition in `sql/tu.sql`: only the intended move-function ownership entry, grants entry/comment and addition of `tally_dispute` to the role loop differ. The carried reading-workflow body differs only by removal of the six obsolete dispute fields and their hint text. Its consumed-read/void protections were not rewritten.

The move remains a narrowly granted, RLS-bound `tally_dispute` definer. App/core cannot directly update dispute status. Owner history writes still require a valid tenant session identity for the definer's move; replica mode retains the ALWAYS business guards, but does **not** turn every ordinary FK into an ALWAYS check. Probe **05** covers these distinctions. Do not describe H17's single cross-tenant invoice case as a complete replica-mode referential audit.

The guard invariant pins listed trigger definitions/ALWAYS state, validated constraints, valid unique indexes, bodies, attributes, ACLs, NOT NULLs and exact policies. The sequence ACL is now in `c_tables`, and H16b3/M152 target grant drift. These are catalog checks, not a historical-row audit or proof of concurrency correctness. Unlisted additional triggers remain the explicitly accepted Not changed limitation. Probe **00** H16/H18 and **06** cover the runtime assertions.

## N5 — executed source findings; database outcomes predicted: tests and residual risk

The mutation runner requires the first failure to name its target check and distinguishes apply failures. That is useful, and M142–M152 target the new rules. I did not execute or independently certify the reported 153/153 run. M65's label remains broader than its absent-row fixture; M65b correctly narrows the tenant leg. A mutation caught at a named check still does not demonstrate coverage of the other OR terms in its condition.

Additional missing coverage: finite filing windows and repeated-decider multiplicity (probe **08** supplied); a successful governing-law tariff citation (**00** supplemental supplied); both reading-status-move race orders; and close-first platform-default citation. DR10 tests citation-first only. DR11 is explicitly sequential, not evidence of ordering concurrent backdated insertion against citation. S1's new two-session probe exercises a further untested lock path.

Some round-2 label limits remain nonblocking: S2 in the battery checks schema IDs and hash format, not hash equality to committed files; the separate filesystem check here establishes embedding. Migration P1 compares selected counts, not a complete catalog identity. H18b is a baseline seal-invariant call; H16d exercises owner drift through the dispute invariant. None should be described more strongly than its assertion.

**Residuals R1–R8 are not newly blocking under the settled scope:**

- R1/R2 are explicitly unimplemented governmental/conditional-law shapes, not implicit permissions.
- R3 assigns eligibility, class, amounts and due-process evaluation to the core; R4 checks a decider category rather than the user's authority.
- R5 excludes reading-only shelter under an issue-counted rule until a bill supplies the anchor. “Until a bill names it” is workflow shorthand: dispute identity is immutable, so this is not permission to attach an invoice by updating that dispute.
- R6 accepts later backdated policy as an audit obligation; it does not promise serialized absence.
- R7 is the session-identity contract of the narrow status-move definer.
- R8 leaves due-date eligibility to the core. The database's 60-day reader boundary does not itself implement the next-regular-bill due-date workflow or the whole-bill fallback when a customer supplies no disputed amount. Those remain required integration work under the recorded ruling.

Runtime evidence for the ordinary residual boundaries is in **00/05/06**. No independent legal-policy change is requested by this review.

## Probe execution notes

All probes are in [codex-r3-probes](codex-r3-probes/), are unexecuted, and end in `ROLLBACK`. Run each independent probe, or each scheduled pair, as owner on a fresh scratch clone with frozen r3 already applied. No probe creates, drops or alters roles. The two-session A files explicitly commit the minimal shared fixture; 02-A also commits the first close so B can test the fresh post-wait snapshot. These files are for throwaway clones, with the author responsible for dropping the clone afterward. Every caught exception prints SQLSTATE and message; COPY prints its own saved verbose error.

Before ready: resolve S1's lock choice and test the promised schedules, complete S2's fixture/mismatch coverage, and run the supplied probes. The original acceptance blockers appear repaired; the remaining requests should not reopen the settled platform-default design.
