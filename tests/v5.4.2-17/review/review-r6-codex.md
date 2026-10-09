# v5.4.2-17, round 6 — Codex review

**Verdict: ready on source review; no blocking finding identified.** Database verification is pending operator execution. The r5 integrity fixes and the r2 blockers remain addressed. Two nonblocking should-fixes remain: complete (or narrow the documented promise of) discriminator-property `$ref` support, and make the new trigger assertion verify trigger identity as well as its name. Two additional registration limitations deserve explicit notes and regression coverage.

## Provenance and execution boundary

I read the brief and verified the frozen artefacts **before inspecting the implementation**:

| Artefact | Observed MD5 | Result |
|---|---|---|
| `tests/v5.4.2-17/review/patch-17-frozen-r6.sql` | `e56f35010b3697680cff673cf44cbd8e` | Matches |
| `tests/v5.4.2-17/review/battery-17-frozen-r6.sql` | `f65867baaf103dd589c581520cd5228f` | Matches |

References use **P** = `tests/v5.4.2-17/review/patch-17-frozen-r6.sql`, **B** = `tests/v5.4.2-17/review/battery-17-frozen-r6.sql`, **L** = `tools/law/lawc.py`, **ZZ** = `law/fixtures/zz/fixture-zz.sql`. Numbers following these abbreviations are file line numbers. Probe paths below are relative to `tests/v5.4.2-17/review/codex-r6-probes/`.

Scope: the frozen SQL and changes from r5; the amended inventory and adopted convention; prior Codex findings; the fixture, schemas and law-file pipeline; isolation/race/mutation harnesses; CI; relevant -13/-15 table definitions and -16/base-schema profile/isolation patterns. No implementation or frozen artefact was changed.

**The sandbox cannot reach Docker. I did not try Docker**, run a database server, connect to `tally` or `postgres`, or create a database. Every database probe requested by this review is a self-contained SQL file listed below. Each guards the `codex` database-name prefix, performs its own setup, and rolls back. They require an operator-owned clone with the frozen r6 patch already applied and clone TEMP privileges revoked as the brief directs. They do not require loading the ZZ fixture or another probe first. Run each in a fresh psql session; a failure under `ON_ERROR_STOP` can leave that session in an aborted transaction until rollback/disconnect.

Completed local checks:

- `lawc.py check law/fixtures/zz/zz_fee_rules.yaml`: **3 rows valid**.
- `lawc.emit(read_law_file(...))` exactly equals committed `zz_fee_rules.seed.sql`.
- Python fixed rules reject NUL, lone-surrogate values and lone-surrogate keys; accept a valid supplementary-plane character.
- All **165** mutation transformations find their anchors in frozen r6. This is harness applicability, **not** 165 observed mutation kills.
- Shell syntax checks pass for CI, isolation, rule-close races and law-file runners.
- A ZZ schema with delegated `governs` replaced by a reference to its identical string/const definition accepts the delegated document through `reference_errors`, but `typed` raises `a oneOf needs exactly one const discriminator`. This locally confirms the tooling half of S1.

Not executed: patch apply/reapply, the SQL battery, SQL probe files, database W3/W4, X1–X6 isolation cases, RC1–RC7 races, mutation executions, or database invariant assertions. No operator results have been appended at writing time. Database outcomes below are source predictions, not reported passes.

## Blocking findings

**None identified.** Neither should-fix introduces an ordinary-writer acceptance escape in a correctly registered, unchanged table. S1 rejects a supported-looking authoring spelling; S2 requires a subsequent owner DDL change that incorrectly replaces an installed trigger. The newly discovered limitations do not prevent the -13 migration or -15 rewrite from using the machinery with inline discriminators and correctly installed triggers.

## Should-fix findings

### S1 — The advertised property-reference support still excludes `governs`

**Evidence:** `law/README.md:99` allows a property of the delegated branch to be a `$ref` to its exact standard shape. P:1024–1030 now resolves its `governs`, `citation` and `note` property nodes for exact-shape comparison. However, discriminator discovery at P:372 reads `properties/<name>/const` directly. Distinct-discriminator checking at P:482, document branch selection at P:700–706, and law-branch classification at P:1006–1011 also read inline consts. L:192–204 and L:216–217 have the same assumption.

**Counterexample:** move only `{"type":"string","const":"delegated_to_utility"}` into `$defs/governs`, then use `{"$ref":"#/$defs/governs"}` for that property. Keep `citation`, required keys, the other branch, and all constraints unchanged. This is semantically the same schema, but the database should refuse it at subset checking before reaching the new comparison. The loader's rejection was observed locally; the reference validator plus fixed rules accepted its delegated document. **p10** captures database registration and positive referenced-citation control, plus cycle and union-target negatives.

**Impact:** incomplete r5 Fable S1 follow-through and a misleading new format promise; no invalid row is admitted. Inline `governs` works, so this is nonblocking.

**Fix:** either explicitly require inline discriminator consts in the README/subset contract, or resolve the property consistently in discovery, uniqueness, branch selection and law-role classification, in SQL and Python. Merely changing discovery would create a new mismatch. Add a `governs` reference test beside B:R3i, which currently exercises only `citation` (B:245).

### S2 — The trigger invariant can accept a trigger with the right name on the wrong event

**Evidence:** P:1501 exempts `rule_row_insert` and `rule_row_history` from the late-name check. P:1504–1507 verifies only that each template name exists with `tgenabled = 'A'`. It does not verify `tgfoid`, `tgtype`, an unconditional definition, or the expected event coverage.

**Counterexample:** register a normal table; replace `rule_row_history` with an ENABLE ALWAYS, BEFORE INSERT noop of the same name; run `assert_rule_table_invariants()`. The assertion should pass even though UPDATE/DELETE have no history guard. **p12** then changes `source_note` without closing the row, showing the consequence. This is an owner-migration configuration defect that CI's newly advertised assertion misses, not something `tally_app` can install.

At initial registration, the same reserved-name trigger on the wrong event instead causes duplicate-object failure when registration creates its real trigger (P:1783); this fails closed. The two phases must not be conflated.

**Fix:** verify the three expected trigger functions, complete timing/event/row-level bitmasks, no WHEN filter and expected arguments, as well as ENABLE ALWAYS. Add a negative replacing a template trigger, not just disabling it. Existing B:T1l/T1m (B:472–476) cover a later extra trigger and a disabled trigger but miss this replacement.

## Notes and explicitly bounded guarantees

### N1 — Delegated facet dry-run is not an all-branch compatibility proof

P:1538–1561 computes facets on exactly `{"governs":"delegated_to_utility","citation":"x"}` and checks NULL against NOT NULL columns. P:1718 applies this to adopting registrations too; P:1888 applies it again for the version used by a new/adopted row. These correctly address the specific r5 delegated-document problem.

A declared `text` facet at `$.cap` and a physical `text` column pass registration when the delegated document has no cap. A law branch with numeric `cap` is schema-valid but fails the facet derivation at P:1218. **p11** contains that example, a successful delegated insert, and an adopting-table NOT NULL negative. This is fail-closed and does not restore r2 B1: declared and physical types agree; the schema and extraction path disagree. P:1228 already calls such disagreement a registration defect, but the implementation does not detect every such defect during registration. Add branch examples that run through actual row preparation, or document that remaining schema/facet compatibility is checked on use. The same single-document dry-run is not a proof of arbitrary table CHECKs, vocabulary compatibility, area hooks or every allowed citation value.

### N2 — Blank legacy keys survive registration but cannot be adopted

P:1660–1667 checks an area's key column type/NOT NULL, and P:1697–1712 checks empty legacy documents. Neither scans the legacy key values. Registration can therefore succeed with an existing empty-string key. Adoption then calls preparation at P:2176, and the new P:1854 key check rejects it. History also prevents simply editing the key afterward. **p06** demonstrates this path and separately checks direct-insert refusal.

This does not bypass the new guard: the invalid legacy row never gains convention terms. It is a migration-preflight limitation. Validate/repair legacy keys before registration, preferably reject them during adopting registration with an actionable diagnostic. -13's existing class/cause vocabulary FKs provide a stronger starting point (`sql/v5.4.2-13-backbilling-caps.sql:674–708`); no evidence here shows its current rows have this problem.

## Round-5 fixes and required adjacent probes

| r5 item | r6 assessment | Evidence and probe |
|---|---|---|
| Opus S1: delegated/version guards lacked isolated cases | Addressed in the battery source | B:R3h, R4s–R4v at B:242–258 separately omit citation-required, version-required, positive minimum, minimum presence and integer minimum. p01/p02 retain earlier independent controls. No execution claim. |
| Opus S2: facets can make delegated rows unstorable | Addressed for the promised standard-document dry-run | P:1538,1718,1888; B:T1n–T1p at B:478–505. p11 tests the adopting path and the other-branch boundary (N1). |
| Opus S3: strategy could be an unrestricted string | Addressed | P:555–558 requires string const or an enum array; ordinary string-schema checks enforce enum element types and the per-type keyword allowlist prevents an unrelated type from smuggling an enum through. B:R4w/R4x at B:259–264. |
| Fable S1: delegated property references | Partially addressed | Citation/note normalization is sound; direct reference cycles/chains fail schema checks, and a union-valued citation is not the standard string shape. `governs` remains rejected (S1). p10. |
| Fable S2: late BEFORE ROW rewriting | Addressed for extra triggers; assertion identity gap S2 | P:1490–1532,1722,1782–1787; p12 covers digits, uppercase, underscore, names on either side of the boundary, reserved name on another event, statement-level and AFTER triggers, and later replacement. |
| Codex S1: blank direct area key | Addressed | P:1854 calls the same P:2466 key validator as lookup/seeding; adoption uses preparation too. p06; N2 states registration's legacy limitation. |
| Codex S2: nonfinite published values/bounds | Addressed | P:2553–2556,2591,2643 compare numeric values with NaN and both infinities, rather than comparing input spellings. `inf`, `+Infinity` and `-inf` normalize before these comparisons. p09 tests each as value/min/max without finite range bounds masking the special-value check; finite 1.25 is its control. |

The new trigger-name comparison explicitly uses C collation (P:1500), so case/digits/underscores are compared by the intended byte order. Statement-level BEFORE and row AFTER triggers do not rewrite the current NEW tuple after validation; their ordinary nested DML still traverses the row guards. They are intentionally excluded from this particular rule. This does not certify arbitrary owner-written trigger bodies or SECURITY DEFINER functions.

The cycle test does not ask the database to expand an unbounded chain: P:453–454 and the `$defs` checks reject reference-to-reference definitions. A reference to a definition that is a discriminated object union can be supported in ordinary document positions; substituting it for the standard delegated citation is correctly refused because that position must be the standard string, not an object union.

## Round-2 findings, r4 status, and r3/r4 regressions

“Held in r4” below assesses the historical fix, not a newly executed r4 build. “Holds in r6” is source confirmation plus the specified pending probes.

| Earlier finding | Held in r4? | Holds in r6? |
|---|---|---|
| B1: declared facet and physical column could be different allowed types | Yes | Yes: exact pairings at P:1467–1477, all registered versions checked at P:1715, each row version at P:1887. p04. N1 concerns extraction semantics, not a regression of this type-pairing fix. |
| B2: union branches incorrectly consumed document depth | Yes | Yes: branch recursion keeps `p_depth` at P:712; children increment depth at P:730/P:750. B:V24 at 386; p07 checks depth 64 versus 65 through a recursive referenced union. |
| B3: adopting registration admitted already-filled, unchecked documents | Yes | Yes: P:1705 rejects any non-NULL terms/source/kind/version in preexisting rows. B:A1e at 836; p04. N2's still-empty legacy row is a distinct limitation. |
| NUL/lone surrogate handling | Values/NUL yes; surrogate keys were still r4 S2 | Keys fixed by r5 and still fixed at L:289–291; locally checked. P:881–886 rejects PostgreSQL-unrepresentable JSON before duplicate parsing. p07 includes escaped duplicate keys, NUL, lone-surrogate key and valid pair. |
| Reusable core invariant | Yes | Yes: P:3055–3119 checks role attributes/membership, materialized-view access including columns, default ACLs, TEMP/database/schema CREATE. Tail P:3123 and CI tests/ci.sh:90 call it. p05. It complements rather than replaces the tenant invariant. |
| Freeze changed schema text without updating hash | Yes | Yes: non-freeze fields compare as text at P:964, hash stamped on insert at P:1040. B:R8c at 659; p04 includes scale-changing and ordinary freezes. |
| Isolated noninteger/array-uniqueness/depth/adoption cases | Named gaps fixed | Still present: B:V10b/V13b at 368/371, V24, T1h, A1e. This is not proof that every possible guard has unique coverage. |
| APPLY mutation counted any apply failure | Yes | Still fixed: tests/v5.4.2-17/mutations-17.py:517–524 requires the designated phrase. Unrelated failure is MISSED/APPLY-ERROR, not a caught mutation. All anchors matched locally; kills pending. |

The separate adoption-equivalence hook remains one-time (P:2177–2178). The permanent insert hook remains in preparation (P:1966). r3/r4 did not reintroduce the old requirement that every future row match legacy columns. The whole-row comparison preserves identity and dates; R20 accurately records JSONB versus text comparison boundaries.

The r4 delegated-shape blocker still fails closed at P:1017–1036 (p01); the lone-strategy version requirement still applies to every strategy-bearing object at P:536–551 (p02); malformed seed applicability is checked before identity matching at P:2380–2400 (p03). The r4 adoption documentation now identifies `p_adoption_check` in R14. No new ordinary-writer integrity hole was found in these repairs.

## Step-2 inventory traceability

**Held** means implemented in the inspected source/format, not an executed SQL pass. **Residual** means disclosed unfinished work, not completion. These dispositions use the inventory's post-r1 amendments.

| Requirement | Disposition | Evidence / boundary |
|---|---|---|
| V1 registry/version immutability | Held | P:909–1053: registry, ordered versions, immutable role/hash, one-way freeze under schema lock. |
| V2 table-kind pinning | Held | P:1749–1751 installs CHECK and schema FK; consumer kinds are Area. |
| V3 document checks | Held within registered subset | P:397–865: closed objects, required/no-null, exact numeric types/bounds, arrays/uniqueness, string enums, component ids. Rationals are typed num/den objects with denominator bounds; arithmetic stays in core. |
| V4 strategy unions | Held, with S1 authoring limitation | P:464–486 and 689–712 select one required distinct string-const discriminator; attribute-dependent shapes need no table lookup. |
| V5 strategy versions | Held | P:536–558 requires bounded positive integer version and closed strategy names on every strategy-bearing object. |
| V6 section citations | Held format | law/README.md:69; ZZ law schema/rows include section citations. Area schemas decide which sections require them. |
| V7 explicit unruled versus absence | Held | String const/enum support plus fixed null refusal; no inserted parameter defaults (P:685,720–730). |
| V8 standard delegated law | Held for inline discriminators; S1 syntax gap | P:998–1037 and delegated facet dry-run P:1538. Explicit cited delegation stays distinct from unknown law. |
| V9 unsupported keywords refused | Held for subset | Per-node/type allowlist P:427–442; recursive validation and `$defs` checks P:617–658. S1 is an overly narrow accepted spelling, not an ignored constraint. |
| V10 reference cross-check | Held mechanism; runtime pending; R7 | L:520–537 compares SQL with Draft202012Validator plus fixed rules on corpus; not a proof of all schemas/documents. |
| F1 derived immutable facets | Held; R9 | P:1072–1229 declares/derives facets, P:1880–1904 checks set/types/writer agreement, P:2140 protects whole row. |
| F2 facet types | Held | P:1180–1229 and 1467 support text/text[]/integer/boolean plus number/present; no typmod rounding permitted by physical checks. |
| F3 scoped vocabulary checks | Held mechanism | P:1145–1165 validates configuration; P:1907–1932 quotes names/values and checks codes in row scope. Area must supply tenant scope for tenant vocabularies. |
| F4 area-key predicates | Held hook | Signature P:1731; prepared-row call P:1966. Actual area predicate is Area work. |
| F7 component citation | Held pattern | ZZ:79–104 checks component against governing law/tariff facet after correct-row citation. |
| T1 envelope/history/close floor | Held template | P:1566–1796 installs envelope constraints/exclusion/triggers; P:2115–2198 close-only history and hook floor. S2 limits later-DDL assertion, N2 adoption preflight. Areas supply complete floors. |
| T2 owner/system/jurisdiction applicability | Held | P:1243–1361 immutable ordinals/set spans; P:1947–1956 derives spans; P:1764 exclusion uses overlap. NULL means all, empty/duplicate sets refused. |
| T3 profile-to-law resolution | Held helper | P:2238–2285 uses -16 utility_service_profile_as_of and exact key/date, refuses zero/multiple rows. Premise-to-system selection is upstream/Area. |
| T4 citation/close serialization | Held protocol; runtime pending | P:2149 exclusive lock before floor; P:2222 shared lock before reread; READ COMMITTED guard P:256. Law citation resolves after locking P:2298–2302. |
| T5 strict seeding | Held documented identity; R20/R21 | P:2357–2460 validates complete envelope, compares applicability/key/start and then content/end/citation; no upsert. p03. |
| T6 one-time adoption | Held mechanism; R14 | Empty-document registration P:1697–1712, migration-only fill and equivalence hook P:2163–2190; key/dates retained. N2 preflight limitation. |
| U1 tenant tariff envelope | Held | P:1646–1653,1769–1780: tenant/system keys, tariff citation, canonical FORCE RLS and grants, common history/floor. |
| U2 duplicate JSON keys | Held | P:869–900 checks original JSON text recursively before returning JSONB; preparation uses it at P:1841. p07. |
| U3 stricter comparison/later-law finding | Held infrastructure; R5/R6/R12/R16/R17/R18 | P:2007–2111 covers full date range and law lock/reread; area comparator called P:2103; finding kind P:2800. No core audit executor yet. |
| U4 always law, optional tariff | Held pattern | P:2291–2349 and ZZ:65–104; delegated law preserves mandatory law FK even for municipal tariffs. |
| P1 published values | Held scope/unit/value mechanism; residual R4/R10 | P:2506–2698: typed state/service scope, unit vocabulary, finite exact numeric, range/exclusion/citation/history. Class scope amended out; **citation close floor remains unimplemented**, explicitly R4. |
| P3 named published references | Held format/helper | law/README.md:71, P:2668 dated exact-scope lookup; optional facet vocabulary against rule_parameters. |
| C1 core role | Held mechanism; R1/R8 | P:200–247,3055–3119; NOLOGIN, no role memberships, no code-definition privileges, explicit grants and tenant RLS. Actual core login/service-user choice deferred. |
| C2 core-only grant pattern | Held pattern; identity R1 | ZZ:125–137 demonstrates core INSERT/app SELECT. Consumer migrations must move their grants and decide evaluated_by. |
| C3 audit findings/dispositions | Held; R13 | P:2767–3023: tenant-owned append-only rows, scoped subject/rule checks, stamped version/release/coverage, missed-decision fields, separate user dispositions. Subject durability is Area responsibility. p08. |
| C4 DB-computed inputs fingerprint | Held pattern; R15/R19 | P:2709–2760: inputs schema/role/version, freeze lock, canonical numeric validation and SHA-256 of stored JSONB text. Record columns/append-only behavior remain area obligations; insert-only stamp. |
| L1 law files | Held amended format | L:336–401 and law/README.md:13–46: table/state/service files, applicability sets, dated cited rows and scenario shape. Scenario presence is optional, not mandatory coverage. |
| L2 strict loader | Held | L:72–129 duplicate/tag/anchor/alias rejection; L:207 schema-directed scalar typing; L:141–179 exact serialization; L:404–416 seed emission. S1 affects referenced discriminator authoring. |
| L3 CI | Held structure; runtime pending; R11 | tests/ci.sh:18–91 and .github/workflows/ci.yml:20–44 build/test PG16, strict apply twice, batteries/isolation/races/files/invariants. Scenarios are shape-checked; schema/execution deferred per amended inventory. |
| L4 fictional fixture | Held | ZZ:23–36 three kinds/scoped facets, tables/comparator/citation/core pattern, zz_fee_rules.yaml's municipal-bound and delegated cases plus non-Texas strategy examples. |

F5/F6, U5, P2/P4 and consumer kind rows are Area/no-Step-2-work entries. T7 is explicitly Out, recorded in R2. There is no newly identified undisclosed Step-2 omission; P1's floor is a disclosed residual, not a completed guard. Likewise U3's audit table/kind is not a running audit job, and L3's golden scenario shapes are not executable legal tests.

## Can -13 and -15 actually use it?

**Yes, with their stated area work.** -13's `customer_class` and `cause` are NOT NULL text with vocabulary FKs (`sql/v5.4.2-13-backbilling-caps.sql:674–708`), which fits equality-based area keys. It needs its correct applicability columns/spans before registration, an adoption equivalence function that includes child window terms, removal of its old close-only history trigger (`...-13...sql:852–905`) in the same transaction, and the one-time document fill. Keep row IDs/dates/citations, validate legacy key content first (N2), then retire obsolete typed content. This is a format migration, not a new dated law row. No -13 facet is forced where no record guard needs one.

-15's law key includes customer class and basis (`sql/v5.4.2-15-deposits-law-to-core.sql:465–505`); its rewrite can declare the listed component/scope/trigger/instalment/return/waiver facets with compatible physical columns and delegated-safe paths. NULL scalar facets and empty arrays under delegation are meaningful; area constraints must allow that case. Its core-only records and record-integrity guards still need migration, plus tenant vocabularies, complete close floors and the comparator.

Owner types and system kinds are sets; jurisdiction represents either/both boolean states; NULL spans cover every ordinal. This is appropriate for municipal/investor/cooperative applicability without a nullable equality exclusion escape (P:1302–1361,1764). Area keys deliberately have no wildcard (R3): enumerate class rows or choose a different key. A record cites the actual law in force and optionally its own tariff; municipal self-policy uses the explicit delegated row, never a fabricated commission-law citation or missing-law fallback (ZZ:86–97).

The tariff check intersects applicability/date coverage and filters all shared area-key names (P:2031–2037). If city customer classes are a different vocabulary from law classes, use distinct column names and have the comparator map them, as R16 requires. Coverage over multiple unshared law dimensions is not a substitute for the area's applicability semantics.

A seed's identity is table + state/service + applicability sets/jurisdiction + area key + effective_from (P:2408–2420); UUID is not seed identity. Same identity with changed document/end/citation/kind/version refuses. Ordering of applicability sets is immaterial, and parsed-JSON equality intentionally regards equal numeric scale as the same law (R20). A close must be performed separately before reseeding its changed end. Numeric date spellings remain the explicitly recorded R21 limitation. None of these template choices prevents the two consumers, but they are contracts the consumer migrations must implement explicitly.

## Integrity review beyond the changed lines

- **Validator:** union selection is safe for schemas accepted by the discriminator restriction: one distinct required const selects exactly one object branch. `$ref` chains/missing targets and unsupported siblings/keywords fail registration. Recursive refs traverse finite document depth; union dispatch itself adds no depth. Component-id uniqueness and number/control/null rules are extra convention rules, not pure JSON Schema semantics (P:811–865; L:257–311). No new accepted-schema counterexample admitting a schema-invalid document was found. S1 is a rejection inconsistency with the documented spelling.
- **Numbers/Unicode/parser:** numeric validation uses numeric comparisons, not floating point; stored canonical scale supports reproducible fingerprints. Representability checks precede duplicate-key parsing, including escaped keys and nested objects (P:881–893). Exponent and negative-zero normalization boundaries are disclosed in R20; the loader is stricter about written spellings. No claim that Python and PostgreSQL are identical on every possible string/schema is inferred from the corpus.
- **Facets/dynamic SQL:** values are bound or `%L`-quoted, identifiers `%I`-quoted and tables/hooks are platform-configured regclass/regprocedure values (P:1907–1932,2031–2103). Row preparation merges only declared non-key/non-template facets after checks (P:1669–1685,1880–1904). No tenant-supplied SQL injection path identified. Scoped vocabulary immutability and correct tenant scope still belong to areas.
- **Close/freeze:** advisory locks pair closes/floors with citation rereads and schema freezes with row/inputs preparation; stronger isolation levels are refused. Tariff comparison obtains locks and repeats its full read, bounded at five attempts (P:2046–2090). Profile locking, later law, tariff-under-close behavior and retry/deadlock boundaries remain R5/R6/R17/R18, not newly solved races. RC1–RC7 require evidence that the second session waited; these were reviewed, not run.
- **Core/RLS/audits:** the patch adds invoker functions, explicit grants, append-only findings/dispositions and tenant-checked subjects/rule rows (P:2853–2934,2996–3023). The core cannot manufacture trigger-depth context through TEMP/CREATE in the intended grants; materialized-view/default-ACL checks complement tenant-table checks (P:3055–3119). p05/p08 test relevant role paths. Session identity via app.user_id remains the existing application trust boundary (R1), not a new authentication scheme. No cross-tenant read/write path identified under those assumptions.
- **Fingerprint:** core inputs are schema/role checked, version locked and hashed by the database (P:2709–2760). R15 requires PostgreSQL JSONB text semantics for a writer-supplied confirmation hash; R19 requires the area to make the record append-only. Neither record immutability nor arbitrary owner DDL safety is supplied by this INSERT trigger alone.

## Test assessment

The five r6 isolated cases add useful coverage: they distinguish required-key presence, bound presence, positivity and integer bounds from neighboring checks (B:242–258). B:T1n–T1p also checks delegated facet compatibility on registration and later-version use; the latter tries a nondelegated row, so it specifically tests the unconditional delegated dry-run. B:P3c2/P3c3 at 916–921 uses an unbounded parameter so a finite range does not mask infinity refusal.

**It is not established that every guard has a case only that guard can refuse.** Concrete gaps remaining are S1's referenced discriminator, S2's same-name replacement trigger, and migration/branch cases N1/N2. p06/p10/p11/p12 supply those cases for operator execution. p12 also separates initially reserved-name collision from later wrong-identity acceptance. S1 can survive the existing positive R3i case because R3i references only the citation. S2 can survive T1l/T1m because the fake trigger retains the exempt name and ALWAYS state.

W4 does what the README now says: examples plus single-edit mutations, reference validator **plus fixed convention rules**, compared with SQL (L:462–537). It also checks file/registry schema equality via `tests/v5.4.2-17/lawfiles-17.sh`. It does not generate new schemas, exhaust combinations of `$ref`/unions, or exercise facet extraction/table registration. Thus neither S1's schema transformation nor N1's schema/facet mismatch is disproved by W4. W3 at L:544–565 checks two seed results, document equality and extra stored IDs; it does not recreate a complete YAML file from every column of every database row.

The mutation harness's phrase-sensitive APPLY behavior holds (mutations-17.py:517–524), and all 165 transformations are applicable. Mutation execution is not included in tests/ci.sh:79–91; no kill count was verified. PostgreSQL apply, concurrency, role enforcement and the SQL half of reference agreement remain outstanding operator checks rather than assumed successes.

## Operator probe manifest

Every file starts with the result that would prove a defect. All are **pending**, self-contained, transaction-scoped and restricted to a `codex%` clone. p01–p05/p07/p08 retain the earlier regression cases with r6 provenance; p06/p09 update fixed outcomes and edge cases; p10–p12 add this round's targeted cases.

| File | Purpose / expected r6 result |
|---|---|
| `p01-delegated-branch.sql` | Annotated/reordered/whole-branch refs pass; impossible/extra delegated constraints refuse. |
| `p02-strategy-version.sql` | Required positive bounded versions across lone/ref/array/union contexts. |
| `p03-seed-null-coercion.sql` | Malformed applicability cannot reseed an existing wildcard row as a no-op. |
| `p04-registration-and-freeze.sql` | Facet physical mismatch and prefilled adoption refuse; ordinary freeze retains hash, scale rewrite refuses. |
| `p05-core-invariant.sql` | Materialized-view column grants/schema CREATE caught; core/app seed execution denied; TEMP/CREATE false. |
| `p06-blank-area-key.sql` | Direct insertion and adoption of blank key refuse; initial blank legacy registration succeeds (N2). |
| `p07-depth-and-json-parser.sql` | Depth 64/65 boundary; escaped duplicate/NUL/surrogate negatives; valid supplementary pair. |
| `p08-audit-subject-rls.sql` | Core own subject accepted, invisible cross-tenant subject refused, app finding insert denied. |
| `p09-published-infinity.sql` | `inf`, `+Infinity`, `-inf`, NaN refused as value/min/max; finite unbounded value succeeds. |
| `p10-property-references.sql` | Citation ref positive; `governs` ref produces predicted S1 DEFECT notice; cyclic/union-valued citation negatives refuse. |
| `p11-facet-branches-and-adoption.sql` | Other-branch facet mismatch refuses at write (N1); adopting table with unstorable delegated facet refuses at registration. |
| `p12-trigger-order-and-identity.sql` | Odd names ordered correctly; statement/AFTER triggers allowed; initial reserved name collides; later wrong-history replacement produces predicted S2 DEFECT notices and permits history edit. |

Database probe execution and its outputs should be appended below. A setup or unrelated SQL error is not confirmation of a finding; distinguish it from the stated diagnostic/DEFECT result. The verdict is **ready on source review**, with S1/S2 should-fixes and the execution limitation stated above.

## Operator outputs

*Appended by the operator, 2026-10-09, after the review was written.* All twelve probes were run with `psql -X -q -At` on a fresh clone of `tally` with the frozen r6 patch applied strictly (md5 `e56f3501…`). The clone was dropped afterwards. The first pass filtered NOTICE lines and missed the probes that report through them; the table below is from the second pass, with notices shown.

| Probe | Result |
|---|---|
| p01-p05, p07, p08 | no FAIL or DEFECT; `tally_core` false/false for TEMP and CREATE; the astral pair parses |
| p06 blank area key | direct insert refused (22023); blank legacy adoption refused (22023); **`NOTE: blank legacy key survived registration`**: N2 reproduced |
| p09 published infinity | no DEFECT; the finite control (1.25) publishes |
| p10 property references | referenced `citation` registers; cycle and union-valued citation refused; **`DEFECT: documented referenced governs refused`** with "a oneOf needs exactly one property that every branch requires with a string const": S1 reproduced |
| p11 facet branches and adoption | a schema-valid other branch hits the incompatible facet at row preparation (22000, fails closed): N1 shown; the adopting registration is refused for the NOT NULL facet column (42P16) |
| p12 trigger order and identity | `0_early`, `A_early`, `_early`, `rule_row_historx` allowed; `rule_row_history_`, `rule_row_inseru`, `z_late` refused; reserved name on another event collides at registration (42710); **`DEFECT: assertion accepted history trigger on INSERT with wrong function`** and **`DEFECT: history edit accepted after misconfigured migration`**: S2 reproduced |

S1, S2 and N2 are reproduced; N1 is shown. The verdict stands: ready, with S1 and S2 as should-fixes.
