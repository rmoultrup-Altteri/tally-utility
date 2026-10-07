**Verdict: not yet.** The overall separation is usable, but adoption, tariff locking, input-schema freezing and facet registration have integrity gaps. Several explicit Step 2 requirements are also missing.

The frozen artefacts match:

| Artefact | Observed MD5 | Result |
|---|---|---|
| `patch-17-frozen-r1.sql` | `bf006d2a6722035d928e34177fdf60a0` | Matches; 2,558 lines |
| `battery-17-frozen-r1.sql` | `43c4132fb4ed8d2cdebfd77c30429c15` | Matches |

This was a read-only static review. **Every reproduction below is predicted from the source, not executed.** No database tests or mutations were run, and no files were modified.

For citations below:

- **P** = [patch-17-frozen-r1.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/patch-17-frozen-r1.sql)
- **B** = [battery-17-frozen-r1.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/battery-17-frozen-r1.sql)
- Other paths are relative to the repository root.

**Blocking findings**

**B1 — Adoption can change the law while preserving its old identity and dates.**

The approved requirement is not merely “fill `terms` once.” It requires the database to establish that the document equals the old typed content.

The adoption branch checks unchanged columns, migration privileges, isolation and applicability spans, then validates the new document. It never compares that document with the legacy content. `insert_check` is optional, and registration does not require an equivalence hook for adopting tables. See P:1326–1330, P:1805–1829.

The battery demonstrates the omission: `zz_legacy_rules` has `legacy_cap`, but its registration supplies no checking hook. See B:589 and B:602–603.

Predicted reproduction, after the legacy fixture is registered and before its second row is adopted:

```sql
UPDATE public.zz_legacy_rules
SET terms_kind = 'zz_fee',
    terms_version = 1,
    terms_source =
      '{"governs":"delegated_to_utility","citation":"ZZ 9"}'
WHERE id = '00000000-0000-4000-8000-0000000017e2';
```

As the migration role, this passes despite replacing the meaning of a row with `legacy_cap = 500` with delegation. No disabling of triggers is needed.

The branch also deliberately removes supplied `terms` before preparation at P:1819, so adoption does not enforce the ordinary disagreement check between supplied `terms` and `terms_source`.

**Required correction:** make adoption contingent on a required, area-supplied equivalence check or deterministic legacy-to-document conversion. Test a schema-valid but semantically different document. The existing A3 tests cover second fills, unrelated edits and invalid documents, but not this central requirement.

---

**B2 — Tariff validation uses a law row read before its lock, allowing stale coverage and comparison.**

`rule_tariff_check` opens a query that retrieves the law row’s document and range, then takes the shared advisory lock inside the loop. After waiting, it uses the already-read `l.r` and `l.j`; it never re-reads the law row. See P:1716–1729.

Predicted race:

1. Session A closes an open law row at 2030 and retains its exclusive advisory lock before committing.
2. Session B inserts a tariff extending beyond 2030. Its query sees the old, committed, open-ended law row.
3. B waits at P:1727.
4. A commits.
5. B continues with the old open-ended `l.r`, declares the tariff fully covered and compares against the old `l.j`.

If A also inserts a stricter successor, B can miss that successor as well: its enumeration started before A committed.

This differs from `rule_row_cite`, which correctly takes the lock before querying the row at P:1854–1856. Residual R5 concerns profiles; it does not disclose this law-row race.

**Required correction:** acquire the relevant locks, then re-read and establish coverage/comparison from current rows. Add close-first tariff races, including close-and-successor. The existing race script covers direct citations and schema freezing only: `races/rule-close-17.sh:61–89`.

---

**B3 — `stamp_core_inputs` allows a frozen version through an old transaction snapshot.**

The inputs trigger takes the schema’s shared advisory lock and reads `accepts_new_rows`, but does not require READ COMMITTED. See P:2240–2273. Ordinary rule insertion explicitly requires it at P:1660.

Predicted reproduction:

1. A core transaction begins REPEATABLE READ and establishes a snapshot while an inputs schema accepts rows.
2. Another transaction freezes that schema and commits.
3. The core transaction inserts a calculation using the frozen version.
4. Its advisory lock succeeds, but the subsequent SELECT sees its old snapshot and accepts the insert.

The schema row is not updated by the core transaction, so an ordinary REPEATABLE READ write-conflict check does not repair this.

**Required correction:** apply the same isolation requirement to inputs stamping, and test both freeze orders for inputs. `isolation-17.sh:25–34` and the race fixture exercise rule rows, not this path.

---

**B4 — Facet registration permits replacing the validated document and silently coercing facet values.**

Registration checks only whether a facet column exists. It neither excludes template/key columns nor verifies the SQL type against `facet_type`. See P:1414–1417.

Preparation then merges:

```sql
jsonb_build_object('terms', v_terms) || v_facets
```

at P:1613, and populates the physical record at P:1667 or P:1671.

Two predicted examples:

- Register a tariff kind with a text facet named **`terms`**, extracted from a string property. Register its table with `facet_columns = ARRAY['terms']`. When the inserted `terms` is initially NULL, the writer-value check passes. The facet overwrites the validated document in `v_out`, and the table stores a JSON string instead of the validated object.
- Declare a `number` facet but give its SQL column type `numeric(4,0)`. A derived value of `1.5` becomes `2` during record population. The stored facet no longer equals the document’s value. A numeric facet stored in a text column can similarly be silently coerced.

These are migration-configuration defects, not a tenant’s ability to register schemas. Nevertheless, the shared registration function accepts them and then gives runtime writes invalid semantics.

**Required correction:** reserve all envelope and key names, verify facet SQL types and permitted typmods, and ensure population cannot change the derived value. Add registration negatives and a stored-document validity assertion.

---

**B5 — Validator/reference agreement and exact-number handling have concrete counterexamples.**

There are three separate problems.

1. **The whitelisted code pattern is not equivalent across the engines.**  
   P:342–345 explicitly claims equivalence for `^[a-z][a-z0-9_]*$`. Python’s `$` can match immediately before a final newline; PostgreSQL’s default non-newline-sensitive matching requires the end of the string.

   Predicted case: use the existing tariff example with `fee.id = "t1\n"`. The Python reference path accepts the pattern; the database rejects it at P:675. The fixed-rule overlay does not reject that string. W4 does not generate newline replacements: `lawc.py:422–423`.

2. **Schemas can admit documents deeper than the interpreter permits.**  
   Registration recursively checks schema syntax but imposes no corresponding depth bound and allows recursive object definitions: P:392–404, P:547–559. Runtime validation refuses after depth 64 at P:576–590, with unions consuming additional depth at P:616.

   Predicted case: register an inputs schema containing a chain of 65 nested, closed object properties, and supply its valid document. Standard validation accepts it; the database rejects it. An optional recursively referenced child provides another example.

3. **Python decimal canonicalization rounds through the active Decimal context.**  
   `canonical_number` calls `d.normalize()` at `tools/law/lawc.py:140`. With the default precision, that rounds values exceeding 28 significant digits.

   Predicted case: a canonical tariff amount of `12345678901234567890123456789` is accepted by the schema and PostgreSQL numeric semantics, but the loader calls it non-canonical because normalization changes its value. Schema numbers are also passed through this serializer, potentially changing bounds supplied to the database cross-check.

**Required correction:** define and test the actual supported document domain; fix regex equivalence and context-independent decimal serialization; align depth handling between registration, runtime and the reference check.

W4 currently compares the database with **JSON Schema plus handwritten convention rules**, not unmodified JSON Schema: `lawc.py:276–279`. That is defensible for canonical numbers and global component IDs, but its claim must say so. It does not prove equivalence for the whole registered subset.

---

**B6 — Published values cannot represent the required class scope, and units are not a vocabulary.**

P1 explicitly requires state, service and customer-class scope, with NULL meanings. The implementation permits only:

- no scope;
- state;
- state plus service.

See P:2066–2069. There is no class column in `rule_parameter_values` at P:2104–2128 or class argument in its lookup at P:2199.

This loses an existing consumer capability: `sql/v5.4.2-15-deposits-law-to-core.sql:1138–1162` includes nullable `customer_class` and its composite vocabulary reference.

Additionally, `unit` is only a regex-constrained text value at P:2065. There is no unit vocabulary or FK as required by P1.

The close-floor omission is honestly recorded as R4, P:2533–2535. The class and unit omissions are not.

**Required correction:** implement typed class scope and a unit vocabulary, or obtain an explicit specification change. Encoding class in the parameter name would contradict the inventory’s settled decision to keep scope typed.

---

**B7 — The shipped record pattern does not establish the required references.**

Three missing checks make the ZZ fixture unsuitable as proof of the promised consumer pattern:

- **Wrong applicable law:** `zz_charge_cites` checks existence and date, but never resolves the law for the charge’s tenant/profile/key. A municipal tenant can cite an investor-owned law row in force on the same date. See `law/fixtures/zz/fixture-zz.sql:63–81`.
- **Cross-tenant core reference:** `zz_charge_calcs.charge_id` has a simple FK, and the inputs trigger does not check the charge’s tenant. A core session can insert its own `tenant_id` with another tenant’s known charge ID. FK enforcement does not substitute for tenant matching. See `fixture-zz.sql:102–113`.
- **No component-reference pattern:** facets expose `component_ids`, but no record has a component ID and no guard checks membership. See `fixture-zz.sql:33`, `:63–81`. F7 remains unimplemented.

There is also an UPDATE hole in the fixture’s citing records: its citation trigger runs only on INSERT at `fixture-zz.sql:81`, while the base table defaults grant `tally_app` UPDATE (`sql/tu.sql:11388–11389`). A later update can replace the law/date/tariff without the citation guard.

These findings do **not** mean `rule_row_cite` should itself infer every area key. Its narrow contract is reasonable. They mean the promised Step 2 **pattern** must show the missing area guard, composite tenant integrity, component membership and record immutability.

**Required correction:** ship and test a complete citing-record example, including wrong-profile law, wrong-class law, wrong-tenant core references, unknown component IDs and citation-changing updates.

---

**B8 — Audit findings and golden scenarios omit explicit Step 2 work.**

- **No dispositions:** C3 requires separate append-only disposition rows. The patch creates findings only. Its table comment delegates “how that is recorded” to areas at P:2380, but section 11 does not list this scope reduction.
- **Expected-decision CHECK has a NULL escape:** for a non-missed finding, set `expected_decision = NULL` and `expected_by` to a date. The trigger compares only whether `expected_decision` exists at P:2399. The CHECK at P:2365 evaluates to NULL, which passes. Thus the “or the reverse” refusal promised at P:122 is not held.
- **Scenarios are not schema-checked:** `lawc.py:366–371` checks only the outer `{name, inputs, expected}` structure and non-empty mappings. It does not type or validate scenario inputs/outputs against schemas. An arbitrary input key and `expected: {fee: nonsense}` pass that check. Scenarios are optional altogether at `lawc.py:334` and `:366`.

**Required correction:** implement dispositions; make the expected-decision pair explicitly both-null or both-non-null; define scenario input/output schema references and validate them. Core execution can remain deferred as specified.

**Should-fix findings**

**S1 — Core privilege assertions are weaker than the existing house pattern.**

The core materialized-view assertion uses `has_table_privilege` at P:2497. The base isolation assertion deliberately uses `has_any_column_privilege` because column-level SELECT grants are otherwise missed: `sql/tu.sql:21776–21788`.

Predicted case: grant `tally_core` SELECT on individual columns of a materialized view. The new assertion does not detect it; the old assertion checks `tally_app` and PUBLIC, not `tally_core`.

Likewise, creation preserves an existing `tally_core` role without checking LOGIN, SUPERUSER, BYPASSRLS or other inherited privilege sources: P:142–180. The fresh-role path is substantially safer than the assertion’s general wording implies.

Use effective privilege checks, including column grants, and extend the reusable invariant rather than relying only on the patch’s one-time tail.

**S2 — A tariff table can silently opt out of all law/profile checking.**

Registration explicitly permits both law table and comparator to be absent at P:1428–1429. `rule_tariff_check` immediately returns in that case at P:1698–1700.

That may be useful for a separately defined category, but it contradicts the unconditional tariff promises at P:111–112. Require the pairing for the standard tariff template, or name and document the exemption.

**S3 — Strict YAML still admits an explicit tag.**

`StrictLoader.compose_node` exempts tag `"!"` at `lawc.py:85`. Thus a non-specific explicit tag such as `rows: ! [...]` is accepted despite the “explicit tags are refused” claim. W5 tests `!!seq`, not `!`: `lawfiles-17.sh:72–73`.

**S4 — Audit subject existence is a point-in-time check, not durable reference integrity.**

The subject check is an unlocked dynamic SELECT at P:2416, with no FK-like mechanism preventing later deletion or tenant reassignment. It correctly checks the visible tenant at insertion, but can leave dangling findings if an admissible subject table permits deletion.

Decide whether historical findings deliberately retain references to deleted subjects. If so, preserve enough subject identity in the finding and document that contract; otherwise provide durable reference enforcement.

**S5 — The header overstates state validation.**

P:106 promises refusal of unknown states. The template installs only a two-uppercase-letter check at P:1449; law preparation does not verify a known state. A law row for an otherwise unknown `QQ` is therefore admissible.

Either enforce the claimed check or narrow the wording.

**S6 — File organization differs from L1 without acknowledging the change.**

L1 says one file per kind/state/service/owner type. The actual documented format groups a table’s rows for a state/service, and the ZZ file mixes owner sets: `law/README.md:14`, `law/fixtures/zz/zz_fee_rules.yaml:14`, `:40`, `:53`.

The set-based design makes this a reasonable format choice. It still needs reconciliation with the inventory rather than being reported as exact compliance.

**Requirement-by-requirement disposition**

“Held” below means supported by the inspected implementation, subject to the findings above. “Partial/miss” identifies an unstated gap. “Residual” means explicitly recorded in section 11.

| Requirement | Disposition | Evidence / qualification |
|---|---|---|
| V1 | Held, with freeze-path defect | Registry, hashes, immutability and one-way freeze: P:789–917. Inputs consumer has B3. |
| V2 — table pinning | Held | Kind CHECK and registry FK: P:1445–1447. Actual consumer kinds remain Area work. |
| V3 | Partial | Types, bounds, closed objects, arrays and IDs implemented: P:570–749. B5 limits agreement; rational shape is expressible with integer fields and positive denominator. |
| V4 | Held | Discriminated unions: P:407–433, P:596–616. |
| V5 | Held as a format rule | Strategy/version format documented at `law/README.md:64`; fixture schemas require version. Registration does not independently recognize every strategy reference. |
| V6 | Held as a format rule | Per-section citations: `law/README.md:66`; ZZ schema/file examples. |
| V7 | Held as a format rule | No null type; explicit enum/string values can represent `unruled`: P:341, P:592–593; README:60. |
| V8 | Held | Mandatory delegated branch: P:873–900. |
| V9 | Partial | Keyword allowlist exists: P:365–404. Registered schemas can exceed runtime depth; B5. |
| V10 | Partial/miss | W4 exists, but B5 gives counterexamples and its reference includes extra fixed rules. |
| F1 | Partial | Derivation and history comparison exist; unsafe column registration/population is B4. |
| F2 | Partial | Requested facet kinds implemented: P:954–955, P:1053–1077. Physical SQL types are not checked. |
| F3 | Held for insertion checks | Scoped vocabulary queries: P:1586–1610. Vocabulary lifetime/immutability remains an area responsibility. |
| F4 | Held | Insert predicate hook: P:1641–1643; ZZ example at `fixture-zz.sql:87–92`. |
| F7 | Miss | Component arrays exist, but no checked record-component citation pattern; B7. |
| T1 | Partial | Envelope, exclusion, history and floor hook exist: P:1368–1485, P:1755–1867. Adoption/facet defects remain. |
| T2 | Held | Fixed ordinals and intersecting applicability spans: P:1101–1217, P:1627–1632. |
| T3 | Held as shared resolver | Profile lookup, exact key and missing/ambiguous-row refusal: P:1875–1918. Consumers must compare selected IDs with their citations. |
| T4 | Partial | Direct citation/close protocol is correctly ordered: P:1785–1788, P:1853–1856. Tariff checking violates it; B2. |
| T5 | Held for its defined identity | P:1967–2026. Qualifications below. |
| T6 | Miss | One-time write exists; mandatory legacy equivalence does not. B1. |
| U1 | Partial | Tariff envelope/RLS/grants exist: P:1463–1478. B2 and optional law-check bypass remain. |
| U2 | Held | Text parser uses PostgreSQL’s recursive unique-key predicate: P:758–778; ordinary preparation always calls it. |
| U3 | Partial; later-law behavior residual | Comparator hook exists but has B2. Later-law audits are R6, P:2542–2545; profile locking is R5. |
| U4 | Partial/miss as a pattern | Separate law/tariff IDs and lookups exist, but fixture does not establish applicable law or immutable citations; B7. |
| P1 | Partial/miss plus residual | Values/ranges/history exist. Class scope and unit vocabulary missing; B6. Close floor explicitly R4. |
| P3 | Held as a format rule | Named published source documented at `law/README.md:68`; dated lookup P:2199–2229. |
| C1 | Held for fresh role setup, with hardening gaps | P:142–180, P:2468–2505. Service-login provisioning is described rather than instantiated. S1 applies. |
| C2 | Pattern partially held; identity residual | Core-only INSERT example: `fixture-zz.sql:111–113`. `evaluated_by` identity is explicitly R1, P:2518–2522. B7 affects the example. |
| C3 | Partial/miss | Findings/RLS/stamps exist: P:2339–2461. Dispositions absent; expected-pair NULL escape; B8. |
| C4 | Held for stamping; freeze integrity incomplete | Database hash and input validation: P:2240–2290. B3 permits frozen-schema use. |
| L1 | Partial | Law format and citations exist; grouping differs and per-row scenarios are optional. S6/B8. |
| L2 | Partial/miss | Strict parsing and reviewed seed emission exist. Decimal context and tag exceptions: B5/S3. |
| L3 | Partial/miss | PostgreSQL 16 build and test orchestration exist: `postgres/Dockerfile:42`, `tests/ci.sh:63–89`. Scenario schema checks are missing; W4 is narrower than claimed. |
| L4 | Held in basic breadth; integrity example incomplete | ZZ has law/tariff/inputs kinds, alternative strategies, delegation, and an all-owner commercial law covering municipal systems. B7 limits what it proves. |

F5, F6, U5, P2 and P4 are Area or non-Step-2 items. T7 is explicitly Out and is recorded as R2 at P:2523–2527.

Section 11 honestly records C2 identity, correction lineage, exact area-key limitations, published-value floors, profile locking, later-law audits, finite fixture-based cross-checking and explicit core grants. It does **not** record the missing legacy equivalence, class scope, dispositions, component-reference example or scenario schema validation.

**Suitability for the two consumers**

The applicability spans are a good fit for both consumers. Using overlap for owner/system sets and jurisdiction, with NULL represented as the universal span, avoids the classic “NULL wildcard does not overlap a specific value” exclusion defect. The ordinary lookup also refuses ambiguity rather than selecting an arbitrary match. See P:1160–1217, P:1458 and P:1912–1916.

The area-key choice—NOT NULL text, compared with `=`—fits the existing backbilling class/cause and deposit class/basis keys (`-13:674–702`; `-15:465–504`). It is not a wildcard mechanism. R3 states that limitation.

For deposits, the rewrite must explicitly distinguish **a utility’s customer-class code** from **a law classification**. Giving both columns the name `customer_class` causes the shared-key comparison to require equality at P:1705–1708. A city-local class will not automatically match a delegated row keyed by a different law class. Conversely, removing a shared key broadens comparison to all returned law classes. That is an area-design decision requiring a mapping or deliberate key design; the helper does not solve it.

Likewise, tariff coverage is accumulated across all matching law rows at P:1728. Where a tariff omits a law key such as deposit basis, coverage by one basis can cover a temporal gap in another. The area comparator must establish the intended domain and completeness, or the shared contract must be strengthened. The current single-class ZZ example does not demonstrate that case.

“Always cite law; optionally cite tariff” is the right model for the stated municipal delegation case. The defect is the incomplete record guard, not that decision.

`rule_row_seed` has a sensible **semantic identity** for ordinary migrated rows: state, service, applicability sets, area key and start; it compares document, end, citation, kind and version. Owner-array order is correctly irrelevant. See P:1990–2022.

Its limitations should be explicit:

- Supplied IDs are not part of sameness.
- Additional area columns and supplied facets are not compared on the existing-row branch.
- The existing-row branch does not revalidate the source against the schema or freeze status.
- Closing a database row requires updating the corresponding file’s end date before reseeding; the seed helper does not perform the close.

Those choices are reasonable for reviewed, generated law seeds, but “same row” should not be read as full-row equality.

The **-13 migration cannot safely rely on adoption as built**. It also must replace the old history trigger, which independently refuses adoption (`-13:866–870`), and verify legacy child-window terms as part of equivalence. Adding the new trigger alongside the old one is insufficient.

The **-15 rewrite can use the basic architecture**, but cannot preserve the inventoried published-rate scope or copy the fixture’s record-integrity pattern unchanged. B2, B4, B6 and B7 should be resolved first.

**Tests and mutation coverage**

The battery has a useful discipline: negative SQL tests match both SQLSTATE and a guard-specific phrase, and success tests reject NULL. See B:41–85. The race harness also requires the second session to be observed waiting, which prevents a sequential execution from masquerading as a race: `rule-close-17.sh:33–58`.

It does **not** test every guard with an input only that guard can reject:

- V10’s fractional version also exceeds its maximum: B:261–263.
- V13’s duplicate array item also duplicates a component ID: B:275–277.
- The exact error-list assertions still detect removal of those checks, but they are not independent acceptance/refusal cases.

More consequential missing cases are:

| Area | Missing case |
|---|---|
| Adoption | Valid document with different legacy meaning |
| Tariff concurrency | Close-first and close-plus-successor, with post-lock re-read |
| Inputs freezing | REPEATABLE READ old snapshot and both freeze orders |
| Facets | Reserved names, wrong SQL types, numeric typmod rounding, integer/boolean facet examples |
| References | Wrong-profile law, wrong-class law, wrong-tenant core FK, unknown component, citation update |
| Validator | Final newline, Unicode boundaries, deep/recursive schemas, large exact decimals, boolean const |
| Parser | Escaped duplicate names such as `"a"` and `"\u0061"` |
| Audits | `expected_by` without `expected_decision`; disposition integrity |
| Seeds | Different end, kind and version; additional-column expectations |
| Core privileges | Column-level matview SELECT and inherited privilege sources |
| Scenarios | Invalid domain input/output accepted by the outer-shape check |

W4’s mutations are document mutations around five hard-coded fixture examples, not systematic schema-feature combinations: `lawfiles-17.sh:43–48`, `lawc.py:417–476`. It does not validate that each tested schema is accepted by the database registry, and it supplies the file schema directly rather than checking equality with the stored registry schema.

The round-trip check establishes stored-`terms` equality with generated JSON and detects extra rows in participating tables. It does not serialize a stored row back into a law file and reparse it: `lawc.py:490–510`. That is useful coverage, but narrower than a literal file → database → file round trip.

The mutation harness contains 104 targeted patch mutations, but none targets W1–W5 despite having dispatch support for those labels. Its inputs-stamping mutations omit freezing and isolation: `mutations-17.py:287–297`. Mutation execution is also absent from `tests/ci.sh:79–89`. Consequently, the mutation catalogue does not establish that the tooling checks catch their own drift.

**Notes**

- I found no direct SQL-injection path in ordinary facet scope values: identifiers and values are quoted at P:1600–1603, and vocabulary relations are resolved during platform registration. All new functions are invoker-rights.
- The duplicate-key parser is appropriately placed before conversion to `jsonb`; ordinary tariff writers cannot bypass it by supplying only `terms`.
- Direct citation/close and ordinary rule/schema-freeze ordering are substantially better than the tariff and inputs exceptions identified above.
- The new role receives no default privileges, and the fresh-role grant path excludes materialized views. The concern in S1 is the incomplete assertion and preservation of pre-existing privileges, not an identified fresh-install matview grant.
- Deferred core execution and later-law audit generation are appropriate while the core does not exist. Missing database structures and missing schema checks should not be folded into that deferral.

Approval should wait for **B1–B8**, with targeted regressions demonstrating each corrected invariant.