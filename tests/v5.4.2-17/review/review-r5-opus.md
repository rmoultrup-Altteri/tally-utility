# v5.4.2-17 r5 — review (Opus)

**Artefacts:** patch `patch-17-frozen-r5.sql` md5 `d20d453c0aaecadb79ffdc0852d8cb56` (3120 lines), battery `battery-17-frozen-r5.sql` md5 `ea9bb460c10534fce95b9c5883e48904`. Both match the brief.

**Setup:** clone `opus17` from `tally`, TEMP revoked, patch strict-applied (`search_path=''`, `check_function_bodies=on`, `-1`). It applied cleanly and the patch's own tail assertion passed.

**Suite on the frozen artefacts (all run, all pass):**
- battery: 230 PASS, exit 0;
- `isolation-17.sh opus17 opus17iso`: X1–X6, 0 failures;
- `races/rule-close-17.sh opus17 opus17race`: RC1–RC7 all pass;
- `lawfiles-17.sh opus17 opus17law`: W1–W5 pass (W4: 899 documents, 0 disagreements).

I did not run the repo's mutation suite: it uses fixed database names that other reviewers may be using. Instead I ran my own targeted mutations of the r5 guards against the frozen battery, on a separate clone `opus17m` (section 3).

Probes were run as owner inside rolled-back transactions. Every `opus17*` database is dropped, and no probe role remains.

**Verdict: ready.** Nothing is blocking. The r4 fixes hold, and none of them opened a hole I could find. Three should-fixes:
1. most sub-clauses of the two new registration guards have no test that only they can fail (S1);
2. a law table can still be registered where the delegated document cannot be stored, through its facets or facet columns rather than its schema (S2);
3. the strategy rule does not require the strategy name to be a closed set (S3).

---

## 0. Round-4 findings in r5

| # | Probe (rolled back, on opus17) | Holds? |
|---|---|---|
| **B1** delegated branch exact (P:993–1011) | **Satisfiable variants all accepted:** `required` reordered; the branch inline with a `$comment`; the branch's `$ref` node carrying a `title`; no `note` property at all. **Unsatisfiable variants all refused** ("must admit {"governs": …}"): `required: ["governs","note"]` (citation optional, note required: the standard document fails); `maxLength` on `governs` or `citation` (R3d, R3f); a required note (R3e). `const` with `enum` on `governs` is refused one step earlier, by the subset | **Yes** |
| **B2** strategy version on every object (P:526–539) | **Refused:** `strategy` reached through `$ref` under array `items` (error at `/$defs/f`); `strategy` in the branches of a union discriminated by `kind` (error at `/properties/fee/oneOf/0`); an unused `$defs` object with `strategy`. **Accepted:** `strategy` and `version` both given as `$ref`s, with version bounded 1..2, and `1.0`/`2.0` as bounds. So a `$ref`, an array item and another discriminator are all reached. The check sits in the object case, which every path through `rule_terms_schema_node_errors` passes through (properties, items, oneOf branches, `$defs`) | **Yes** |
| **S1** seed applicability typed (P:2270–2283) | **Refused:** `"null"` as a string for `commission_jurisdiction` (22023); `[]` (by the span function: "non-empty"); a JSON-null `state_code` (no state place). **Same set:** a reordered `owner_types` re-seeds as the same row. **Distinct row:** `owner_types: null` vs a two-element set is a different row, and its insert is refused by the exclusion constraint. I found no value that still reads as "every one" | **Yes** |
| **S2** lawc lone surrogate in a key | W5 passes; `lawc.py:290–291` applies the same pattern to keys as to values (`:271`) | **Yes** |
| **S3** adoption wording | Header P:146–150 and R14 (P:3089–3091) name the adoption check | **Yes** |

**Earlier findings, re-checked on r5:**
- **My r3 S1 (core role membership)** is fixed. I granted a fresh BYPASSRLS role to `tally_core`, and `assert_core_role_invariants()` refused: "tally_core is a member of opus17r5_admin: it belongs to no role" (0LP01). It passes again after the revoke. K10 covers this.
- **My r3 N1 (seed id and omitted columns)** is fixed. A seed naming an `id` is refused (22023), and so is one omitting `source_note` (P:2263–2269).
- **The round-2 items the brief lists:**
  - facet-to-column type pairing (P:1448–1461, P:1613–1615, P:1775–1780);
  - depth under unions (P:690–693);
  - filled documents at adopting registration (P:1596–1608);
  - NUL and surrogates (J3: `\u0000` is refused, 22P02);
  - the reusable core invariant;
  - the freeze compared as text (P:944–945);
  - APPLY phrases.

  All still hold: their battery cases pass, the strict apply is clean, and the r5 diff does not touch them.
- **Duplicate-key parser:** a duplicate written through an escape (`{"a":1,"a":2}`) is refused (22030), and so is one nested in an array.

---

## Should-fix

### S1. The r5 guards' sub-clauses are mostly untested: 8 of 9 mutations survive the frozen battery
I applied each mutation to the frozen patch on a fresh clone (strict apply, TEMP revoked), then ran the frozen battery.

| Mutation (one clause removed) | What it opens | Result |
|---|---|---|
| m1: `(v_core -> 'required') @> '["citation","governs"]'` (P:1002) | `required: ["governs","note"]` registers, and the delegated document can never validate. This is **B1 again** | **SURVIVED** |
| m2: `required ? 'version'` (P:528) | A strategy whose `version` is optional | **SURVIVED** |
| m3: `minimum < 1` (P:534) | A version range starting at 0 | **SURVIVED** |
| m4: `jsonb_typeof(minimum) = 'number'` (P:530) | No lower bound at all. The rest of the OR chain then goes NULL, so nothing raises | **SURVIVED** |
| m6: integer `minimum` (P:532) | A fractional lower bound. M140 covers only the maximum | **SURVIVED** |
| m5: properties `<@ {citation, governs, note}` (P:1004) | An extra optional property on the delegated branch. Exactness only, not satisfiability | SURVIVED |
| m8: `(v_core - required - properties) = {type, additionalProperties:false}` (P:1001) | Nothing: the subset already pins the branch to these keywords, so this mutation is equivalent | SURVIVED |
| m9: annotations no longer stripped from `citation` (P:1007) | Over-refusal of an annotated citation. R3g annotates `governs` and `note`, never `citation` | SURVIVED |

(m7, the `note` clause, was not run: my anchor did not apply. That clause guards exactness, not satisfiability, since `note` is optional.)

On the unmutated patch:
- m1's case is refused (probe D1);
- m5's case is refused (D2: an extra optional `memo`).

So the guards act; the battery just cannot tell. m1–m4 and m6 each reopen a hole that r5 or r2 closed, and the memory rule "a guard is tested by a case only it can refuse" applies.

**Fix:** add refusal cases, each with the guard's own phrase:
- R3h: `required ["governs","note"]`;
- R4s: version not required;
- R4t: `minimum: 0`;
- R4u: no `minimum`;
- R4v: `minimum: 1.5`.

Add an accepting case for an annotated `citation`, and name each new case as the killer of a matching M-mutation. m5 and m8 can stay untested if the header says the exactness beyond satisfiability is defence in depth.

### S2. A law table can still be registered where the delegated document cannot be stored, through its facets rather than its schema
B1 is now closed at the schema. The same outcome, a law table where `{"governs":"delegated_to_utility","citation":…}` can never be inserted, is still reachable through two parts of registration.

1. **A `strict` facet path.** `enforce_rule_term_facet` (P:1086–1150) bans only `.datetime()` and `.double()`. I registered a copy of `zz_fee` with the facet `fee_cap number 'strict $.fee.cap'`, and the table registered. A delegated seed is then refused: `2203A JSON object does not contain key "fee"` (raised from `jsonb_path_query_array` in `rule_terms_facets`, P:1174). A facet whose type does not fit what its path matches in the delegated document (for example `$.citation` declared `integer`) fails the same way, from P:1192–1200.
2. **A NOT NULL facet column.** `rule_facet_column_errors` (P:1448–1461) pairs facet and column types but not nullability. I gave `fee_cap numeric` the NOT NULL constraint and the table registered (P:1613–1615). A delegated seed is then refused: `23502 null value in column "fee_cap"`. Every non-`present` facet is NULL on the delegated document, by construction.

Both failures are loud at the first delegated row, and P:1209 already calls a facet/schema disagreement "a registration defect". But B1 was folded because a law kind must provably admit delegation (V8), and for the launch customers (city-owned systems, all delegated) this is the only row they will ever cite.

**Fix:** at `rule_table_register` for a law table (and in `rule_row_prepare` for a later version's first row, where facet types are already re-checked), do two things:
- run `rule_terms_facets(kind, v, '{"governs":"delegated_to_utility","citation":"x"}')` inside a BEGIN/EXCEPTION block and refuse on error;
- require every facet column other than `present` to allow NULL.

One battery case each.

### S3. The strategy rule does not require a closed set of strategy names
Probe B2d registers a tariff kind with `"strategy": {"type": "string"}` plus a bounded `version`. Any strategy name then validates.
- Convention v2 §4 says: "The set of names is closed and registered (§5). A row cannot name a strategy the core lacks."
- §5 lists "a strategy not registered for that decision point" among the documents it refuses.
- Inventory §3.2 says strategy-like codes go in the schema.

Inside a union, the discriminator rule already forces a `const`. A lone strategy, the case B2 just brought into the rule, does not.

**Fix:** in the same block (P:526), require the resolved `strategy` schema to be a string with `const` or `enum`. This is one more clause and one refusal case.

---

## Notes
- **N1. The delegated branch must be written inline, and the refusal does not say so.** The check also refuses satisfiable branches: a `citation` that is `{"$ref": "#/$defs/citation"}` (the way the fixture's own *law* branch writes it, `zz_fee.v1.schema.json`); `citation` with `minLength: 1`; `note` with `maxLength: 0`. Each is refused with the same generic message, "must admit {"governs": "delegated_to_utility" …}". That is defensible for "exactly the standard document", but the -13/-15 authors will naturally reuse `$defs/citation`.
  - **Cheapest:** make the message say "exactly the standard branch, written inline: …".
  - **Alternative:** resolve a `$ref` for each property before comparing.
- **N2. The version rule is keyed on the property name `strategy`.** A selector named `method` (B2e) is outside the rule. The name is the convention's own (v2 §3 examples, inventory V5), so this is consistent, but `law/README.md` could say that the name is what makes it a strategy.
- **N3. The version check does not test satisfiability.** `minimum 1, maximum 1, exclusiveMaximum 1` registers with no valid version (B2f). Unlike the delegated branch, an unsatisfiable tariff shape is the author's problem, so this is a note only.
- **N4. The seed does not type its dates.** `effective_from: 20280101` (a number) inserts as 2028-01-01. A re-seed with the canonical string then matches the same row, and a re-seed repeating the number is refused as "different" (fails closed). lawc always emits strings, so nothing is wrong today.
- **N5. Precomposed and decomposed forms of a key are distinct keys.** `{"é":1,"é":2}` parses with both keys. Standard JSON and Python do the same, so W4 cannot disagree. Mentioned only because a law file could carry two visually identical keys. lawc could refuse a key that is not NFC.

---

## 1. The spec
- **Step-2 items:** my r3 table stands: every Step-2 requirement is held or recorded as a residual.
- **V8 and V5:** the r5 changes strengthen both. V8: with S2, fully at registration. V5: with S1's tests and S3, as the convention words it.
- **-13 and -15 can use this as built.** The r5 changes affect only how area schemas are written:
  - the delegated branch goes inline, as the fixture writes it (N1);
  - every object with `strategy` carries `version`, waiver `effect` strategies and -13's `anchor` included, which is what V5 asks.
- **Template choices:** unchanged since r3, and still right for both consumers:
  - spans as sets with NULL = every one;
  - the area key NOT NULL, compared with `=`;
  - the law row cited always, a tariff row optionally;
  - the tariff checked against law rows that share its key;
  - the adoption check split from the insert check;
  - the seed's "same row".

## 2. Integrity
Nothing new found beyond S2, which is the only new way I found to reach a state the header's intent refuses.
- **Parser:** sound for escapes and nesting.
- **Seed:** typing is complete, and the r3 N1 gaps are closed.
- **Core role:** the invariant now covers membership.
- **Dynamic SQL in the paths I re-read** (vocabulary scope, the insert-check call, the seed WHERE): every value passes through `%L`/`%I`/`USING`. The `regproc` call to the insert check cannot resolve to a pg_temp function.

## 3. Tests
- The battery, isolation, races and law files all pass on the frozen artefacts.
- **Gap:** S1. The r5 guards are tested at the whole-guard level (M112, M141–M148), but not clause by clause, and five surviving clauses each reopen a closed hole.
- **W4** proves agreement on documents, not on registration; that is recorded, and is why S1's cases belong in the battery.
