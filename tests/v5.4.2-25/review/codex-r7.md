# v5.4.2-25 — Codex review round 7

**Verdict: ready.** No blocking defect identified in the whole frozen patch. Both of my round-6 should-fix findings are closed. One nonblocking documentation qualification remains below. All database behavior in this review is **predicted**, with SQL probes for the author; none was executed by me.

## B — executed source assessment

**No open blocking item.** Reviewed the complete patch, battery, races, mutation definitions/runner, terms tests, migration tests, manifest filler, platform-default sources and r6 delta; the complete r7 plan including “As built” and “Tests”; the application design/inventory/rulings; my round-6 review, all prior probes and the author's adjacent run transcripts. I did not read the other reviewers' review files.

The eleven checksums were checked first and matched, including the brief's checksum file:

| Frozen input | Verified MD5 |
|---|---|
| review-brief-25-r7.md | d2e98858f757fd7d5462399044d61983 |
| patch | a2646d043c09bca6beb3606623977ad4 |
| battery | 3255b77046b53f183b90b359df61edcf |
| races | ba77a03997a856bd00d90d3c0e7fcb88 |
| mutations | 68ee1252a020b63f67c522e05c120eeb |
| terms | 83d1484349ef8c3ad654eb40f2264eb6 |
| migration | 55d80759b4066f5a037acc3bd104be20 |
| fill-manifest | 33802a5b696602534f9b1b521981fc5d |
| default YAML | deb668299bc3bd44d1eb72a1aeb117d4 |
| default seed | 3832a44f5ae4c788a8451479390906ec |
| r6-to-r7.diff | 8a597274f2b2f05c06d98fcdcd05c348 |

Executed checks were source/text checks only. No Docker, psql, CI, race script, mutation runner or database-connected Python helper was run. The brief's 351 checks, 30 race results, 199 mutations and 59 CI results remain author-reported.

## S1 — executed documentation assessment; predicted witnesses: qualify R10's scope

[Patch R10](patch-25-frozen-r7.sql:174) correctly describes the law-nonfinal/policy-final tradeoff at the law's last stage. It is not an exhaustive description of losing policy finality. A shorter, older policy can end in a final decision at a position where a later law has a nonfinal stage followed by another stage. Combining them clears the policy's earlier final flag even though the law's **last** stage is final. That older policy could not newly pass filing against the longer law, but combination deliberately supports previously filed policies under later law.

[16-finality-scope.sql](codex-r7-probes/16-finality-scope.sql) supplies schema-valid documents for that case and the reverse flag direction. [13](codex-r7-probes/13-carried-matrices.sql) retains the valid no-finding law-last-nonfinal control. [00](codex-r7-probes/00-contract-battery.sql) retains the real-row later-law/final-stage/trailing-appeal controls.

Suggested wording: “At any matched place where the policy says final and the law says nonfinal, preserving the law's flag can remove favorable policy finality. This includes a shorter older policy under a longer later law.” The sentence about no seeded law ending nonfinal proves only the narrower example is absent.

For the opposite direction, law-final/policy-nonfinal, source preserves the tariff's trailing stages and admits their stage events. Under the standing interpretation that finality binds the utility and does not erase the customer's additional appeal, I find no demonstrated customer loss in this database patch. If the core treats `final=true` as an unconditional instruction to stop all appeal, an adverse decision could disadvantage the customer in this direction too. Thus R10 cannot establish a universal, customer-independent ranking of finality; its safety depends on the stated core contract. Do not remove the retained appeal or reinterpret finality as a generic “more protective” Boolean. This qualification does not require changing the standing combination ruling or block this patch.

## N1 — executed: my round-6 findings are closed

**Round-6 S1:** the comparator catalog comment is rewritten coherently, the structured-verdict comment now accounts for the fraction boundary, the release comment points to the full header lock rule, and design L6 no longer makes the unconditional undisputed-charges claim or ranks differently anchored starts. None of that finding remains half-done.

**Round-6 S2:** D8j and D9a now reject a NULL predicate with `IS DISTINCT FROM true`. D9j compares the complete stage array against its expected value. [00](codex-r7-probes/00-contract-battery.sql) repeats the missing-final witness against the new exact predicate: predicted rejection, rather than the old NULL escape. The prior B1/B2 repairs remain intact: stages merge even without a stages finding, and undisputed charges compare as withholding fraction 1.

## N2 — predicted: the whole payment ordering is consistent

[15-payment-matrix.sql](codex-r7-probes/15-payment-matrix.sql) checks all 64 ordered pairs, schema admissibility, exact combined payment objects and transitivity of the no-finding relation. It uses an explicit expected table independent of the comparator's branching. The following is that table; rows are tariff, columns law. `—` means no finding, `L` looser, `N` not comparable.

| | R | F | U | W.9 | W1 | W1.1 | A2 | A3 |
|---|---|---|---|---|---|---|---|---|
| R | — | — | L | L | L | L | L | L |
| F | — | — | L | L | L | L | L | L |
| U | — | — | — | — | — | L | — | — |
| W.9 | — | — | L | — | L | L | N | N |
| W1 | — | — | — | — | — | L | — | — |
| W1.1 | — | — | — | — | — | — | — | — |
| A2 | — | — | L | N | L | L | — | N |
| A3 | — | — | L | N | L | L | N | — |

R = unruled; F = full bill; U = undisputed charges; W = withholding fraction; A = average cap with two/three history years and the supported similar-customers fallback. R as tariff is a **defensive helper input**, rejected by the tariff schema, not a filing the patch permits. Equal average parameters compare equally; unequal histories can favor either customer. The schema offers only one no-history basis. Fractions within their family compare numerically, so the representative below/at/above-one cases also expose the cross-family boundary. The six original U/W orientations remain in 00 and 11; 13 retains the earlier validated matrices.

The premise holds under the supplied text of [7.45(6)(D)(ii)](../../../../application/wave3-build-2026-10-18/sources/law-text/tac7-45.txt:495): the exemption is part of the **disputed portion**, not an exemption from undisputed charges. For bill B and disputed portion D, undisputed charges are B−D. Withholding at least D asks no more than B−D; an average-usage shelter confined to disputed charges asks at least B−D. Consequently no customer pays more under W≥1 than under this average cap. This argument does not assume a particular implementation of the average calculation. A whole-bill cap that also waives undisputed charges would invalidate the premise, but that is not the supplied rule's meaning.

Below one, an average can leave more or less payable than W.9, so `not_comparable` is appropriate in both directions. Increasing the withholding fraction cannot increase payment. Equality for some customers, including zero disputed amount, does not invalidate `looser`: the ordering is weak dominance, not a promise of strictly more protection for every bill. The formerly missing W≥1/average edges now agree with U=W1; no no-finding transitivity contradiction remains in this matrix.

## N3 — predicted: other comparison and combination paths

Probes [00](codex-r7-probes/00-contract-battery.sql), [03](codex-r7-probes/03-stage-comparison.sql), [08](codex-r7-probes/08-stage-boundaries.sql), [09](codex-r7-probes/09-combination.sql), [11](codex-r7-probes/11-withholding-and-subjects.sql), [13](codex-r7-probes/13-carried-matrices.sql) and [16](codex-r7-probes/16-finality-scope.sql) cover these predictions:

- Stage prefixes are positional, including repeated deciders. Wider filing windows and quicker decisions are preserved; different finite anchors are not assumed comparable. Missing/mismatched law stages are restored and displaced tariff stages retained with collision-safe IDs.
- List findings say `lacks`, not scalar dominance. Subjects merge by admitted coverage; blocks and duties are unions. Scalar incomparability keeps both alternatives, with a `law:` payment ID when needed. Law-winning scalar comparisons keep the law's term.
- `any_time` is widest under the explicit premise that an unrestricted dispute may also be made through the regulator-complaint route. Other unlike start/end shapes remain unranked unless the documented order applies. A core interpreting regulator complaint as a separate eligibility prerequisite must preserve that distinction.
- Combined output is data for the core, not a document expected to pass either input schema. It is recomputed on read; the patch does not promise a permanently materialized historical combination.

## N4 — predicted: records, roles, statement shapes and history loads

No new application bypass was identified. [00](codex-r7-probes/00-contract-battery.sql), [01](codex-r7-probes/01-cross-table-id.sql), [04](codex-r7-probes/04-copy.sql), [05](codex-r7-probes/05-roles-and-isolation.sql) and [06](codex-r7-probes/06-catalog.sql) carry the concrete controls.

The record guards preserve immutable dispute identity, invoice/customer/tenant coordinates, issued-bill requirements, amount/positive-line caps, same-transaction amount lines and their deferred sum. Determinations check governing/cited rows, class/profile/date shape, supersession, available tariff/default selection, component membership, blocks and supported end bounds. They intentionally do not independently compute eligibility, classification or monetary figures.

Nothing-after-close is enforced with database record ordering, including same-statement/COPY and writable-CTE cases; supplying a low sequence or reusing a UUID across record tables does not exempt a later record. The status transition has restricted `tally_dispute` definer rights, checks its cause, and remains RLS-bound. App/core privileges differ intentionally. Owner history loads preserve timestamps but still need application identity for the restricted status move. ALWAYS guards remain active in replica mode; ordinary foreign keys do not thereby become ALWAYS. This is not a guarantee against a superuser disabling constraints or rewriting arbitrary catalogs.

## N5 — executed source assessment; predicted concurrency results

The lock rule is followed by the principal append/citation paths, but **is not a universal acyclic lock order**. The header and revised release comment correctly disclose the exceptions. Record writes serialize on the dispute mutex; determinations then acquire citation locks. Release checks lock the reading with `FOR NO KEY UPDATE` before the separate sibling-open query. READ COMMITTED is required for writes taking the mutex so the post-wait query can see the winning transaction.

The author's old transcripts show the expected release serialization, successful FK key-share controls and deadlocks in the inversion probes. Those are historical author executions, not r7 execution by me. Reissued predictions:

| Probe pair | Expected result |
|---|---|
| 02-A/B | Second release sees first committed close and refuses the inconsistent reading state, 23514/T2c. |
| 07-A/B | FK key-share does not recreate the old release lock-upgrade deadlock. |
| 10-A/B | Reading-row/dispute inversion can produce 40P01. |
| 12-A/B | Even a reading notes update followed by an amount can produce that inversion. |
| 14-A/B | Opposite acquisition of two dispute mutexes can produce 40P01. |

The loser must retry; which session loses is not promised. Probe 05 covers rejection of repeatable-read, serializable and the explicitly named read-uncommitted setting. Tariff absence is not protected against future backdated insertion (R6), and unrelated core classification inputs are not made immutable by the dispute mutex. I found no additional unacknowledged ordering hole in the reviewed paths.

## N6 — executed source checks; predicted catalog checks: -17 and -23

The patch registers its three rule tables through -17's template rather than replacing its generic enforcement. Static comparison against the latest base definitions shows the carried seal invariant changes only to include `tally_dispute` and its exact function/grants. The reading validation workflow removes the six retired dispute columns from its permitted-change list and updates the hint; it does not loosen the consumed reading's billing-field freeze.

I independently recomputed all **32 pinned function-body MD5s** from frozen patch text; all match. Both embedded schema JSON objects equal the committed schema JSON objects. These were filesystem-only checks. [00](codex-r7-probes/00-contract-battery.sql) H16/H18 and [06](codex-r7-probes/06-catalog.sql) cover the predicted runtime invariants, including disabled triggers, changed bodies/owners, ACL drift, dropped constraints/NOT NULL, policy drift and sequence settings.

The invariants protect specified catalog properties, not arbitrary semantic correctness or every conceivable extra trigger. The invariant functions themselves are not part of the 32-body manifest. The existence marker makes a normal second atomic application a no-op; it is not a general repair mechanism for manually constructed partial installations.

## N7 — executed test assessment; predicted supplements

The new N5c/N5d/N5e and D9t checks cover both boundary directions. D9t2/D9t3 distinguish the actual displaced and retained component IDs on the later-law path. D4y2/D4y3 use the real unprotected 7.45(1) row and its unruled end, checking allowed bounded/no-end records without inventing an unsupported law shape. D9u checks the opposite final flag. My old S2 NULL escape is repaired.

Two modest coverage limits remain: D9t4 checks only the alternatives' length, not their identities/content, and D9u is a direct-helper test whose synthetic stage overrides lack the citations a stored law requires. Neither proves a production failure. Probe 00 adds exact D9t4 alternatives plus successful real determinations using each component; probes 13/16 use schema-valid finality documents. Some D9t direct tariff values also carry law-style citations; the new 64-pair probe validates actual tariff shapes separately.

M188–M191 target the new cross-family boundary branches, M192 the unruled-end path, M193 preservation of a policy final flag where law says nonfinal. M17's retarget to N5c is justified: this newly admitted tariff encounters the mutated comparison with the unprotected law's unruled start first. It is a relevant behavioral failure. The runner suppresses the tail body invariant for behavioral mutants and requires the named first failing check; a later manifest mismatch is not credited. I found no concrete wrong-reason credited mutant in source, but did not reproduce the reported results.

Existing label limits remain: battery S2 checks schema ID/hash format, migration P1 checks selected counts, and DR11 is sequential. Race polling/hold budgets are not a guarantee against environmental timing failures. Frozen Python snapshots retain paths relative to their original locations and should not be launched from the review directory as though relocated installations.

## N8 — executed scope assessment; predicted boundaries: R1–R10

None independently blocks this scoped patch under the supplied rulings. R1's governmental classification and R2's conditional-law shapes remain outside the implemented model. R3 leaves class, eligibility, amounts and due-process evaluation to the core. R4 checks the decider category, not the user's adjudicative authority. R5 leaves reading-only shelter without an invoice reader/issue-date anchor. R6 accepts the later-backdated-policy audit obligation. R7 documents restricted status-move identity even for history loads. R8 leaves due-day eligibility interpretation to the core. R9 can prevent a common policy from satisfying incompatible class stage prefixes and falls back toward law. R10 requires the qualification in S1; it does not justify silently discarding either party's preserved appeal. Probes 00/05/06/09/11/13/16 supply the relevant database boundaries; the external legal/core obligations are not database guarantees.

## N9 — predicted, not executed: probe handoff

There are **22 SQL files** in [codex-r7-probes](codex-r7-probes/). Every prior probe is reissued, with 00 rebuilt from the frozen r7 battery and updated supplements. Prior 13 is named `13-carried-matrices.sql`; 15 is the complete payment matrix; 16 is finality scope. Files 01–14 otherwise retain their prior purposes and scheduled A/B arrangements.

Run each independent file or pair as owner on its own fresh throwaway clone with frozen r7 applied. A files commit shared fixtures as their headers specify; the paired schedule matters. Every file ends in `ROLLBACK`; dispose of each scratch clone afterward. No probe creates, drops or alters roles. Caught errors print SQLSTATE and message with `RAISE NOTICE`. COPY probe 04 prints its own error with `\errverbose`, without relying on `LAST_ERROR_SQLSTATE`.

Static checks verified terminal rollbacks, absence of role DDL, exception notices and parseable embedded case JSON. Exploratory probes may catch and print an unexpected error without failing the file: inspect their output, not merely the process exit code. Only this review and these probe files were written.
