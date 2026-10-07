**Verdict: not yet.** Three blocking items remain: facet-to-column type matching, validator depth agreement, and validation of prefilled documents at adoption-mode registration.

This was a read-only static review. **All reproductions and their outcomes below are predicted from the source, not executed.** I did not run database tests, races, or mutations, and modified no files.

Both frozen hashes match:

| Artefact | Observed MD5 | Result |
|---|---|---|
| Patch | `896915806252050afc5627ea7ff5def0` | Matches; 2,939 lines |
| Battery | `5da3cb4c31ec909eff92dd2b9bead7d5` | Matches |

The working patch and battery also have those respective hashes.

References below use:

- **P** — [patch-17-frozen-r2.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/patch-17-frozen-r2.sql)
- **B** — [battery-17-frozen-r2.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/battery-17-frozen-r2.sql)
- Other paths are relative to the repository root.

**Blocking findings**

**B1 — Facet registration still accepts a physical column whose type disagrees with the facet.**

The reserved-column and numeric-typmod fixes hold. However, P:1503–1513 only establishes that each physical column belongs to this allowlist:

```text
text, text[], integer, bigint, numeric, boolean
```

It never compares that type with the corresponding `rule_term_facets.facet_type`. Runtime preparation checks the declared facet **names**, not the physical types: P:1681–1690. Extraction verifies the JSON value against the facet declaration, then `jsonb_populate_record` converts it into the physical column: P:1148–1160, P:1791.

**Predicted reproduction:**

1. Create an empty copy of the ZZ law-table structure, with its primary key.
2. Change `component_ids` from `text[]` to `text`.
3. Register it for `zz_fee`, with the fixture’s complete facet list and insert hook.
4. Insert a valid ZZ document containing component ID `f1`.

Registration accepts `text`. Extraction produces a JSON array, but record population stores its JSON representation in the scalar text column. The stored facet is no longer a `text[]`, despite the declaration and downstream component-reference contract.

A second example is a declared `text` facet containing `"001"` mapped to a `numeric` column: population can store `1`. Both physical types independently pass the new allowlist.

This is the unresolved part of round-1 Codex B4. T1f/T1g and M109/M110 test reserved names and disallowed physical types; they do not test **allowed-but-mismatched** types.

**Required correction:** verify a deliberate mapping between declared facet types and physical column types, including later schema versions used by an existing table. Alternatively, add an equivalent exactness check before storing derived values. Test `text[] → text` and a scalar coercion independently of typmods.

---

**B2 — The database and reference validator still disagree on depth.**

SQL increments depth when selecting a `oneOf` branch, even though it is validating the same document node:

- depth refusal: P:640–641;
- union branch recursion: P:667;
- actual child recursion: P:684–685 and P:705.

Python increments depth only when descending into an object value or array element: `tools/law/lawc.py:264–290`.

Consequently, “64 levels deep” has two different meanings.

**Predicted reproduction:** register an inputs schema with this structure:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["payload"],
  "properties": {
    "payload": {"$ref": "#/$defs/node"}
  },
  "$defs": {
    "node": {
      "oneOf": [
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["tag"],
          "properties": {
            "tag": {"type": "string", "const": "end"}
          }
        },
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["tag", "next"],
          "properties": {
            "tag": {"type": "string", "const": "more"},
            "next": {"$ref": "#/$defs/node"}
          }
        }
      ]
    }
  }
}
```

Build the document as follows:

```python
node = {"tag": "end"}
for _ in range(31):
    node = {"tag": "more", "next": node}
doc = {"payload": node}
```

The schema fits registration’s reference and discriminator rules: P:429–484. Python’s deepest document value is at depth 33, so standard validation plus its fixed rules accepts it. SQL reaches the final union at depth 63, its selected object at 64, and `tag` at 65, then refuses it.

The original round-1 example of a plain document deeper than 64 is now rejected on both sides. The union combination remains broken. Current mutations do not generate this structure.

**Required correction:** count document depth consistently; entering a selected branch should not consume another document level. Add boundary tests combining objects, arrays, references and unions, plus a mutation that changes the depth accounting.

---

**B3 — Adoption-mode registration admits already-filled, unvalidated documents.**

The new existing-row check runs only when `p_adopts_legacy_rows` is false: P:1518–1523.

When it is true:

- registration requires an insert hook but does not execute it against existing rows: P:1524–1529;
- the added document CHECK permits all four document columns to be non-NULL: P:1564–1566;
- existing rows are not parsed, schema-validated, or checked for derived facets;
- subsequent adoption only applies when the old `terms` is NULL: P:1959.

Thus selecting adoption mode can register a table containing invalid completed documents.

**Predicted reproduction using the battery’s legacy fixture, before its registration:**

```sql
UPDATE public.zz_legacy_rules
SET terms_kind = 'zz_fee',
    terms_version = 1,
    terms_source = '{}',
    terms = '{}'::jsonb
WHERE id = '00000000-0000-4000-8000-0000000017e2';
```

Then register it using the same adopting registration and real `zz_legacy_check(jsonb)` hook as B:661–662.

The empty object is not a valid `zz_fee` document, and its missing cap disagrees with `legacy_cap = 500`. Nevertheless, the registration’s FK and all-or-none document CHECK pass. Neither document validation nor the equivalence hook runs for that row.

This requires a migration role configuring a table, not tenant access. It is still a registration integrity hole of the same class as the now-fixed “non-adopting registration accepts pre-existing rows” finding. It bypasses the approved empty-document adoption path without disabling a trigger.

**Required correction:** require adopting tables’ pre-existing document columns to be empty, or explicitly validate every prefilled row—including source agreement, facets and equivalence—before accepting registration. Add a negative beside A1d with a fully populated but invalid document.

**Round-1 findings: re-evaluation**

I traced each reproduction from my round-1 review through the revised paths.

| Round-1 finding | Round-2 result |
|---|---|
| **B1: adoption changes legacy meaning** | **Original reproduction now refused.** Registration requires a hook, and preparation invokes it with the complete row and derived facets: P:1528, P:1761–1762. The fixture’s `legacy_cap IS DISTINCT FROM fee_cap` comparison rejects delegation for cap 500: B:647–650, B:685–687. Registration has the separate B3 hole above. |
| **B2: tariff uses pre-lock law** | **Fixed for the reported race.** P:1844–1880 rereads after acquiring previously unseen row locks; only a read whose rows were already locked is accepted. Close-plus-successor therefore reaches the successor comparison. RC5 directly targets this; M106 restores the old defect. |
| **B3: inputs freeze under an old snapshot** | **Fixed.** P:2487 requires READ COMMITTED before locking and reading the schema. The REPEATABLE READ reproduction now fails before insertion. X6/M107 target it. |
| **B4: facet overwrites `terms`, or rounds/coerces** | **Partly fixed.** Reserved names and `numeric(4,0)` are refused. Allowed-but-mismatched physical types remain accepted: current B1. |
| **B5: newline, Decimal rounding, depth** | **Partly fixed.** Newline/tab rejection is present on both sides; `format(d, "f")` removes context-dependent normalization. Plain excessive document depth is aligned. Union depth still disagrees: current B2. |
| **B6: published class scope and units** | **Resolved by implementation plus amended scope.** Units now have an FK: P:2304. Class scope is explicitly deferred by R10 and the inventory amendment at line 182. I do not retain it as a blocker. |
| **B7: citing-record integrity** | **Reported holes fixed.** Law citation resolves applicability after locking: P:2091–2095. The fixture checks the tariff’s tenant/key/date and component membership, revokes citing-record updates, and uses a composite tenant/charge FK: `fixture-zz.sql:79–100`, `:129`. |
| **B8: dispositions, expected-decision NULL escape, scenarios** | **Database omissions fixed; scenarios explicitly deferred.** Dispositions are append-only, stamped and tenant-linked: P:2725–2782. Expected decision/date pairing is checked at P:2593 and P:2628. Scenario schema checking is R11 and inventory amendment line 184. |
| **S1: core privilege assertions** | **Main counterexamples fixed.** Role attributes, effective database TEMP/CREATE, public-schema CREATE and column-level matview SELECT are checked. The reusable-invariant concern remains; see S2 below. |
| **S2: tariff without a law table** | **Explicit residual R12**, P:2904–2908. This is an exemption, not the standard law-backed tariff path. |
| **S3: explicit YAML `!` tag** | **Fixed.** Any non-NULL explicit tag is rejected at `lawc.py:84–86`; W5 adds `bang`. |
| **S4: non-durable audit subject reference** | **Explicit residual R13**, P:2909–2912. Subject existence remains a point-in-time check; areas must make audited records durable. |
| **S5: unknown state accepted** | **Original reproduction now refused.** P:1729 requires a state place with that code. |
| **S6: file partition differs from L1** | **Reconciled.** Inventory amendment line 183 adopts the table/state/service partition. |

The adoption path still deliberately discards a supplied `terms` value before preparation, P:1973. Therefore a correct `terms_source` alongside a contradictory supplied `terms` is overwritten rather than refused as it would be on insert. This does not defeat equivalence—the stored document still comes from the checked source—but the “validated exactly as an insert” wording at P:1958 is too broad.

**Should-fix findings**

**S1 — Python accepts strings that PostgreSQL cannot store.**

The new control-character regex starts at U+0001: `lawc.py:252`. A valid fixture document with citation `"ZZ\u0000"` therefore passes Python’s schema and fixed-rule checks. Emitted SQL subsequently fails PostgreSQL’s JSONB conversion, which the SQL parser correctly reports at P:837–841.

The same general representability issue applies to unpaired surrogate escapes in JSON input. The current W4 replacement set does not exercise either case: `lawc.py:459–461`.

Add a Python-side PostgreSQL-representability check and targeted loader tests. This is distinct from a pattern disagreement: the document cannot reach the SQL interpreter at all. B:311–312 already acknowledges the SQL-side NUL restriction.

**S2 — Core security checks remain a one-time patch tail, not part of the reusable invariant.**

The new checks at P:2811–2835 are useful, but `assert_tenant_isolation_invariants()` still checks matview reachability for `tally_app`/PUBLIC, not `tally_core`: `sql/tu.sql:21777–21792`.

**Predicted reproduction:** after applying -17, grant `tally_core` SELECT on a materialized view containing tenant data, then run the standard invariant assertion. Its matview check does not detect the core grant. Rerunning the -17 tail would detect it, but later patches and the final CI assertion call the shared function: `tests/ci.sh:89`.

Move the core checks into the reusable invariant. Also make “cannot define code” cover CREATE in any relevant schema; the current check only inspects `public`, P:2830. These are hardening gaps, not a finding that a fresh installation grants matview access.

**S3 — Freezing a schema can change its serialized content without updating its hash.**

Schema freeze immutability compares JSONB values using semantic equality: P:915–916. The hash was calculated from JSONB **text**, P:977.

**Predicted reproduction:** freeze a schema while changing a numeric bound from `0` to `0.0` using `jsonb_set`. JSONB equality treats those numbers as equal, so the freeze passes. The stored schema’s textual representation changes, but `schema_hash` remains the previous hash.

The law-row close fix uses text comparison at P:1932 specifically to prevent this class of change. Apply equivalent protection to schema freezes, and test:

```text
schema_hash = sha256(current stored json_schema::text)
```

after every permitted registry operation. This is an integrity defect in the stored hash, although the numeric bound’s validation meaning does not change.

**S4 — Important guards still lack independent refusal cases.**

The battery’s SQLSTATE-and-message discipline is good: B:41–67. Exact error-list comparisons also detect removal of individual checks. Nevertheless, it is not true that every guard has an input **only it** can refuse:

- V10’s non-integer `1.5` also exceeds the version maximum: B:264–266.
- V13’s duplicate array item also duplicates a component ID: B:278–280.
- No depth case exercises the SQL/reference accounting difference.
- T1g exercises a disallowed typmod, not a mismatch between two allowed types.
- A1d exercises non-adopting registration, not prefilled documents under adoption mode.
- RC3/RC4 exercise ordinary rule insertion versus schema freezing; they do not exercise `stamp_core_inputs` in both freeze orders. X6 covers isolation, not those READ COMMITTED races.

Add isolated cases and mutations for these distinctions.

**Step-2 requirement disposition**

“Held” means supported by the inspected source, not an executed test result. “Partial” identifies an unresolved implementation defect. Residuals are distinguished from missing work.

| Requirement | Disposition and evidence |
|---|---|
| **V1** | Held in structure: registry, versioning and one-way freeze, P:864–990. Hash immutability needs S3. |
| **V2** | Held: table kind CHECK plus registry FK, P:1557–1559. Consumer kind definitions remain Area work. |
| **V3** | Partial: supported types, bounds, closed objects, arrays and component IDs are implemented, P:621–815. Depth agreement has B2. Rational shapes are expressible. |
| **V4** | Held: required const discriminator, disjoint values and selected-branch validation, P:444–484, P:647–667. |
| **V5** | Held as the format rule; strategy-discriminated branches additionally require a fixed integer version, P:467–475. |
| **V6** | Held as a schema/authoring format rule: `law/README.md:69` and ZZ section citations. |
| **V7** | Held: explicit schema values can represent `unruled`; document nulls are refused, P:643–644. |
| **V8** | Held: mandatory cited delegated branch for law kinds, P:948–975. |
| **V9** | Keyword allowlist held, P:402–426; reference restrictions at P:429–441. Supported-schema runtime agreement still needs B2. |
| **V10** | Partial: W4 now checks registered-schema equality and discovers schema files, but the depth counterexample remains. |
| **F1** | Partial: derivation and history protection exist; physical facet matching needs B1. |
| **F2** | Partial for the same reason. JSON extraction checks declared types, P:1133–1157, but storage can coerce them. |
| **F3** | Held as insertion-time scoped vocabulary checking, P:1698–1722. Vocabulary lifetime remains an area responsibility. |
| **F4** | Held: complete-row insert hook, P:1761–1762; fixture predicate at `fixture-zz.sql:110–115`. |
| **F7** | Held as a pattern: component membership is checked at `fixture-zz.sql:94–100`. |
| **T1** | Partial: envelope, exclusions, stamps, close/history and hooks exist. B1/B3 affect registration guarantees. |
| **T2** | Held: immutable ordinal-based sets and jurisdiction spans, P:1181–1297; intersecting exclusion at P:1570. |
| **T3** | Held: exact key/profile/date lookup with missing/ambiguous refusal, P:2029–2072. |
| **T4** | Held for the inspected law-row protocol: lock before rereading citation/floor, P:1939–1942, P:2007–2009; tariff comparison rereads after locks. |
| **T5** | Held for its explicitly documented seed identity, P:2142–2223; qualifications below. |
| **T6** | Partial: equivalence hook and one-time update hold, but B3 permits bypass at registration. Migration sequencing is R14. |
| **U1** | Held structurally: tariff envelope, RLS, validation, history and grants, P:1479–1597. Facet defect B1 applies. |
| **U2** | Held: original text is checked for recursive duplicate keys before the parsed value is returned, P:824–853. |
| **U3** | Hook and finding infrastructure held. Later-law audit execution is deferred by R6; profile locking by R5; close-under-tariff behavior by R17. |
| **U4** | Held as the revised fixture pattern, `fixture-zz.sql:62–104`. No-tariff decisions under delegated law remain the core’s refusal, P:2140. |
| **P1** | Held within amended scope: unit vocabulary, typed state/service scope, exact numeric values and history. Class scope is R10; citation close floor is R4. |
| **P3** | Held: named-source format, optional vocabulary facet and dated lookup; `law/README.md:71`, P:2426. |
| **C1** | Held for fresh role setup and current checks, P:163–218, P:2811–2835. Reusable hardening needs S2. |
| **C2** | Grant pattern held in the ZZ core table, `fixture-zz.sql:125–137`. Session-user meaning remains explicit R1. |
| **C3** | Held: findings, expected-decision pairing, dispositions and tenant linkage, P:2567–2782. Durable subject references remain R13. |
| **C4** | Held for the intended JSONB inputs columns: READ COMMITTED, schema validation and database-computed fingerprint, P:2467–2518. Serialization contract is R15. |
| **L1** | Held as the amended file format. Scenarios are optional in tooling, `lawc.py:355`, `:387`; substantive scenario coverage is not established. |
| **L2** | Substantially held: strict YAML, schema-directed typing, exact decimal serialization and seed emission. PostgreSQL string representability needs S1. |
| **L3** | Partial: workflow, batteries, isolation/races, file checks and cross-check are present. B2 remains; scenario schema checks are explicitly deferred by amended inventory/R11. |
| **L4** | Held: fictional law, tariff and inputs kinds, scoped vocabulary, municipal-bound and delegated cases in the ZZ fixture/files. |

F5/F6, U5, P2/P4 and the consumer-specific portions of V2 are Area/no-work entries. T7 is explicitly Out, recorded as R2.

**Can the first consumers use this?**

**The -13 migration can use the architecture once the blockers are fixed.** Its `customer_class` and `cause` are already NOT NULL text keys, compatible with the exact-key template: `sql/v5.4.2-13-backbilling-caps.sql:678–679`.

R14 correctly records that migration must establish applicability spans, replace the old history guard and compare the document with both legacy columns and child window terms: P:2913–2920. The new hook can perform that comparison, but the generic machinery cannot establish that an area hook actually compares every legacy predicate. That remains part of reviewing the migration.

**The -15 rewrite can use the architecture, but its class mapping is still an area design obligation.** Its existing `customer_class` and `basis` fit the exact-key template: `sql/v5.4.2-15-deposits-law-to-core.sql:469–470`. Its typed facet needs make B1 particularly relevant.

The principal template choices are reasonable within the recorded contracts:

- **Applicability sets:** NULL as every owner/system, with intersecting spans, avoids NULL escaping an exclusion. There is no precedence fallback.
- **Area keys:** NOT NULL and `=` are suitable for the existing keys. “Every customer class” requires explicit rows or a different area key, as R3 states.
- **Law always, tariff optionally:** the revised citation helper and fixture support municipal delegation without citing inapplicable investor-owned law.
- **Shared tariff/law keys:** filtering by identically named key columns is concrete and predictable. For tenant-defined classes, R16 requires a different column name and an area comparator. Coverage over all candidate law rows does **not** independently prove coverage for every unshared legal dimension; the area must establish that.
- **Adoption:** in-place identity preservation is appropriate, subject to B3 and complete area equivalence checking.
- **Seed identity:** applicability sets, exact area key and start identify the row; document, end, citation, kind and version are compared. This is suitable for `lawc` output.

`rule_row_seed` is not full-row equality. Its existing-row branch ignores supplied IDs, derived columns and additional legacy content columns, and does not rerun full document validation: P:2204–2219. Thus it should not be used to verify legacy-column equivalence. The fixes for unknown columns and omitted-column defaults hold at P:2172–2201.

**What W4 and the mutation suite establish**

W4 is materially improved:

- It discovers every matching schema file, requires examples, and checks equality with the registered schema: `lawfiles-17.sh:45–62`.
- Its reference is explicitly Draft 2020-12 **plus fixed convention rules**, matching the revised README: `law/README.md:126–128`.
- M105 targets a check whose removal should be detected by W4: `mutations-17.py:327–328`.

It establishes agreement on the generated corpus. It does not establish agreement for the entire registered subset. Mutations replace values, remove keys, switch discriminators and duplicate items; they do not systematically generate schema combinations or deep recursive documents: `lawc.py:459–510`. B2 is a concrete surviving combination.

The mutation harness is also narrower than a claim that every guard is independently proven:

- Some mutations are caught by exact diagnostic changes even when another guard would still refuse the document.
- `APPLY` mutations count any failed apply as caught, without checking the intended invariant’s error: `mutations-17.py:409–415`.
- Mutation execution is not part of `tests/ci.sh:79–89`.
- W3 compares stored `terms` with emitted JSON and checks participating tables for extra rows; it does not serialize complete stored rows back into YAML: `lawc.py:537–558`.

I have not independently confirmed the reported 899-document result or mutation pass counts.

**Notes**

- I found no concrete ordinary-writer SQL injection path in the inspected facet scope, key lookup or hook arguments. Values and identifiers are quoted, relations/hooks are platform-configured, and the new functions are invoker-rights.
- The revised direct law citation orders operations correctly: lock and reread first, applicability resolution second. The tariff reread loop fixes the reported stale-law race; its bounded retry fails closed.
- Dispositions now have the needed composite tenant/finding FK and stamped user. Audit subject durability remains explicitly outside the generic enforcement.
- The class-scope and scenario-schema deferrals are now recorded in the inventory itself. They are no longer undisclosed failures to implement the frozen specification.

**Approval should wait for B1–B3**, with targeted regressions for each. The round-1 fixes substantially improve the patch, but two claimed fixes remain incomplete and adoption-mode registration still provides an unvalidated entry path.