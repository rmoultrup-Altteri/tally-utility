# v5.4.2-17 r6 — review (Opus)

**Artefacts:** patch `patch-17-frozen-r6.sql` md5 `e56f35010b3697680cff673cf44cbd8e`, battery `battery-17-frozen-r6.sql` md5 `f65867baaf103dd589c581520cd5228f`. Both match the brief. The repo copies (`sql/v5.4.2-17-rule-terms-convention.sql`, `tests/v5.4.2-17/battery-17.sql`) have the same hashes.

**Setup:** I cloned `opus617` from `tally`, revoked TEMP, and strict-applied the patch (`search_path=''`, `check_function_bodies=on`, `-1`). It applied cleanly, and the tail assertions passed, including the new `assert_rule_table_invariants()`.

**Suite on the frozen artefacts (all run, all pass):**
- battery: 247 PASS, exit 0;
- `isolation-17.sh opus617 opus617iso`: X1–X6, 0 failures;
- `races/rule-close-17.sh opus617 opus617race`: RC1–RC7 all pass;
- `lawfiles-17.sh opus617 opus617law`: W1–W5 pass.

**Mutations:** I ran a private copy of `mutations-17.py` with the database names changed to `opus6m*`. I ran the r6 mutations M149–M166 plus five of my own (O01–O05) against the trigger rule. The result was 20 of 23 caught. All 18 of the r6 mutations were caught, each at its named check. Of my five, O04 and O05 were caught at their named checks, and O03 was caught by T1k rather than the check I named. O01 and O02 survived (see S3).

**Probes:** each probe ran inside the battery's own transaction (battery lines 1–560, then my probe, then ROLLBACK), with every probe statement in a subtransaction that is always undone. Every `opus6*` database is dropped.

**Verdict: ready.** Nothing is blocking. Every round-5 fix holds and acts. Three should-fixes:
- **S1.** The new trigger invariant checks template triggers by name only. An inheritance child or a rewrite rule on a registered table is outside it. I reproduced a lookup returning a never-validated row through a child table. Owner DDL only.
- **S2.** The delegated dry-run tries only the document without a note. A delegated document with a note can still be unstorable.
- **S3.** `COLLATE "C"` in the trigger rule is load-bearing (the database collation is `en_US.utf8`), and no test can fail without it.

---

## 0. Round-5 findings in r6

| r5 finding | Probe (rolled back) | Holds? |
|---|---|---|
| **Opus S1** (clause tests) | M149, M151, M152, M153, M154 each caught at R3h / R4s / R4t / R4u / R4v | **Yes** |
| **Opus S2** (facets vs the delegated document) | M156–M158 caught (T1o, T1n, T1p). **F4:** an *adopting* law table whose kind has a `strict $.fee.cap` facet is refused at registration ("facets cannot be derived from the standard delegated document"). The per-version loop at P:1716–1721 runs for adopting tables too. **F3:** a NOT NULL *domain* as the facet column is refused one step earlier, by type pairing (`zz_nn_num` is not `numeric`) | **Yes**, with two gaps: S2 (the note) and N1 (CHECK constraints) |
| **Opus S3** (closed strategy names) | M155 caught (R4w); R4x accepts an enum | **Yes** |
| **Fable S1 / Opus N1** (delegated `$ref`s) | Results below the table | **Yes** |
| **Fable S2** (late triggers) | Results below the table | **Yes** for what it names; see S1 |
| **Codex S1** (blank key) | M163 caught (T4a2). **B1b/B1c:** filling an adopting table's legacy row whose key is `' '` or `'—'` is refused (22023), because the fill goes through `rule_row_prepare` (P:2179). **B2:** a key of `é` is accepted. `[[:alnum:]]` under en_US counts it as alnum, and lookup uses the same `rule_key_check`, so the two agree | **Yes**; see N3 for legacy rows |
| **Codex S2** (infinities) | **I1–I4:** `'inf'`, `'+Infinity'`, `'-inf'` and `'INFINITY'::float8::numeric` are all refused by the trigger, with the finite-value phrase. **I5:** a `value_min` of `'-inf'` is refused by `rule_parameters_range_check`. **I6:** `1e400` (finite) is accepted, which is correct. `NOT IN` compares numerically, so the spelling cannot matter | **Yes** |

**Fable S1 / Opus N1 probe results (delegated `$ref`s):**
- **D4:** `note` as `{"$ref": …, "description": …}` to a def with a `title` registers.
- **D5:** `citation` as a `$ref` to a def that adds `maxLength: 1` is refused.
- **D1:** `citation` as a `$ref` to a def that is a `oneOf` union is refused ("must admit …"). The resolved node is `{oneOf: …}`, which is not the standard node.
- **D2:** a two-def `$ref` cycle is refused by the subset ("a definition may not be a reference", "chains are refused").
- **D3:** `governs` as a `$ref` (to exactly `{type: string, const: delegated_to_utility}`) is refused earlier, by the discriminator rule. `rule_terms_discriminator` (P:373) reads `properties.<k>.const` without resolving. This is consistent with every union, so over-refusal only (N5).
- **D6:** a self-recursive def (`rec.properties.x → rec`) in the law branch registers. Validating a document against it terminates.

**Fable S2 probe results (late triggers):**
- **G5:** `rule_row_historz` is refused.
- **G6:** `rule_row_insert_x` on UPDATE is refused.
- **G4:** `"Zz_upper"` is accepted, and correctly so: in C order it sorts, and therefore fires, before the template.
- **G7:** an AFTER ROW trigger and a BEFORE STATEMENT trigger with late names are both accepted, which is correct. An AFTER trigger's UPDATE of the row goes through `rule_row_history`.

**Round-2 findings** (B1 facet-to-column types, B2 depth under unions, B3 filled documents at adopting registration; NUL and surrogates, the reusable core invariant, the freeze hash, isolated guard cases, APPLY phrases):
- The r6 diff does not touch any of them.
- Their battery cases pass on r6, and the strict apply is clean.
- My r5 re-checks of each stand.
- No r6 change opened a hole in them. The new per-insert dry-run (P:1888–1890) runs inside `rule_row_prepare` after validation, and uses no dynamic SQL.

---

## Should-fix

### S1. The trigger invariant identifies the template's triggers by name, and a registered table can still route rows around them
`rule_table_trigger_errors` (P:1490–1508) requires three triggers *named* `rule_row_insert`, `rule_row_history` and `rule_row_no_truncate`, each `tgenabled = 'A'`. It does not check their function, their timing or their events. It also exempts those two names from the sort rule (P:1501).

**Reproductions** (owner DDL on the registered `zz_fee_rules`, the same class as Fable S2):
- **G1.** Drop `rule_row_insert`, then recreate it under the same name on `zz_noop_trg()` with ENABLE ALWAYS:
  - `assert_rule_table_invariants()` passes;
  - an INSERT with `terms_source = 'not json'`, `terms = {"x":1}` and `fee_cap = 1` is accepted.
- **G2.** Recreate `rule_row_history` as BEFORE **INSERT** on a no-op:
  - the assertion passes;
  - `UPDATE … SET terms = '{"x":1}', fee_cap = 1` of law row lr1 is accepted. That is an edit of a law row.
- **G3.** `CREATE TABLE zz_child () INHERITS (zz_fee_rules)`, then insert a row with `terms_source = 'nonsense'` and `terms = {"x":1}`, owner type municipal, class `industrial`:
  - the assertion passes;
  - `rule_law_row_as_of('public.zz_fee_rules', <T1>, 'gas', 'distribution', 'ZZ', {"customer_class":"industrial"}, 2020-01-01)` **returns the child row's id**, with terms `{"x": 1}`.

  The parent's triggers do not fire on an insert into the child. Exclusion constraints are not inherited. Every dynamic read uses `FROM %s t` without `ONLY`:
  - lookups (P:2259, P:2337);
  - the tariff check (P:2062);
  - cite (P:2218);
  - audit subjects (P:2887, P:2903).

  So a lookup returns a row the template never validated, instead of refusing. (The ZZ charge FK to the parent would then refuse to cite it, but the lookup's answer is already wrong.)
- **G8.** `CREATE RULE … ON INSERT TO zz_fee_rules DO INSTEAD NOTHING`: the assertion passes, and every insert or seed then silently writes nothing.

**Why should-fix, not note:** r6 adopted Fable S2's principle: "nothing may change a row after the template checked it", asserted in the tail and in CI. As written, the assertion certifies a property that it does not check. That is the "check narrower than its claim" pattern: the CI line goes green on every one of G1–G3 and G8.

**Fix** (all in `rule_table_trigger_errors`, so registration and the assertion share it):
- **(a)** For each template name, require its function and type exactly:
  - `rule_row_insert`: `tgfoid = 'enforce_rule_row_insert'::regproc` and `tgtype = 7` (ROW, BEFORE, INSERT);
  - `rule_row_history`: `enforce_rule_row_history` and `tgtype = 27` (ROW, BEFORE, UPDATE, DELETE);
  - `rule_row_no_truncate`: `enforce_rule_registry_no_truncate` and `tgtype = 34` (BEFORE, TRUNCATE).

  Also require `tgqual IS NULL`, since a `WHEN` clause would make the template conditional.
- **(b)** Refuse a table that is any `pg_inherits.inhparent`.
- **(c)** Refuse a table with any `pg_rewrite` rule on it.

Add one battery case each, killed by its own mutation. Using `FROM ONLY %s` in the reads is defence in depth, but (b) is the guard.

### S2. The delegated dry-run tries only the note-less document; a delegated document with a note can still be unstorable
`rule_law_delegated_facet_errors` runs the facets on `{"governs": "delegated_to_utility", "citation": "x"}` (P:1549). The standard document (P:996–998, and the branch the registry requires at P:1028–1030) also admits a `note`. The fixture's own delegated example carries one ("Cities set their own fees.").

**F1:** I declared a law kind with the facet `note_n integer '$.note'` and gave the table an `integer` column.
- **F1a:** it registers.
- **F1c:** a delegated row without a note inserts.
- **F1b:** a delegated row **with** a note is refused: `22000 facet note_n … matched "Cities set fees.", not a integer`.

The same holds for any facet whose path reaches `note`, or `citation` with a non-`"x"` shape (a `text` facet on `$.**.note` alongside another match, for example).

**Fix:** run the dry-run on both documents, `{governs, citation}` and `{governs, citation, note}`, and apply the NOT NULL test to each. One battery case: F1 as written.

### S3. Two clauses of the trigger rule have no test that only they can fail
- **O01 survives:** dropping `COLLATE "C"` from P:1500. The database collation is `en_US.utf8`, where punctuation and case are ignored at the first level. So the clause is load-bearing:
  - `'rulerowa' >= 'rule_row_history'` is **false** under en_US, but **true** under C. In C, `r` (0x72) sorts after `_` (0x5F), so a trigger named `rulerowa` fires after the template. Without `COLLATE "C"` the rule would let it through.
  - Conversely, `'Zz' >= 'rule_row_history'` is true under en_US but false under C. The mutation would also over-refuse `Zz_…`.

  T1i's `zz_late` sorts after under both collations, so no case can tell them apart. **Fix:** add a refusal case for a trigger named `rulerowa` (sorts after in C, before in en_US), and an accepting case for `Zz_early` (sorts before in C).
- **O02 survives:** dropping the BEFORE bit `(t.tgtype & 2) = 2`. AFTER triggers with late names would then be refused. That is over-refusal only. **Fix:** add an accepting case: an AFTER ROW trigger named `zz_after` registers and passes the assertion. This also pins down G7's correct behaviour.
- **O03** (dropping the ROW bit) is caught, but by T1k, through `rule_row_no_truncate` (a statement trigger), not by T1j. The mutation file's check name would need changing if it were added.

---

## Notes
- **N1. A CHECK constraint on a facet column is outside the dry-run.** F2: `CHECK (fee_cap IS NOT NULL)` registers. A delegated row is then refused, `23514 violates check constraint "zz_f2_cap"`. The same goes for `CHECK (cardinality(component_ids) > 0)` against the `[]` a text[] facet gets.
  - It fails loudly at the first delegated row, and an area author would have to write it on purpose.
  - Either say in the comment at P:1534 that only `attnotnull` is tested, or (stronger) have the dry-run insert the delegated row into the table inside a subtransaction, with placeholder key and template values, and roll it back.
- **N2. A facet path with an unbound variable registers.** F6: `$.fee.cap ? (@ > $lim)`. The dry-run passes because lax `$.fee` matches nothing on the delegated document, so the filter is never evaluated. Every law-branch row then fails with `42704` (not a `data_exception`, so it propagates raw). `enforce_rule_term_facet` (P:1127–1143) could refuse a path containing a `$name` variable, since `rule_terms_facets` never passes `vars`.
- **N3. An adopting table's legacy rows with a blank key register, but can never be adopted.** B1a: registration accepts legacy rows keyed `' '` and `'—'`.
  - The fill is then refused (B1b, B1c), which fails closed.
  - A close is still accepted (B1d).
  - No lookup or seed can address these rows, but they still occupy the exclusion.

  Registration could list them (one `EXISTS … WHERE key !~ '[[:alnum:]]'` per area-key column, as it already checks for filled documents at P:1704–1710), so the -13 migration finds them before its fill step rather than in it.
- **N4. A facet that fits the delegated document but not the law branch registers.** F5: `cap_text text '$.fee.cap'`. Every law-branch row then fails with `22000`. P:1228 already calls this "a registration defect, not data", and it is loud. Recorded only because the dry-run's existence might suggest registration checks facets against the schema in general; it does not.
- **N5. A discriminator must be an inline `const`.** D3: `governs` written as a `$ref` is refused, with the generic message "a oneOf needs exactly one property that every branch requires with a string const". `law/README.md` could say that discriminators (`governs`, `strategy` inside a union) are written inline, unlike `citation` and `note`, which may now be references.

---

## 1. The spec
- **Step-2 items:** my r3 table stands. Every Step-2 requirement is held or recorded as a residual (R1–R21). The r6 changes strengthen:
  - **V5:** a strategy is a closed set;
  - **V8:** delegation is storable as well as valid, subject to S2;
  - **T1:** no post-validation rewrite, subject to S1.
- **-13 and -15 can use this as built.** I checked the r6 trigger rule against the consumers:
  - **-13:** the triggers that `backbilling_rules` and `backbilling_rule_window_terms` carry, in `sql/tu.sql:24205`, `:24267`, `:24304` and `:24332`, are all `a_…`, so they sort before the template and registration accepts them. `a_enforce_backbilling_rule_history` (BEFORE UPDATE) would still refuse the adoption fill, and R14 step 3 already says the migration drops it.
  - **-15:** the draft's rule tables also use only `a_…` names (`sql/v5.4.2-15-deposits-law-to-core.sql:750`, `:825`, `:917`, `:942`, `:1201`).
  - **Strategies:** -13's `anchor` and -15's deposit strategies need a `const` or `enum`, which is what both drafts' unions already give.
- **Template choices:** unchanged since r3, and still right for both consumers:
  - spans as sets with NULL = every one;
  - the area key NOT NULL and compared with `=`, now also non-blank at write (Codex S1), which -13's and -15's text keys satisfy;
  - the law row cited always, a tariff row optionally;
  - the tariff checked against law rows that share its key;
  - the one-time adoption;
  - the seed's "same row".

## 2. Integrity
- The only way I found to make a lookup return a wrong row instead of refusing is S1/G3: owner DDL that the new invariant was meant to catch and does not.
- I found nothing reachable by `tally_app` or `tally_core`.
- The new functions are invoker-rights, with a pinned `search_path`. `assert_rule_table_invariants` is revoked from PUBLIC, `tally_app` and `tally_core`.
- The dry-run's subtransaction catches only `data_exception`. Any other error (N2) still refuses, just with a raw message.
- The infinity guard and CHECKs are numeric comparisons, so no spelling escapes them (I1–I5).

## 3. Tests
- Every r6 guard has a case only it refuses: M149–M166 are all caught at their named checks.
- The gaps are S3, where the collation clause and the BEFORE clause have no test, and the cases S1 and S2 call for.
- W4 still proves agreement on documents, not on registration (recorded). This is why the registration clauses need battery cases.
