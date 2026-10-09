# v5.4.2-17 round 4 — Codex review

**Verdict: not yet.** Two registration-format guarantees remain incomplete: V8 can register a law schema that admits no delegated document (B1), and V5 can register an unversioned single-strategy document (B2). These are static SQL findings with runnable probes below, not claimed database reproductions. The three round-2 blockers are fixed in the inspected source.

## Scope, hashes and execution limits

Read the brief, then verified the frozen artefacts **before reviewing implementation or attempting database work**:

| Artefact | Observed MD5 | Result |
|---|---|---|
| `tests/v5.4.2-17/review/patch-17-frozen-r4.sql` | `ad7045b9e680af4ca0f72212013a7cd5` | Matches; 3,080 lines |
| `tests/v5.4.2-17/review/battery-17-frozen-r4.sql` | `a24cdfb2cf48d8ec9e137468d26e84c1` | Matches |

The brief supplies no expected hashes for the other listed files, so no hash agreement is asserted for them. Those files were reviewed as present in this checkout. Abbreviations below: **P** = frozen r4 patch; **B** = frozen r4 battery; **W** = `tests/v5.4.2-17/lawfiles-17.sh`; **M** = `tests/v5.4.2-17/mutations-17.py`; **L** = `tools/law/lawc.py`; **ZZ** = `law/fixtures/zz/fixture-zz.sql`. `P:980`, for example, means line 980 of the frozen patch, not the working SQL patch.

The prescribed first clone command, `docker exec tally-pg psql -U tally -d postgres -c 'CREATE DATABASE codex17 TEMPLATE tally'`, failed before connecting:

```text
permission denied while trying to connect to the docker API at unix:///Users/ryanscomputer/.docker/run/docker.sock
```

This session cannot request elevated execution. No database was created, patched, seeded or dropped; no database cleanup remains. Neither `tally` nor `postgres` was modified. Database apply/reapply, battery, isolation, races, W3/W4 database comparison, and mutation execution are **unverified in this review**. A prior review's successful runs are not substituted for new execution.

Completed locally, using the prescribed virtualenv with bytecode writes disabled:

- `lawc.py check law/fixtures/zz/zz_fee_rules.yaml`: three rows valid.
- `lawc.py emit ... | diff - law/fixtures/zz/zz_fee_rules.seed.sql`: no difference.
- All three fixture schemas pass the installed Draft 2020-12 meta-schema check.
- Reference-only evaluation using W4's exact example-name selection: inputs 107 cases (10 valid/97 invalid), law 683 (52/631), tariff 109 (11/98). This is **899 reference evaluations, not 899 database agreement checks**.
- All 139 mutation functions can transform the frozen r4 patch without an anchor error. This is not a mutation kill result.
- Shell syntax checks pass for CI, isolation, races and law-file scripts.
- Executed Python probes confirm the reference outcomes for B1/B2 and the remaining surrogate-key gap S2.

Only this review file was written in the repository.

## Blocking findings

### B1 — Registration can accept a law kind with no possible delegated document (V8)

**Evidence:** P:975–988 checks the delegated branch's property names, requires at least `citation` and `governs`, and checks the exact citation/note schemas. It does not restrict the rest of the `governs` schema. P:550–570 permits `const` together with string length bounds. The discriminator check uses the literal const, not the satisfiability of its schema (P:336–365, P:491–497).

Starting from the shipped ZZ law schema, add `maxLength: 1` to `$defs.delegated.properties.governs`. This is a valid supported JSON Schema. It retains the required, distinct `governs` const, the exact citation schema and the same optional note. Thus the SQL registration checks have no rejecting condition. However, `delegated_to_utility` cannot satisfy maxLength 1. **No delegated document can ever validate under this registered law kind.**

This contradicts inventory V8, P:137–138 and `law/README.md:70,89–98`. It matters to the first consumers: the municipality's law citation depends on the delegated branch actually being usable, not merely having a branch with that label. W4 agreement would not establish V8: both interpreters correctly reject the impossible branch.

**Runnable database probe (not executed here):** after loading the ZZ fixture in a transaction on a scratch clone:

```sql
BEGIN;
WITH s AS (
  SELECT jsonb_set(json_schema,
    '{$defs,delegated,properties,governs,maxLength}', '1'::jsonb) AS j
  FROM public.rule_term_schemas
  WHERE terms_kind = 'zz_fee' AND terms_version = 1
)
SELECT public.rule_terms_schema_errors(j) AS schema_errors,
       public.rule_terms_errors(j,
         '{"governs":"delegated_to_utility","citation":"ZZ 1"}'::jsonb)
         AS delegated_errors
FROM s;
-- Static prediction: schema_errors = {}; delegated_errors is nonempty.

INSERT INTO public.rule_term_schemas
  (terms_kind, terms_version, rule_role, json_schema,
   introduced_on, description, source_note)
SELECT 'codex_impossible_delegation', 1, 'law',
       jsonb_set(json_schema,
         '{$defs,delegated,properties,governs,maxLength}', '1'::jsonb),
       DATE '2026-10-09', 'Registration probe', 'Codex review probe'
FROM public.rule_term_schemas
WHERE terms_kind = 'zz_fee' AND terms_version = 1;
-- Static prediction: succeeds, despite no valid delegated document.
ROLLBACK;
```

The installed reference validator was actually run against this modified schema and rejected the standard delegated document. The SQL acceptance prediction follows the cited branches; it needs confirmation in PostgreSQL.

**Fix:** enforce the complete standard delegated shape, including the discriminator's constraints and exactly the required keys (note optional), or equivalently verify those structural requirements plus an admitted standard document. Add a registration refusal for this contradictory discriminator and for making `note` required. Test the guard at registration, not merely document rejection afterward.

### B2 — V5's version requirement applies only to a `oneOf` discriminated by `strategy`

**Evidence:** the version guard is exclusively inside `IF p_node ? 'oneOf'` and `IF v_disc = 'strategy'` (P:451–490). The ordinary object path (P:502–531) recursively checks property schemas without requiring a strategy object's version. A single-strategy object is a normal, useful member of the supported subset; it has no union to trigger that guard.

This schema passes the static subset rules and admits an unversioned strategy:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["fee"],
  "properties": {
    "fee": {
      "type": "object",
      "additionalProperties": false,
      "required": ["strategy"],
      "properties": {"strategy": {"type": "string", "const": "flat"}}
    }
  }
}
```

Document: `{"fee":{"strategy":"flat"}}`. Local `lawc.reference_errors(schema, document)` returned `[]`. Static prediction: `rule_terms_schema_errors(schema)` and `rule_terms_errors(schema, document)` likewise return `{}`. Register it as a new tariff kind using the same INSERT envelope as B1, with `rule_role = 'tariff'`; no law-only check intervenes. It can also be embedded in a law branch.

Inventory V5 says a strategy reference names its version so the core can reproduce old decisions. `law/README.md:67` gives the same rule. There is no residual for unversioned single-strategy objects. Requiring at least two union branches is not an adequate workaround for a decision point with just one strategy.

**Fix:** apply the strategy-reference version rule to ordinary object schemas as well as selected union branches, resolving property `$ref`s as needed. Either admit a single strategy with a required bounded integer version, or explicitly refuse the unversioned form. Add positive and negative tests for the single-strategy case; also cover strategy-bearing objects under a union selected by another discriminator. The r4 fractional-bound fix should remain.

These findings concern convention-format enforcement, **not a claim that the database misimplements ordinary JSON Schema validation for these examples**. Standard validation and the database can agree while both allow a missing convention requirement.

## Should-fix findings

### S1 — A malformed applicability value can silently match an existing all-applicability seed

P:2239–2246 now requires all envelope keys, but does not validate their JSON types. P:2269–2271 converts `owner_types` and `system_kinds` to SQL arrays only when their JSON type is `array`; every other type becomes SQL NULL, meaning every owner/system. P:2291 excludes both fields from the subsequent comparison because they were supposedly compared as sets.

For an existing law row with NULL `owner_types`, take its correct complete seed and replace `owner_types: null` with `owner_types: "municipal"` (or `{}`). The lookup still uses the universal span. If all other named values agree, the function returns the existing id. It never reaches `jsonb_populate_record`, which would otherwise validate/coerce the insertion types. The same problem applies to `system_kinds` for a universal-system row. This is a static prediction, not an executed SQL reproduction.

**Suggested test:** seed a valid wildcard row, then call `rule_row_seed` with that exact envelope and a scalar/object in each applicability field separately; require a type error. Check JSON null-or-array before lookup, with array members as strings. The normal YAML loader already rejects these forms (`L:324–332`), so this affects the independently callable, migration-only SQL seed helper rather than the shipped YAML path. That limits severity, but strict re-seeding should not silently reinterpret a malformed applicability request.

### S2 — Lone-surrogate refusal still misses object keys

The round-2 value-string fix is present at L:272–275. The dictionary loop checks keys for control characters, but not `SURROGATE` (L:289–297). Executed results:

```python
fixed_rule_errors({"x": "\ud800"})
# ['/x: a lone surrogate PostgreSQL cannot store']
fixed_rule_errors({"\ud800": "x"})
# []
```

A matching Python-side schema can therefore pass `reference_errors` with an unpaired surrogate as a property name even though PostgreSQL cannot store that schema/document. Usually a registered closed schema rejects an unknown key first, so this is tooling representability/error-reporting incompleteness, not a demonstrated SQL acceptance or tenancy bypass. Add the same surrogate test to keys and cover high/low lone surrogates plus valid supplementary characters. NUL keys are already caught by `CONTROL`.

### S3 — Adoption instructions still name the permanent insert hook

P:146–148 and residual R14 at P:3047–3054 say the old-column equality belongs in the insert check. The corrected API stores `adoption_check` (P:1356–1369), validates its signature at P:1572–1576, and invokes it only during adoption at P:2041–2043. Following the old wording would recreate the exact round-2 regression where post-adoption inserts fail against retired legacy columns. Update the header/R14 to name the adoption check and keep any enduring record predicate in the separate insert check.

## Verification of the round-2 findings and r3/r4 changes

All SQL conclusions in this section are source-level verification; the battery cases were inspected, not executed here.

| Prior item | r4 disposition and evidence |
|---|---|
| B1: allowed physical type differs from facet type | **Fixed.** `rule_facet_column_errors` pairs each declared type with exact physical types, rejecting numeric typmods and cross-type coercions (P:1425–1439). Registration checks every existing version (P:1589–1591), preparation checks every row's version (P:1751–1756). B:T1g/T1h and M125 target it. |
| B2: unions consume document depth | **Fixed.** Union selection recurses at unchanged depth (P:686–689); actual object/array children increment it (P:706–707,738–739). B:V24 tests recursive refs/unions at 31, 62 and 63 links (B:338–355); M126 restores the bug. Python starts the root at depth zero (L:265). |
| B3: already-filled documents enter via adoption registration | **Fixed.** Any non-NULL terms, source, kind or version on an existing row rejects adoption registration (P:1577–1583). B:A1e and M127 target it. |
| NUL / lone surrogates | **NUL and surrogate values fixed; keys partially fixed.** L:252–275 covers controls, including NUL, and lone-surrogate values; see S2 for keys. SQL parsing refuses unstoreable input before duplicate checking (P:854–862; B:V21e). |
| Reusable core invariant | **Fixed in the intended architecture.** P:2900–2980 provides the owner-only reusable assertion; `tests/ci.sh:89–90` runs isolation and core checks at the end. Attributes, matview column grants, direct default ACLs, effective TEMP/database CREATE and schema CREATE are checked. R4 also forbids every membership held by the core (P:2924–2933). K8/K9/K10 cover key cases. |
| Freeze/hash text equality | **Fixed.** P:937 compares the non-freeze fields as text, preserving the stored schema text that was hashed; B:R8c/M131 targets numeric-scale edits. |
| Isolated guard cases | **Prior named gaps addressed.** B:V10b and V13b isolate integer and uniqueness checks; V24 isolates union depth. RC6/RC7 cover inputs freezes in both directions; O1/O2 cover ordinals. The additional gaps below prevent a universal “every guard is isolated” claim. |
| APPLY mutations accepting any apply failure | **Fixed.** M's `APPLY:<phrase>` cases require the named phrase in failing stderr; unrelated apply errors are misses. The code is at M's main apply-result branch. Anchor matching was run locally; actual failures were not induced. |
| Adoption equality ran on ordinary new inserts | **Fixed.** Separate adoption hook runs only in the empty-document transition; B:A3h/A4 and M128/M129 check refusal and subsequent insertion. S3 is stale documentation, not stale implementation. |
| Every named seed column must agree | **Fixed for well-typed input.** P:2280–2308 compares terms parsed and all other named columns except the matched applicability fields. R4 adds whole-envelope/no-id requirements, B:T4k–T4m/M130/M138/M139. S1 is the remaining malformed-type path. |
| Strategy versions independent of terms version | **Range supported and integer bounds enforced** at P:476–490; R4n–R4p and M132/M140 target invalid ranges. B2 is a separate coverage hole outside that branch. |

I found no regression introduced specifically by the r3/r4 fixes to type pairing, depth, adoption, text freeze comparison or role membership. B1/B2 concern older format-check omissions; S1 survives the strengthened r4 seed envelope check. Changing a seed's numeric spelling but keeping its mathematical value is explicitly intentional (P:2287–2290); a close/freeze must retain text, while a seed restates law. Do not confuse that choice with the earlier freeze hash defect.

## Inventory traceability

“Held” below means the mechanism/pattern is present in the inspected source; it does not certify unrun database tests. “Residual” names an explicit section-11 limitation. Area predicates and legal content remain the consumers' responsibility.

| Requirement | Result | Evidence / qualification |
|---|---|---|
| V1 | Held | Registry and one-way freeze, P:881–1011; stamped hash; privileges; immutable history. |
| V2, Step-2 portion | Held | Kind CHECK and registry FK added at P:1618–1620; registry role is pinned per kind, P:958–963. Actual kinds are Area. |
| V3 | Held for supported schema/document rules | P:376–875: closed objects, required fields, types, bounds, arrays, discriminator unions, fixed canonical numbers/ids/null rules. Rationals are expressible as numerator/positive-denominator object fields; legal arithmetic stays in core. R7 limits cross-check proof. |
| V4 | Held | Const-discriminator unions and per-branch parameter validation, P:449–498,662–689. No table reads in the immutable interpreter. |
| V5 | **Miss, B2** | Bounded version enforcement exists for strategy unions only. |
| V6 | Held as format | Per-section citation is documented at `law/README.md:69` and exemplified in ZZ schemas/files; areas choose section boundaries and require their citations. No generic legal-section inference is claimed. |
| V7 | Held as format | No JSON null; schemas may explicitly enumerate `unruled`. Required/optional keys decide absence; interpreter does not fill defaults (P:659–661,699–709). |
| V8 | **Miss, B1** | Registry recognizes a delegated branch but does not prove it admits the mandatory document. |
| V9 | Held for keyword support | Per-node/type allowlist and recursive validation, P:409–442,589–630. B1/B2 are convention restrictions, not silently ignored standard keywords. |
| V10 | Held as finite-corpus CI mechanism; unrun here | W:45–63, L:518–535; compares reference-plus-fixed-rules to DB for examples and mutations. R7 explicitly limits proof. |
| F1 | Held | Immutable facet registry, preparation derivation and writer comparison, P:1029–1194,1748–1780; history covers derived columns, P:1997–1999. R9 fixes the facet set for a table. |
| F2 | Held | text, text[], integer, boolean plus exact numeric/present types; pairing at P:1425–1439. |
| F3 | Held mechanism | Vocabulary table/column validation P:1098–1120; scoped code lookup P:1766–1790. Tenant vocabularies still need area scope/RLS declarations. |
| F4 | Held hook | `insert_check(jsonb)` signature and invocation P:1597–1600,1828–1830. |
| F7 | Held pattern | ZZ:83–105 resolves the governing row then checks the component against derived `component_ids`. |
| T1 | Held template | P:1439–1667 registers envelope, checks, exclusion, insert/history/no-truncate triggers; close floor hook P:1998–2017. Consumer must supply its complete floor. |
| T2 | Held | Immutable ordinals, multiranges and jurisdiction ranges P:1197–1331; derivation P:1802–1826; overlap exclusion P:1631–1632. |
| T3 | Held helper | P:2099–2210 resolves profile, exact key/date, and refuses absent/ambiguous law; tariff absence is explicit. Premise-to-system selection remains upstream -16/area work. |
| T4 | Held protocol | P:2070–2099 shared citation lock and fresh read; P:2005–2016 exclusive close lock and floor read, READ COMMITTED; RC1/RC2 test both orders. |
| T5 | Held normal path, S1 | Complete-envelope strict seed, P:2218–2315; re-seed compares parsed content and supplied fields. Malformed applicability needs rejection. |
| T6 | Held mechanism | Empty registration condition plus migration-only fill/equivalence hook, P:1572–1584,2026–2059; old identity/dates retained. R14 records area migration sequence but needs S3 wording fix. |
| U1 | Held | Tenant/system tariff envelope, FK/index/exclusion/FORCE RLS/grants P:1514–1520,1636–1652; same preparation and close protocol. |
| U2 | Held | Text parser uses PostgreSQL unique-key predicate before returning jsonb, P:841–875; every rule-row preparation calls it, P:1708. |
| U3 | Held hook, residuals R5/R6/R12/R16/R17/R18 | P:1868–1974 covers profile/law spans, locks/re-reads law rows and invokes comparator. Later law creates an audit obligation, not an automatic SQL audit runner. Core does not yet exist. |
| U4 | Held pattern | Law cite helper P:2152–2173; optional tariff resolution P:2176–2210; ZZ:65–105 requires law, checks optional tariff and component. |
| P1 | Held with residuals R4/R10 | P:2381–2543: typed state/service scope, units, numeric values, exclusions and close history. Class scope and first citing area's close floor are explicitly deferred. |
| P3 | Held format/helper | `law/README.md:71` documents published-name references and optional vocabulary facet; P:2513–2543 resolves exact scope/date or refuses. |
| C1 | Held with R1/R8 | NOLOGIN role, explicit invoker-function/read grants, RLS; reusable assertion P:2900–2980. Login provisioning/session identity is first-core-area work. |
| C2 | Held grant pattern; identity residual R1 | ZZ core record demonstrates separate grants/inputs stamping. Existing -13/-15 writes are intentionally not migrated here. |
| C3 | Held with R13 | P:2612–2869: tenant-safe append-only findings/dispositions, subject/rule existence and tenant checks, expected-decision pair, stamps. Subject durability is delegated to append-only area records. |
| C4 | Held | P:2554–2605 validates inputs kind/version, locks against freeze, enforces READ COMMITTED, stamps SHA-256 of canonical-number jsonb text. R15 specifies PostgreSQL serialization. |
| L1 | Held amended format | `law/README.md:13–46`, L:334–399: table/state/service files, explicit applicability, scenarios. Owner partition changed by inventory amendment. |
| L2 | Held, S2 | L:71–129 strict loaders; schema typing L:207–234; exact Decimal emission L:141–179; seed emitter L:402–414. Pins in `tools/law/requirements.txt`. |
| L3 | Held CI structure, residual R11 | `.github/workflows/ci.yml`, `tests/ci.sh`; W1–W5 and all batteries. Scenarios shape-checked until core types exist; stored-document comparison is semantic round-trip, not literal re-emitted YAML. Database run blocked here. |
| L4 | Held | ZZ fixture registers law/tariff/inputs kinds, multiple strategies, binding municipal and delegated rows, vocabulary facets, citations, core records and hooks. Three law rows passed local loader check. |

Not Step 2: actual V2 kinds; F5/F6 area facets/no facets; T7 correction lineage (R2); U5 customer-class vocabulary; P2 actual annual rate/legal applicability; P4 no backbilling published value. These are not missing machinery.

## Suitability for the first consumers

**-13 migration:** its text keys (`customer_class`, `cause`) fit the NOT NULL equality area key (`sql/v5.4.2-13-backbilling-caps.sql:674–701,744`). The sanctioned path can preserve all 16 row ids and their citations: add/fill applicability and template columns, register with an adoption check, replace the old history trigger in the same migration, compare document content including child window terms, then fill once. B:A3h/A4 demonstrates the important distinction between adoption and subsequent inserts. The migration must also replace its old exclusion, which lacks owner/system/jurisdiction dimensions, when those dimensions need distinct legal rows; merely adding the new exclusion leaves the old one over-restrictive. Its complete citation floor and calls to the law-citation helper remain area work. The stale R14 hook terminology needs S3.

**-15 rewrite:** the existing state/service/basis/customer-class design (`sql/v5.4.2-15-deposits-law-to-core.sql:465–493`) can use this template, and the F3/F4/F7 mechanisms support the specified reference-integrity facets. Move computation-only record grants to the core explicitly and install its inputs schemas; SQL should retain record integrity without reimplementing legal strategy arithmetic.

The applicability representation is appropriate: NULL is an unbounded universal ordinal span; explicit nonempty sets use immutable ordinals, and boolean jurisdiction represents false/true/either. Exclusions use overlap on those spans, catching universal against particular applicability. R3's equality-only area keys deliberately do not provide class wildcard precedence: enumerate legal classes or remove that dimension from the key. There is no silent broad-law fallback.

Always citing law and optionally tariff is suitable for both consumers. For the city case, the mandatory law row is delegated and the recorded tariff supplies policy. For regulated cases, law remains the legal constraint and tariff may tighten it. The fixture's absence of a usable component prevents recording a charge under delegation with no tariff; the actual core must refuse missing policy. **B1 must be fixed so the shared registry guarantees that delegated documents can exist.**

Shared-key tariff filtering is reasonable under R16: equally named area dimensions must have identical meaning. A utility's own class vocabulary cannot be given the same key-column name as the law's class unless their codes mean the same thing. If dimensions differ, the comparator must select the relevant law rows and detect any gaps it cares about; the generic aggregate coverage is not proof of coverage for every unshared legal dimension. This is an explicit residual/area contract, not a newly inferred precedence rule.

For well-typed seeds, “same row” is sensible: state/service + applicability sets + exact area key + start identifies it; end, source, kind, version and document must agree, as must any additional named columns. Ordering sets and mathematical numeric equality do not change law. Whole-envelope/no-id in r4 closes omission and identity ambiguity; S1 addresses ill-typed values before they are normalized into that identity.

## Integrity and test assessment

- **Interpreter:** inspected typed branches, bounds, string lengths, whitelisted patterns, const discriminators, local non-chained refs, recursive document depth, canonical numerics and global component ids. Recursive refs descend through objects/arrays; selecting a union branch no longer adds depth. Control-character prohibition removes the known trailing-newline regex discrepancy. No additional concrete standard-validator acceptance disagreement was established here; B1/B2 instead expose missing convention checks. S2 limits Python representability equivalence.
- **Duplicate parser:** `IS JSON OBJECT WITH UNIQUE KEYS` operates on original text, after checking jsonb storability and root type; duplicate object keys inside arrays are targeted by B:V21b. W4 casts documents directly to jsonb, so W4 does not test this parser or duplicate-key preservation (L:525–528). Keep parser tests separate.
- **Facets/generic record conversion:** exact type pairing is checked before `jsonb_populate_record`; reserved facet names cannot overwrite envelope/key columns. Paths refuse datetime and double conversion. Vocabulary SQL quotes identifiers/literals and binds codes. It remains the platform schema author's responsibility to choose correct semantic paths and scope mappings; app/core cannot register them. JSON row comparison protects content/facets on close; adoption has a separate narrow field set.
- **Concurrency:** citation/close and schema-write/freeze share lock keys and use READ COMMITTED. Tariff checks accumulate locks and re-read until no unseen id remains. RC1–RC7 check that session B was observed waiting and that A succeeded; this is materially stronger than sequential success. R5 explicitly leaves profile coverage unlocked, and R18 admits retry/deadlock outcomes. No race run occurred in this session.
- **Privileges/tenancy:** all patch functions are invoker-rights; helper reads honor RLS. The core's only explicit definer helper grants are the established tenant/admin identity functions. Registration/seeding/assertions are revoked from app/core. Core membership is now forbidden in either dangerous direction, matview column grants count, and effective CREATE/TEMP are checked. The base isolation assertion checks canonical policies/forced RLS and view/definer/default-ACL hazards (`sql/tu.sql:21638–21888`). As already documented in R1, app.user_id is the trusted session identity convention, not an authentication mechanism introduced here.
- **Audit subjects:** P:2713–2757 restricts subject relations to public ordinary/partitioned tables with id/tenant columns, checks the visible subject's tenant and registered rule/tariff tenant, and stamps terms version from that row. It does not provide a durable FK to arbitrary subjects (R13). Findings/dispositions use separate append-only grants and canonical tenant policy.
- **Inputs:** P:2563–2598 validates before fingerprinting, serializes with PostgreSQL jsonb text and checks an optional caller fingerprint. RC6/RC7 and X6 cover inputs freeze/isolation. Consumer tables still need their own append-only semantics and grants; a stamping trigger alone does not establish a core-only table.

**Does every guard have a case only it can refuse? No.** The old isolated integer/uniqueness/depth/ordinal/input-lock gaps are addressed, but the registration format cases B1/B2, malformed applicability S1, and surrogate keys S2 are missing. Existing strategy tests vary version bounds only inside the recognized strategy-union route. W4 mutates documents, not registration schemas; it cannot discover arbitrary new schema-shape combinations. Add each new negative alongside a valid near-neighbor, so disabling its guard causes that named case to fail.

The mutation runner now requires the intended APPLY phrase, and the battery checks SQLSTATE/message rather than any exception. All 139 source anchors apply to the frozen patch, including r3/r4 additions. Its normal DB names are hard-coded `m17`/`m17iso`/`m17race`/`m17law`, and it reads the working patch (M:32–34 and `runner`); it must be adapted in memory or scratch for a future **codex-prefixed, frozen-artifact** review run. It was not launched against those default databases. Mutation execution is outside routine CI; that is unchanged, documented review practice rather than evidence of kills in this session.

**What W4 proves:** finite-corpus agreement between the database interpreter and Draft202012Validator plus independently coded convention fixed rules, for each file schema after checking it equals its registered version (W:49–61). Here the reference half covered 899 cases. It does not prove all schemas/documents, registration's semantic format promises, duplicate parsing, locks, grants, or legal calculations. It also does not require an example for every branch: one valid example is enough to pass the nonempty-examples check. B1's impossible delegated branch can therefore escape a future corpus that contains only a valid law branch. The README correctly limits its claim at lines 126–128; R7 should be understood that narrowly.

**W3:** L:542–562 seeds twice, compares returned ids, compares stored terms as jsonb with source terms and rejects extra stored ids. It does not produce YAML from stored rows. That is a useful semantic round-trip under the prior disposition, not a byte-for-byte file round-trip or a proof that every stored envelope field was independently re-read by W3. Strict seed comparison carries the latter responsibility.

## Decision

Hold approval for **B1 and B2**, with isolated registration regressions. The priority should-fix is **S1**, so malformed applicability cannot become a silent successful re-seed. Fix S2 and stale adoption guidance S3 as small follow-ups. Before acceptance, run the frozen apply/battery, isolation, RC1–RC7, W1–W5 and targeted mutations on an authorized codex-prefixed scratch clone, and drop every created database. No created database remains from this review.
