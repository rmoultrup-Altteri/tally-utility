# Codex — v5.4.2-25, round 4

**Verdict: not yet.** The round-3 FK-lock defect and tariff-fixture defects have source-level fixes. The new combined document can still discard protections from the tariff, including a stage that the event guard then refuses to record. Its handling of incomparable sections also fails the standing “not comparable is refused” rule. The promised reverse reading-move race remains missing.

This is a whole-patch **source-only** review. **Executed** below means filesystem/source inspection, never database execution. **Predicted** means an unexecuted database outcome represented by a probe in [codex-r4-probes](codex-r4-probes/). No Docker, psql, CI, race, mutation, migration or terms runner was run. No `opus-*.md` or `fable-*.md` was read. The round-3 author transcripts are historical evidence, not round-4 results.

## B1 — predicted: whole-section replacement can remove protections from either document

**Evidence:** `patch-25-frozen-r4.sql:2644–2650` in `dispute_terms_combined`; comparator at `:1837–1926`; determination helper at `:2673`; event stage lookup at `:3051`.

The comparator answers whether the tariff is no looser than the law. A nonempty answer does **not** prove that the law is no looser than the tariff. The combination treats those propositions as equivalent: any finding other than blocks/duties replaces that entire section with the law's. This faithfully implements the plan's mechanical section-selection recipe, but not its stronger promise to preserve both documents' protections.

Three concrete cases:

1. **Subjects are sets, not a total order.** A law admits `meter_accuracy` and `calculation`; the tariff admits `meter_accuracy` and `deposit`. The comparator reports the missing calculation subject. Replacement supplies calculation but removes deposit. The protective combination must retain both sets' admitted subjects. Such a tariff can predate the changed law; the insert-time comparator does not establish compatibility with later law rows.
2. **Stages contain several independently protective promises.** The tariff gives the designated employee one day to decide and the regulator fifteen days. The later law leaves the employee without a deadline and tightens the regulator to ten days. A `stages:` finding replaces the whole array: the employee's one-day promise disappears. The same replacement drops a valid tariff-only stage after the law's last stage. This is observable beyond a helper's JSON: the event guard derives its allowed stage IDs from the combined array and rejects the lost stage with `[D5b]`.
3. **Incomparable is not “law is more protective.”** The comparator explicitly reports incomparable starts (`within_days` from receipt versus `before_termination`), ends (`earlier_of_resolution_and_days` versus `through_regulator_close`), and average-cap parameters (two years versus three). The combination returns the law's section without refusing or establishing that it preserves the tariff's promise. Which average is smaller depends on the customer's history. This is exactly the uncertainty for which the standing rule requires refusal, not an unconditional choice of one document.

**Probes:** [09-combination.sql](codex-r4-probes/09-combination.sql) validates both input documents and exercises all seven comparator section names, including union and ordered-end controls. It predicts deposit disappearing, the employee deadline becoming unlimited, and incomparable cases returning a result. The supplemental B1 block at the end of [00-contract-battery.sql](codex-r4-probes/00-contract-battery.sql) uses real rows: it writes an initially compliant tariff, tightens the law using D8's fixture, writes the combined determination, and attempts both the extra tariff stage and a surviving law stage. Expected: the tariff's one-day employee deadline and extra stage disappear, the extra event gets `23514 [D5b]`, and the law-stage control succeeds.

**Required fix:** distinguish dominance from incomparability. Union admitted subjects; preserve independently stronger stage deadlines and valid trailing tariff stages while retaining the law's ordering. Where the existing representation cannot express a protective combination, refuse explicitly rather than silently weakening either promise. Scalar choices need an established protective ordering; an incomparable comparison must not be interpreted as permission to select the law. Add both-direction and mixed-within-section regression cases, including real stage events. This is a defect in assembling the document the core evaluates, not a request to move the core's evaluation into the database.

## S1 — executed source finding; race outcome predicted: reverse reading-move coverage remains half-done

**Evidence:** `disputes-25-frozen-r4.sh:385–397`; r4 plan item 1 and As built.

DR15 covers **move first**, then close: A marks the reading disputed and holds its locks; B withdraws. DR15b is **two closes of the same dispute**, each followed by a reading update. B queues on that dispute before reaching its reading update. It does not exercise **close first**, then an independent reading move that acquires the reading row before waiting on the closing transaction's dispute lock.

That was explicitly requested in round 3 and again in the r4 plan. Add the reverse schedule and assert the resulting state/retry behavior. [10-a-close-first.sql](codex-r4-probes/10-a-close-first.sql) and [10-b-close-first.sql](codex-r4-probes/10-b-close-first.sql) supply it: A closes and pauses before its deferred check; B attempts to enter `disputed` and waits; A then forces release. One participant is predicted to report `40P01`. Both files roll back the test transactions. This is the already documented inversion, not a new acceptance bypass or a demand to eliminate every deadlock.

## N1 — executed: freeze and source checks

All ten frozen hashes and the brief's own hash matched **before reviewing source**:

| File | Expected = observed MD5 |
|---|---|
| review-brief-25-r4.md | ce97b1e2ddaeba56eafa809c9409e1da |
| patch-25-frozen-r4.sql | dc738d922cf27c9847347a507c055475 |
| battery-25-frozen-r4.sql | 557604c32211183f4ac5e07fb8f7b351 |
| disputes-25-frozen-r4.sh | cd393cfdb86854f449c42e8c43e5901c |
| mutations-25-frozen-r4.py | 3243d0b52ea7742348d1bbcc74358dd4 |
| terms-25-frozen-r4.py | 83d1484349ef8c3ad654eb40f2264eb6 |
| migration-25-frozen-r4.py | 55d80759b4066f5a037acc3bd104be20 |
| fill-manifest-25-frozen-r4.py | 33802a5b696602534f9b1b521981fc5d |
| dispute_platform_defaults-frozen-r4.yaml | deb668299bc3bd44d1eb72a1aeb117d4 |
| dispute_platform_defaults-frozen-r4.seed.sql | 3832a44f5ae4c788a8451479390906ec |
| r3-to-r4.diff | 9102047af72d253fa022cd837432ba0c |

Read the entire r4 plan, including the narrower As built decision; the earlier plans, design, inventory D/Q1, relevant DECISION-LOG rulings, GBM's November 5 answers, my round-3 review, and its probes and author diagnostics. The supplied rulings are the product contract; this review does not independently reinterpret the law.

Filesystem checks matched all **31 function-body MD5 pins** to the frozen patch. Both committed JSON schema texts and the frozen default seed are embedded verbatim. All four frozen Python sources parse as ASTs; none was imported or run. The new probes were checked for a final `ROLLBACK`, absence of role DDL, and SQLSTATE/message notices in exception handlers; COPY retains its own `\errverbose` output.

## N2 — executed source disposition; runtime outcomes predicted: every round-3 item and probe

| Prior item / probe | Round-4 disposition |
|---|---|
| S1, FK lock upgrade; 07-A/B | Fixed in source at patch `:3517`: `FOR NO KEY UPDATE`. DR14 and M153 specifically target the stronger-lock regression. Reissued 07 now predicts two successful releases, no 40P01. The remaining requested reverse-move coverage is S1 above. |
| S2, hidden tariff and dimensions | Fixed in source. D4f follows D7j and names its surviving T3 tariff under T1 identity. D4f2 retains the owner-visible tenant mismatch; D4f3/4/5 construct real own-tenant policies with independent state/service/system mismatches. M65, M65b/c/d/e target the separate comparisons. Runtime checks are in 00. |
| 01, equal UUID across record tables | The strict record-sequence check remains; no cross-table ID exclusion returned. Equal-ID and distinct-ID amount/determination attempts should all refuse. |
| 02-A/B, two closes of one reading | Shared reading serialization and the separate post-lock sibling query remain. Expected second release refusal `[T2c]`. DR13c adds B's actual COMMIT path to the frozen suite. |
| 03, very slow decision / short appeal | Still refused; positional matching further tightens stage order. |
| 08, finite windows / anchors / repeated deciders | Reissued unchanged in substance. Equal and wider windows remain controls; shorter/different-anchor/unlimited-decision cases refuse. Two law stages still require two positions. |
| 04, owner COPY | Reissued; withdrawal followed by escalation should refuse with `[D5f]`. COPY prints its own error, not `LAST_ERROR_SQLSTATE`. |
| 05, roles/isolation/history | Reissued: direct app/core status changes, missing identity, replica-mode owner close with identity, and explicit non-READ-COMMITTED isolation levels. |
| 06, catalogs/invariants | Reissued against r4. Includes rule registration, exact move-role grants, FKs, and all patch-tail invariant calls. |
| 00, contract battery and supplements | Rebuilt from frozen r4, preserving its fixture lifetimes and checks, with caught-error diagnostics. Retains the successful no-looser tariff citation and dependent line-after-close CTE; adds B1's live combined-stage case. |

The author's r3 runs establish the old FK deadlock and the expected prior refusals; they do not establish these r4 predictions. No other prior blocking defect was found to have returned.

## N3 — executed source assessment; database behavior predicted: combined terms and final stages

All comparator messages begin with one of the seven actual section keys: `blocks`, `duties`, `stages`, `subjects`, `shelter_earned`, `shelter_ends`, `must_pay`. The split-at-colon dispatch currently maps them correctly. The problem is the meaning assigned to a finding, not a misspelled prefix. A structured comparison result would make that distinction safer than parsing human messages.

Blocks and duties use a distinct sorted union. Both governing-law and tariff schemas require those objects, so a missing intermediate parent in `jsonb_set` is not a valid-row bypass here. Ordered scalar cases, including resolution versus a days-capped end, have meaningful positive coverage. Probe 09 includes those controls.

Granting `dispute_tariff_compare` to `tally_core` introduces no definer privilege: the function is STABLE, invoker-rights, has no writes or dynamic SQL, and only reads the shared subjects vocabulary through its helper. It does not look up private tariff rows. Probe 09 exercises the core call; 00/06 cover the role invariants and RLS readers.

I do **not** reject the As built allowance for an additional stage after the law's final stage solely because of `final`. Under the recorded interpretation, the law's decision remains binding and the extra stage delays none of its stages. The comparator now requires the law's stages at the first corresponding positions. N9g/h reject inserted stages; N9i admits a trailing stage; N9j admits a quicker regulator. These checks are in probe 00. This acceptance is separate from B1: once a trailing tariff stage is admitted, an unrelated later tightening must not silently delete it from the event document.

The stage event guard correctly calls the common determination-terms helper and checks ID, decider category and user presence. Consequently it consistently enforces the **wrong reduced stage list** in B1. Ordering actual stage events, evaluating deadlines and authenticating the user's decider authority are not newly implemented by this patch; R3/R4 remain the declared division of responsibility.

## N4 — executed source assessment; runtime predictions in 00–07 and 10: whole-patch guards and concurrency

The unchanged write paths retain tenant checks, immutable dispute identity, issued-bill/date checks, positive amount and line caps, same-transaction line completion, one live determination, correction-link checks, outcome shapes and append-only records. The AFTER guards cover amounts, lines, determinations and events; lines resolve their dispute through the parent amount. Database-assigned sequences override caller values. Probes 00/01/04 cover multi-row INSERT, dependent writable CTE, cross-table UUID reuse and owner COPY.

App writes go through invoker guards and RLS; core has read grants; the status move is the narrowly granted `tally_dispute` definer. Owner history writes still need tenant identity for that move. Replica mode retains ALWAYS business guards but does not make ordinary FKs ALWAYS; H17 is one targeted cross-tenant invoice check, not proof that every malformed history reference is impossible. Probes 00/05/06 retain these boundaries.

Dispute child writers acquire the advisory mutex before checking status. Amount lines rely on their parent having been inserted in the same transaction and therefore retaining its mutex. Determinations then acquire citation locks; law terms are read after citation. The release guard takes the reading lock before a separate sibling-status read. The lighter lock retains the needed writer conflict while avoiding FK key-share contention (02/07). READ COMMITTED is deliberately required by `dispute_lock`; repeatable read, serializable and literal read uncommitted refuse there (05).

The documented order is per operation, not a universal transaction order: a reading update holds the reading before taking dispute locks. The reverse-order deadlock remains documented and probed by 10. I found no additional r4-specific lock defect, but do not certify that the header's two examples exhaust all arbitrary multi-object transaction deadlocks.

The omitted-tariff lookup is still not protected by a citation/absence lock. Immutable terms and the explicit R6 boundary explain its scope; it is not a serializable absence predicate. DR11 is sequential. Close-first default citation remains absent from the frozen race suite. Neither omission supplies evidence of a newly accepted invalid row here.

The readers retain both required coordinates, recorded supersession, close-date termination, inclusive last-day handling and cumulative per-line rounding. Probe 00 includes the temporal and allocation checks. No new defect was identified in those unchanged paths.

## N5 — executed source comparison; preservation predicted in 00/06: -17, -23 and invariants

No -17 template function is replaced. The default stays in its separate registered law-role table; the delegation branch is not expanded. Its date, two municipal classes and three blocks agree with the November 22 rulings. The later tariff/default citation alternatives remain explicit.

Compared the carried seal-invariant body directly with its definition in `sql/tu.sql`: changes are the intended dispute move ownership entry, exact grant entry/comment and role-loop addition. The carried reading-workflow body changes only the six removed dispute fields and their hint. The existing consumed-reading and void protections were not relaxed.

The dispute invariant checks listed trigger definitions/ALWAYS state, validated constraints, valid unique indexes, body hashes, function attributes/ACLs, NOT NULLs, table ACL/RLS/owner, sequence start/increment/bounds/cycle, column grants and exact policies. The new combination helper and comparator grant are pinned. These checks detect catalog drift, not semantic correctness: pinning B1's body cannot establish its protection-preservation property. Extra unlisted triggers remain the explicitly accepted limitation. Sequence settings are pinned; this is not a historical record audit. Probe 00's H checks and probe 06 provide the runtime assertions.

## N6 — executed source findings: test strength and missing cases

The mutation runner distinguishes apply failures and requires the **first** failure to name its intended check. M153 is a useful distinct test of lock strength; M145 only tests removal of serialization. The D4f mutations now isolate the individual mismatch legs. I did not execute or certify the reported 161/161 run, and found no specific listed mutation demonstrably credited to the wrong check in source.

D8 exercises cross-section combination: tariff end/start/pay versus law stages, with unioned blocks/duties. It does not exercise **mixed protection within one section**, loss of a tariff-only stage, or incomparable sections in the combination. M147 removes replacement globally and is caught through stages; it does not establish correct replacement behavior for every section. Probe 09 and the live B1 supplement fill those gaps for author execution. S1 identifies the missing race direction.

Retained label limits: battery S2 tests schema IDs and hash format, not equality with the committed files (the separate filesystem check here establishes embedding). Migration P1 compares selected counts, not complete catalog identity. DR11 is not a race. The battery is a rollback fixture suite; it must not share a clone with the race script's committed fixtures. None of those limits should be presented as stronger evidence than it is.

## N7 — executed contract assessment; database boundaries predicted in 00/05/06: residuals R1–R8

None of the declared residuals is newly blocking under the settled scope. B1 is outside them: an implemented helper is losing stated protections.

- **R1/R2:** governmental-class and conditional-law shapes remain explicit scope exclusions, not implicit permissions.
- **R3:** eligibility, class, figures and due-process evaluation belong to the core. That does not excuse delivering a weakened combined document to it.
- **R4:** decider category is checked; user authority remains external.
- **R5:** a reading-only dispute has no bill anchor for an issue-counted end. Immutable identity means “until a bill names it” is workflow shorthand, not permission to update its invoice link.
- **R6:** later backdated policy is an audit obligation, not a promise of serialized absence.
- **R7:** owner history loads must set tenant identity for the RLS-bound move.
- **R8:** due-date eligibility, the whole-bill fallback when the customer supplies no amount, and the next-regular-bill due-date workflow remain core integration obligations under the rulings. A 60-day reader boundary alone does not implement them.

## Probe execution notes

All **14 SQL files** are unexecuted and end in `ROLLBACK`. Run each independent file, or each scheduled A/B pair, as owner on a fresh throwaway clone with frozen r4 already applied. No probe creates, drops or alters a role. Pair A files commit shared fixtures so the other session can see them; 02-A also commits its first close for the post-wait visibility test. The author disposes of those clones afterward. Each caught error prints SQLSTATE and message; probe 04 prints COPY's own verbose error.

Before ready: correct B1's combination semantics and add its regression cases; complete S1's reverse schedule; run the supplied probes. The settled silent-city default does not need reopening.
