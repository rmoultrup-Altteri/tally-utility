# v5.4.2-17 round 5 — Codex review

**Verdict: ready, on source review. No blocking finding identified.** The r4 blockers and should-fixes are addressed, and the r2 fixes still hold. This is not a claim that the database tests passed: database execution is delegated to the operator, and all nine probes below are **pending**. Two nonblocking should-fixes remain: align direct-insert area-key validation with lookup/seeding, and refuse infinities in published numeric values.

## Scope, provenance and execution

I read the brief and verified both frozen artefacts before inspecting the implementation:

| Artefact | Observed MD5 | Result |
|---|---|---|
| `tests/v5.4.2-17/review/patch-17-frozen-r5.sql` | `d20d453c0aaecadb79ffdc0852d8cb56` | Matches |
| `tests/v5.4.2-17/review/battery-17-frozen-r5.sql` | `ea9bb460c10534fce95b9c5883e48904` | Matches |

References below use **P** for the frozen r5 patch, **B** for the frozen r5 battery, **L** for `tools/law/lawc.py`, and **ZZ** for `law/fixtures/zz/fixture-zz.sql`. Thus `P:523` means `tests/v5.4.2-17/review/patch-17-frozen-r5.sql:523`. Battery case names supplement line citations where useful.

Reviewed the inventory including its amendments, adopted convention, r2/r4 Codex findings and r4 dispositions, frozen SQL, fixture schemas/law/examples/seed, loader and dependency pins, isolation fixture/runner, race runner, mutation harness, README, CI runner/workflow, relevant -13/-15 definitions, and -16/base-schema locking and isolation patterns. I did not change implementation, frozen artefacts, or existing tests.

**Execution boundary:** the sandbox cannot reach Docker. I did not invoke Docker, connect to a database, create a database, or attempt an alternative database service. In particular, I did not touch `tally` or `postgres`. All requested new database work is supplied as self-contained SQL files under `tests/v5.4.2-17/review/codex-r5-probes/`, guarded to run only in a database whose name begins with `codex`.

**Completed local checks:**

- `lawc.read_law_file` accepted all **3** ZZ law rows.
- `lawc.emit` exactly matched the committed `zz_fee_rules.seed.sql`.
- `fixed_rule_errors` refused NUL, a lone surrogate value, and a lone surrogate key; accepted a valid supplementary-plane character.
- All **147** mutation transformations found their anchors in the frozen r5 patch. This checks harness applicability, not mutation detection.
- Shell syntax checks passed for CI, isolation, race and law-file runners.

An initial loader invocation used a nonexistent filename; after discovering the actual fixture filename, the checks above ran successfully. No implementation failure is inferred from that invocation.

**Not executed:** strict application/reapplication, frozen SQL battery, database half of W3/W4, isolation cases X1–X6, races RC1–RC7, mutation executions, tenant/core invariant execution, or the new SQL probes. There are no operator outputs in this review yet. SQL behavior described as predicted is derived from source, not presented as an observed database result.

## Blocking findings

**None identified in this round.** No remaining counterexample was found for the r4 registration guarantees or the r2 registration/depth guarantees. The readiness verdict covers the reviewed implementation and recorded residuals; operational verification remains pending rather than silently counted as passing.

## Should-fix findings

### S1 — Direct inserts can store an area key that lookup and seeding refuse

**Evidence:** registration checks area-key columns for NOT NULL text at `P:1555–1563`. The row preparation/insert path at `P:1714–1889` does not call `rule_key_check` or impose its nonblank-key predicate. Conversely, `rule_key_check` rejects a value without an alphanumeric character at `P:2362–2367`, and law lookup, tariff lookup and seed use that helper (`P:2139`, `P:2218`, `P:2284`).

**Predicted reproduction:** on a minimal registered law table without an area-specific vocabulary CHECK/FK, insert a valid delegated document with `customer_class = ''`. The row satisfies the generic template and is stored. Passing that same key to `rule_key_check` is refused with `22023`; the shared lookup cannot address the stored row by its key. Probe **p06** contains the complete setup and both operations.

**Impact/severity:** unusable rows and inconsistent write APIs, not a wrong-row lookup or tenant leak. The -13/-15 consumer keys have area vocabularies, and their migrations can exclude this independently. That makes this a should-fix, not an obstacle to adopting the machinery.

**Suggested change:** apply `rule_key_check` to the actual area-key projection in preparation, or install equivalent key CHECKs at registration. Cover both direct law insertion and application-written tariff insertion, with an otherwise valid document and envelope so only the key check can refuse.

### S2 — Published numeric values exclude NaN but not infinities

**Evidence:** `rule_parameter_values.value` is unconstrained `numeric`; its special-value CHECK excludes only NaN (`P:2474`). The insertion guard likewise excludes only NaN, then checks optional bounds (`P:2526–2536`). A parameter may have neither bound (`P:2423–2436`). There is no subsequent finite-value check in `rule_parameter_value_as_of` (`P:2551–2581`).

**Predicted reproduction:** register a national USD parameter without bounds, then insert positive and negative numeric infinity over nonoverlapping dates. The displayed guards accept both, and lookup returns the stored infinity. Probe **p09** supplies exactly that setup.

**Impact/severity:** a reviewed migration can record a nonfinite amount/rate where consumers expect an exact finite decimal. This is not a tenant-writer escape: the tables are platform-only, and finite two-sided bounds prevent the example. The patch explicitly promises “never NaN,” so this is a missing domain guard, not evidence that its existing NaN guard is bypassed. I classify it as nonblocking hardening before a consumer reads these values into decimal arithmetic.

**Suggested change:** explicitly refuse both infinities as values and as non-NULL parameter bounds. Keep NULL as the representation of an unbounded range. Test each special value independently of the range checks.

## Round-4 findings and adjacent cases

| r4 finding | r5 assessment | Evidence and pending probe |
|---|---|---|
| B1: impossible delegated branch can register | **Fixed in source.** The complete branch is compared with the standard shape, including the `governs` schema and exactly two required keys. | `P:990–1017`; B:R3d–R3g at `B:215–229`; p01. |
| B2: a lone strategy need not name its version | **Fixed in source.** The rule is on every object with a `strategy` property, independent of the discriminator that selects it. | `P:517–540`; B:R4q/R4r at `B:230–240`; p02. |
| S1: malformed applicability matches wildcard seed | **Fixed in source.** The complete envelope is required, then both sets are checked as null/arrays of strings and jurisdiction as null/boolean before matching. | `P:2263–2283`; B:T4n cases at `B:510`; p03. |
| S2: lone-surrogate keys escape the Python check | **Fixed; locally exercised.** Keys now pass the same surrogate check as values. | `L:290–291`; W5 surrogate checks in `tests/v5.4.2-17/lawfiles-17.sh`; local results above. |
| S3: adoption instructions name the permanent insert hook | **Fixed.** R14 explicitly identifies `p_adoption_check`, run once on the empty-document transition. | `P:3089–3095`; actual call remains at `P:2065–2066`. |

**Delegated-branch details.** Removing `title`, `description` and `$comment` at both branch and property levels preserves annotations (`P:998–1011`). Required-array containment plus length accepts either ordering; property object order is irrelevant to JSONB equality. The registry resolves a branch `$ref` before testing it (`P:985`), so referencing the whole standard branch remains valid. Omitting the optional `note` property is permitted. p01 exercises all of these positive shapes and the three negative constraints from r4. Property-level references inside the standard branch are not normalized by this exact-shape rule; the README deliberately specifies that narrower branch syntax (`law/README.md:89–100`). I do not treat an explicitly excluded spelling as a validator-acceptance defect.

**Strategy-version reachability.** Definitions are inspected independently (`P:625–635`), properties and array items recurse (`P:497–500`, `P:542–548`), and each union branch is inspected (`P:464–475`). Therefore a strategy reached through a `$ref`, array item, or union discriminated by `mode` still reaches the new object check. The version schema itself is resolved (`P:528`), allowing a referenced bounded integer. p02 covers these forms, including a positive version-2 document. Integer bounds, positive minimum and ordered range remain enforced. The rule requires the version field; it does not force each strategy to have only one version in a terms-schema version.

**Seed NULL behavior.** Missing keys are refused before the type check, so SQL NULL from a missing JSON field cannot skip it. JSON null is deliberately “every one.” Scalars, objects, null array elements, numeric array elements and string spellings of jurisdiction cannot be reinterpreted as wildcard. Empty/duplicate/unknown sets are then refused by `rule_applicability_span` (`P:1294–1311`). p03 includes malformed values against an already stored all-applicability row, where the old bug could silently return its ID, not merely against an empty table.

## Round-2 findings and r3/r4 regression review

“Held” here distinguishes source confirmation from unexecuted database confirmation.

| Prior finding | Did the fix hold in r4? | Does it hold in r5? |
|---|---|---|
| B1: allowed facet type stored in a different allowed column type | Yes. | **Yes.** Exact declared/physical pairings at `P:1448–1461`; checked for all registered versions at registration (`P:1613–1615`) and the row's version during preparation (`P:1773–1779`). Numeric typmods cannot round facets. B:T1g/T1h and p04. |
| B2: unions consume document depth | Yes. | **Yes.** Selected branch reuses `p_depth` (`P:689–692`), object/array children increment it (`P:710–711`, `P:731`). B:V24 and p07 cover recursive union/reference boundaries at depth 64/65. |
| B3: prefilled documents bypass adoption validation | Yes. | **Yes.** Any preexisting non-NULL document/source/kind/version rejects adopting registration (`P:1602–1609`). B:A1e at `B:761`; p04. |
| NUL and surrogates | NUL and surrogate values held; surrogate keys were r4 S2. | **All named cases now covered.** Local Python checks pass; PostgreSQL representability is handled before duplicate parsing (`P:862–868`). p07 exercises parser-side refusal and a valid surrogate pair. |
| Reusable core invariant | Yes. | **Yes in the intended two-assertion architecture.** Owner-only `assert_core_role_invariants` at `P:2938–3004`, called in the patch and separately at CI's end (`tests/ci.sh:90`). All core role memberships are forbidden; effective privileges are examined. p05. The old tenant assertion alone is not claimed to incorporate it. |
| Freeze can change schema text without changing its hash | Yes. | **Yes.** Non-freeze fields compare as text at `P:944–945`; an ordinary freeze stamps only freeze fields. B:R8c at `B:587–589`; p04. |
| Isolated guard cases | Named old gaps addressed. | **Still addressed.** B:V10b/V13b (`B:345–350`), V24, T1h and A1e; RC6/RC7 exercise core-input freezes in both orders (`tests/v5.4.2-17/races/rule-close-17.sh:16–20,126–139`). This is not a universal coverage proof. |
| APPLY counts any apply failure as success | Fixed. | **Still fixed.** A failing apply must contain the case's required phrase; other apply errors are misses (`tests/v5.4.2-17/mutations-17.py:471–482`). All anchors matched locally; actual kills were not run. |

The separate adoption hook still preserves the useful r3 distinction: it compares old content once, while later rows need only the permanent insertion hook (`P:1852–1854`, `P:2065–2066`). The r5 change did not move the equivalence check back onto all new rows. The supplied document is checked against `terms_source`, including on adoption (`P:1740–1744`, `P:2064`).

## Inventory traceability

**Held** means supported by inspected code/format, not an observed database pass. **Residual** means expressly stated unfinished work; it does not mean implemented. No Step-2 requirement is silently treated as Area work below.

| Requirement | Disposition | Evidence / boundary |
|---|---|---|
| V1 | Held | Schema registry, immutable version/role, stamped hash, one-way freeze: `P:890–1050`. |
| V2, Step-2 table pinning | Held | Table-kind CHECK plus registry FK: `P:1642–1644`; kind role pinned at `P:973–978`. Actual consumer kinds remain Area. |
| V3 | Held for supported schema and fixed rules | Type/keyword checks `P:385–640`; document interpreter/fixed rules `P:644–845`. Closed objects, null refusal, bounds, arrays, uniqueness, ids and rationals expressible through typed fields. Rational legal arithmetic is core work. |
| V4 | Held | Single required const discriminator and distinct values at `P:345–373,457–486`; selected branch validation `P:670–692`; no vocabulary table reads in the interpreter. |
| V5 | Held | Every strategy-bearing object requires bounded positive integer version: `P:517–540`; p02. |
| V6 | Held as authoring/schema format | Per-section citations in `law/README.md:69` and ZZ schemas/examples. Area schemas decide the legal section boundaries and required citations. |
| V7 | Held | Explicit `unruled` can be a schema enum; no nulls or silent defaulting: `P:666–667,700–712`. |
| V8 | Held | Mandatory exact cited delegated branch: `P:979–1018`; p01. |
| V9 | Held within documented subset | Per-type/node keyword allowlist and recursive schema checks: `P:413–442,598–640`. Unsupported features fail registration rather than being ignored. |
| V10 | Held mechanism; execution pending; R7 limits proof | W4 discovers schema files and checks registry equality, then `L:520–537` compares reference-plus-fixed-rules against SQL on the corpus. |
| F1 | Held; R9 fixes each table's facet set | Immutable same-transaction facet declarations `P:1053–1159`; derived values/writer agreement `P:1762–1790`; history whole-row comparison `P:2024–2025`. |
| F2 | Held | Text, text array, integer, boolean, plus numeric/presence facets: `P:1161–1207`; physical pairings `P:1448–1461`. |
| F3 | Held mechanism | Vocabulary table/column/scope checked `P:1126–1146`; quoted scoped lookup on every write `P:1791–1815`. Area owns vocabulary stability and tenant scope. |
| F4 | Held hook | `insert_check(jsonb)` signature `P:1624–1627`, called with complete prepared row `P:1852–1854`. |
| F7 | Held pattern | Governing-row citation followed by component-membership check in `ZZ:79–104`. |
| T1 | Held template; S1 is key-input consistency gap | Registration/envelope/exclusions/triggers `P:1463–1690`; close guard/floor `P:2000–2087`. Area must supply a complete citing-record floor. |
| T2 | Held | Immutable applicability ordinals and explicit set spans `P:1224–1342`; derivation `P:1830–1837`; overlap exclusion `P:1655–1656`. |
| T3 | Held helpers | Profile plus exact key/date resolution, absent/ambiguous refusal `P:2123–2170`. Premise-to-system selection is upstream -16/area work. S1 affects otherwise unaddressable invalid keys, not fallback selection. |
| T4 | Held protocol; runtime pending | Close locks exclusive before floor read `P:2033–2042`; citation locks shared before reread `P:2105–2119`; READ COMMITTED enforced. RC1/RC2 cover both orders. |
| T5 | Held for documented identity | Whole-envelope/type checks `P:2260–2283`; set/key/start matching and strict supplied-column comparison `P:2297–2340`; p03. |
| T6 | Held mechanism; R14 area sequence | Empty-document registration rule `P:1590–1610`; migration-only one-time fill and equality hook `P:2047–2075`. |
| U1 | Held template | Tariff tenant/system envelope, FKs, exclusion, canonical FORCE RLS/grants `P:1543–1549,1660–1676`; common validator/history. |
| U2 | Held | Original JSON text must pass recursive unique-key predicate before returning JSONB: `P:850–883`; called in preparation at `P:1732`. p07. |
| U3 | Held comparator/audit infrastructure; residuals R5/R6/R12/R16/R17/R18 | Profile/law range coverage, lock/reread and comparator `P:1892–1997`; later-law finding kind `P:2682–2684`. Core audit execution is not built. |
| U4 | Held pattern | Correct-law citation helper `P:2176–2197`; optional tariff resolution `P:2200–2236`; required law and optional tariff on records `ZZ:65–104`. |
| P1 | Held typed value mechanism; residuals R4/R10; S2 hardening | Parameter units/scopes/ranges and immutable dated values `P:2391–2581`. Class dimension explicitly amended out; citation floor explicitly awaits the first citing area. Nonfinite values need S2. |
| P3 | Held format/helper | Published-name reference format at `law/README.md:71`, optional parameter-vocabulary facet; exact-scope dated lookup `P:2551–2581`. |
| C1 | Held role/boundary; residuals R1/R8 | NOLOGIN role and explicit grants `P:188–234`; reusable privilege assertion `P:2938–3004`; ordinary tenant RLS retained. Login identity/provisioning remains first-core-area work. |
| C2 | Held grant pattern; R1 identity | `ZZ:125–137` demonstrates core-only insertion and common read access. Moving -13/-15 tables is intentionally Area work. |
| C3 | Held; residual R13 | Append-only tenant findings/dispositions, subject and rule-row checks, missed-decision pairing, stamps: `P:2692–2908`. Durable polymorphic subject references remain area responsibility. p08. |
| C4 | Held intended typed-column pattern; R15 serialization | `P:2592–2643`: schema-role/version validation, READ COMMITTED, schema lock/freeze check, canonical-number validation and database SHA-256. |
| L1 | Held amended format | Table/state/service file format, explicit applicability and scenario shape: `law/README.md:13–46`, `L:336–400`. Scenario presence remains optional in this tooling. |
| L2 | Held | Strict YAML/JSON loaders `L:71–129`; schema-directed typing `L:207–234`; exact decimal serialization `L:141–179`; emitter `L:403–416`; surrogate-key repair verified locally. |
| L3 | Held CI structure; runtime pending; residual R11 | Workflow builds PG16 and invokes `tests/ci.sh`; W1–W5 cover files/seed/document roundtrip/agreement/strict loading. Scenario schemas/execution await core types. |
| L4 | Held fixture coverage | Three schemas, multiple strategies, municipal-bound and delegated law rows, scoped vocabulary, tariff/comparator, component citations and core records in `law/fixtures/zz/`. |

F5/F6, U5, P2/P4 and consumer-specific kind rows are Area/no-work entries. T7 is explicitly Out and recorded as R2. P1's close floor is **not implemented now** (R4); unlike class scope, this is a stated patch residual rather than an inventory amendment. L3 scenario schema checks are amended to shape checks pending the core (R11). These distinctions remain visible rather than being counted as finished guards.

## Suitability for -13 and -15

**The -13 migration can use this machinery.** `customer_class` and `cause` are already NOT NULL text (`sql/v5.4.2-13-backbilling-caps.sql:678–679`). Add the envelope/applicability columns, establish their correct spans, register with an adoption equivalence function, replace the old history guard in the same reviewed migration, and fill each old document once. Equivalence must compare both old columns and child window terms; the generic hook cannot establish that the area's comparison is complete. Preserve row IDs/dates and install the complete citation floor and correct-law citation calls. Replace the old exclusion when distinct owner/system/jurisdiction rows are needed: keeping it alongside the new exclusion can still over-restrict rows. R14 now names the correct hook.

**The -15 rewrite can use the template and facet mechanisms.** Its current `customer_class` and `basis` keys fit the text/equality pattern (`sql/v5.4.2-15-deposits-law-to-core.sql:469–470`). The F3 vocabulary hook, F4 complete-row check and F7 component-membership pattern support the listed reference-integrity needs. The rewrite must explicitly move core-only records/grants, add inputs schemas, and carry over record integrity while moving legal evaluation into strategies. It is not a drop-in migration of the existing draft.

The questioned template choices are sound within their stated contracts:

- **Applicability sets:** NULL means every value; nonempty validated sets become overlapping multiranges. An all-owner row and a narrower row for the same key/date overlap and are refused, rather than introducing an implicit precedence rule. That is appropriate for deterministic lookup.
- **Area key:** NOT NULL plus equality avoids NULL escaping the exclusion. “Every customer class” requires explicit rows or moving that distinction out of the area key (R3). S1 asks only that direct writes obey the helper's existing nonblank predicate.
- **Law always, tariff optionally:** city-owned systems cite a delegated law row, and the tariff supplies their policy. A missing tariff under delegation remains a core decision refusal; the ZZ citing-component guard also prevents pretending the delegated row contains a charge component.
- **Tariff/law shared keys:** matching identically named columns prevents comparing residential tariff with unrelated commercial law. A tenant-owned class vocabulary must use a different column name if it is not the law's vocabulary. R16 then puts mapping/comparison on the area. The union of candidate law dates is not proof of coverage of every unshared legal dimension; the area comparator must enforce its intended mapping.
- **Adoption:** one sanctioned fill preserves historical identity. It is not a legal correction or an opportunity to alter applicability, dates or old content. Registration's empty-document rule and adoption span comparison close the previous bypasses.
- **Seed identity:** state/service, applicability sets, area key and start locate the row. Parsed document, end, citation, kind/version and other supplied columns must agree. Set ordering does not matter; document numeric scale is compared semantically on reseed. Existing-row reseeding does not rerun schema acceptance or freeze checks because it creates no new row. A law change still needs an explicit close plus a new row; emitted seed SQL does not close the old row automatically.

## Integrity assessment and remaining limits

**Interpreter and parser.** I found no new concrete acceptance disagreement within the documented subset. References target named root definitions; definitions themselves are checked, chains are refused, and root references are excluded (`P:445–454,615–638`). Disjoint required const discriminators make selected-branch execution appropriate for supported unions. Unsupported standard schema constructions are rejected at registration, not partially interpreted. Numeric comparisons use PostgreSQL numeric, and Python keeps exact Decimal values. String patterns are narrowly allowed; fixed control-character and representability checks cover the reported disagreement paths. The parser checks the original text for duplicate keys, including nested objects. p02/p07 target adjacent combinations instead of claiming corpus testing proves all schemas.

**Facets/dynamic SQL.** Physical types are validated before `jsonb_populate_record`; facet names cannot overwrite template/key columns (`P:1565–1577`). Scalar multiplicity and extraction types are checked (`P:1175–1204`). Vocabulary identifiers are validated/quoted and values are quoted or bound (`P:1126–1146,1797–1807`). Hooks/tables are migration-configured; ordinary writers cannot register arbitrary execution targets. No ordinary-writer injection path was identified. Vocabulary lifetime, area predicates and complete comparator semantics remain author responsibilities.

**Close/freeze/isolation.** The cited-row handshake reads after the advisory lock. A close rereads its floor only after locking exclusively and uses a role that sees all tenants for law rows. The tariff algorithm rereads after newly acquired law locks until its selected set was already locked before the read (`P:1924–1972`); it fails closed on excessive churn. Core inputs share the schema-freeze lock and require READ COMMITTED (`P:2613–2628`). Profile coverage is not locked (R5); later law and close-under-tariff changes are audit obligations (R6/R17); lock-order retries/deadlocks are R18. None is misrepresented as prevented by this patch. I did not experimentally verify either race order.

**Core privileges and RLS.** Functions added by the patch are invoker-rights; no new trigger-depth bypass was found. Role membership, dangerous attributes, materialized-view access including column grants, direct default privileges, and effective TEMP/database/schema CREATE are asserted (`P:2946–2995`). Migration helpers and assertions are owner-only (`P:2928–2931,3003`). Existing invoker-view and tenant-policy invariants remain checked through AC-32. The new invariant is a separate required final assertion, which CI actually calls. No cross-tenant reach was identified from the inspected public-table/function grants. p05/p08 exercise specific role-boundary cases as well as the privileged assertion.

**Findings and inputs.** Subjects are resolved only to ordinary/partitioned public tables with id/tenant columns, then queried under caller RLS and compared with the finding tenant (`P:2760–2779`). Tariff references must match that tenant; schema identity is stamped from the cited row (`P:2781–2801`). Dispositions are tenant-linked and append-only. R13 correctly states the lack of a durable generic subject FK. Inputs are validated against an unfrozen inputs-role schema, and the fingerprint is computed over the stored JSONB representation rather than trusted from the writer. Areas still must use the documented typed input columns and append-only table/grant pattern; this trigger is not a replacement for registering an area's record structure.

## Test assessment

**Does every guard have a case only it can refuse? No universal proof is established.** The specific r2 gaps are now covered by isolated cases, not merely by error-list changes. r5 adds R3d–R3g, R4q/R4r, malformed seed cases and the surrogate-key check. However, the shipped battery does not comprehensively combine the new version rule with referenced objects, array items and differently selected unions; p02 addresses that gap. Direct blank keys and nonfinite published values are not isolated refusal tests today (p06/p09 are expected to demonstrate acceptance).

The mutation harness improves confidence in the named checks, with 147 locally verified anchors and required APPLY phrases. It does not execute as part of the ordinary `tests/ci.sh` sequence, and I have not established any kill count. Some mutations are detected through a changed diagnostic rather than uniquely demonstrating acceptance of bad data. Neither the number of mutations nor an all-pass battery proves every predicate independently necessary.

**W4 proves its stated finite-corpus claim, if run successfully.** The runner discovers each schema file, requires examples, verifies registered-schema equality, and compares SQL acceptance with Draft 2020-12 **plus fixed convention rules** (`tests/v5.4.2-17/lawfiles-17.sh:45–63`; `L:462–537`). It is not pure standard-schema acceptance: canonical numbers, control characters, depth and component IDs are extra conventions on both sides. Its mutations edit documents under existing schemas; they do not generate arbitrary schema combinations. Boundary values are a fixed replacement set plus selected numeric deltas, not exhaustive min/max-derived boundaries. README/R7 accurately limit the claim.

W3 establishes semantic stored-document equality, seed idempotence and no extra rows in participating seeded tables (`L:544–565`). It does not recreate complete YAML files from stored rows or validate scenario meaning. Scenario presence is optional, and their inputs/expected outputs are only nonempty mappings until core types exist (R11). Future area acceptance should require meaningful scenario coverage without confusing the present shape check with legal evaluation.

## Operator probe manifest

Run each file independently with psql's error-stop behavior on a **codex-prefixed clone already containing the frozen r5 patch**, as the migration owner. The files also set `ON_ERROR_STOP`, check the database prefix, set a statement timeout, and wrap their objects/rows/grants in a transaction ending in **ROLLBACK**. They contain their own setup: no ZZ fixture loading, includes, other probe execution, Docker invocation, or database creation is needed. The clone's TEMP ACL must have been corrected as the brief specifies. Run without an outer transaction because each file owns its transaction.

A FAIL/SQL error in a regression probe needs inspection of the actual SQLSTATE/message; setup errors are not automatically product defects. p06 and p09 deliberately print **DEFECT** result rows if the two predicted should-fixes reproduce. Role-sensitive operations in p08 use `tally_app`/`tally_core` and an explicit `app.user_id`; migration-only registration/seeding probes correctly run as owner. p05 checks effective privileges and executes its simple privilege inspection as `tally_core`.

| File in `tests/v5.4.2-17/review/codex-r5-probes/` | Purpose | Expected r5 result | Execution |
|---|---|---|---|
| `p01-delegated-branch.sql` | Annotated/reordered/referenced delegated branch; omit note; reject extra constraints | Positive variants pass; named negatives refuse | Pending |
| `p02-strategy-version.sql` | References, array items, union selected by another discriminator; referenced valid version | Versionless forms refused; valid versioned reference accepted | Pending |
| `p03-seed-null-coercion.sql` | Malformed/missing applicability against existing wildcard row | Type/envelope/set refusals; explicit null reseed returns same ID | Pending |
| `p04-registration-and-freeze.sql` | Facet column mismatch, filled adoption, scale-edit freeze | Named refusals; ordinary freeze hash remains correct | Pending |
| `p05-core-invariant.sql` | Materialized-view column grant, nonpublic CREATE, migration helper privileges | Invariant catches grants; core has no TEMP/CREATE or seed EXECUTE | Pending |
| `p06-blank-area-key.sql` | S1 direct insertion vs shared key validation | DEFECT row then expected lookup-contract refusal | Pending |
| `p07-depth-and-json-parser.sql` | Recursive union depth 64/65, escaped duplicate key, NUL/surrogate handling | Boundary/parser checks pass; valid astral pair parses | Pending |
| `p08-audit-subject-rls.sql` | Core own/invisible subjects, app write denial, tenant filtering | Own subject accepted; foreign subject/app write refused; one visible subject | Pending |
| `p09-published-infinity.sql` | S2 infinite published values with no numeric bounds | DEFECT rows and infinite lookup result | Pending |

These single-session probes do not replace the existing multi-session race suite. I have requested no additional ad hoc database operation outside these files. Results can be appended below; readiness should be reconsidered if a regression probe reveals an unexpected acceptance/refusal or operator execution exposes a blocking defect.

## Operator outputs

*Appended by the operator, 2026-10-09, after the review was written.* All nine probes were run with `psql -X -q -At` on a fresh clone of `tally` with the frozen r5 patch applied (md5 `d20d453c…`, applied strictly). The clone was dropped afterwards.

| Probe | Result |
|---|---|
| p01 delegated branch | no FAIL printed |
| p02 strategy version | no FAIL printed |
| p03 seed NULL coercion | no FAIL printed |
| p04 registration and freeze | no FAIL printed |
| p05 core invariant | no FAIL; `tally_core` shows false/false for TEMP and CREATE |
| p06 blank area key | **`DEFECT: stored key rejected by lookup contract`**: S1 reproduced |
| p07 depth and parser | no FAIL; the astral pair parses (`{"x": "😀"}`) |
| p08 audit subject and RLS | no FAIL; `tally_core|t` |
| p09 published infinity | **`DEFECT: nonfinite published value`** for `Infinity` and `-Infinity`: S2 reproduced |

p01-p05, p07 and p08 printed no FAIL, so the r4 regression and adjacent cases hold. S1 and S2 are both reproduced. The verdict stands: ready, with S1 and S2 as should-fixes.
