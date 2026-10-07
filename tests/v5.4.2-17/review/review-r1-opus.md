# v5.4.2-17 draft r1 — review (Opus)

**Artefacts checked:** patch md5 `bf006d2a6722035d928e34177fdf60a0` (2558 lines) and battery md5 `43c4132fb4ed8d2cdebfd77c30429c15`. Both match the brief, and both match `sql/v5.4.2-17-rule-terms-convention.sql` and `tests/v5.4.2-17/battery-17.sql`.

**Probe setup:** clones `opus17` (fixture committed) and `opus17b` (clean), each strict-applied from `tally` with TEMP revoked. On `opus17b` the full suite passes:
- battery: 177 PASS;
- isolation X1–X5;
- races RC1–RC4;
- law files W1–W5.

**Verdict: not yet.** Two blocking items, both cheap to fix. The machinery is otherwise sound and fits the -13 migration and the -15 rewrite. The validator subset is careful, and the close/cite and freeze/insert handshakes are right in both orders.

---

## Blocking

### B1. The tariff-against-law check reads the law rows, then locks them, and never re-reads
`rule_tariff_check` (patch 1716–1730) runs the law-row query first and only afterwards takes each row's lock shared (1727). The header (66–68, 1677–1680) and the function comment (1753) claim "each law row's lock is taken shared, so a close of it waits". That holds only when the tariff locks first.

When the close comes first, the tariff reads the pre-close row from its snapshot, blocks on the lock, then proceeds with stale law.

**Reproduction (opus17, two sessions):**
- Law A: investor_owned, residential, from 2000, cap 50.
- Session A (owner): `BEGIN; UPDATE zz_fee_rules SET effective_to='2025-01-01'` on law A; inserts law B (from 2025, cap 10); sleeps 3 s; `COMMIT`.
- Session B (tally_app, T2), started 1 s later: inserts a residential tariff from 2020 with amount 40.
- B was seen waiting on a Lock. After A committed, B's tariff was **accepted**. It was compared only with law A.
- The same tariff inserted sequentially is refused: `looser than the law: fee 40 above the cap 10 of law B`.

So a tariff looser than the law in force when it was written is stored. The header lists that as refused (112). This is the exact shape memory `count-guards-need-lock-handshake` warns about: lock, then re-read.

**Fix options:**
- After taking the shared locks, re-run the query with a fresh statement snapshot. If the set of ids differs, loop or refuse.
- Or take one coarser lock that every law-row insert and close takes exclusive, keyed by (law table, state, service).

**Tests:**
- Add an RC5 leg: a tariff against a close plus successor in flight, in both orders.
- Add a mutation that drops the lock. Today no check names it (M66–M69 are all single-session).

### B2. Two Step-2 requirements are neither held nor recorded as residuals
- **P1, the scope of a published value.** The spec asks for a typed scope of state, service **and customer class**, each NULL = all. -15's `deposit_interest_rate_law` is keyed by class (15:1138–1163). `rule_parameters.scoped_by` allows only `{}`, `{state_code}` or `{state_code, service_type}` (patch 2068–2069). P1 also asks for "a unit from a vocabulary"; `unit` is a free code (2065).
- **C3, dispositions.** The spec asks for "dispositions as separate append-only rows". The patch's table comment says "Who acts on a finding, and how that is recorded, is each area's design" (2380). Section 11 has no residual for it.

Either build them, or add a residual each with the reason (and Ryan's agreement, since the inventory classed them Step 2). Per `source-inventory-first-triage-by-rule`, a Step-2 item may not silently disappear.

---

## Should-fix

### S1. The whitelisted code pattern does not mean the same in Python
`^[a-z][a-z0-9_]*$` (patch 345) is claimed to "mean the same in ECMA-262, Python and PostgreSQL" (342–344). It does not. Python's `$` also matches before a trailing newline, and jsonschema 4.23 uses `re.search`.

**Reproduction:**
- `{"c": "abc\n"}`: jsonschema says valid; `rule_terms_errors` says `/c: does not match`.
- `lawc crosscheck` with an example whose `fee.id` is a YAML block scalar (`id: |` → `"t1\n"`) reports **6 disagreements**.

A law file can therefore pass `lawc check` and fail at seed. The direction is safe (the database is stricter), but the V9/V10 claim is false, and the W4 corpus never generates such a string.

**Fix:** add a fixed rule, in both implementations, that refuses control characters (U+0000–U+001F) in every string. That closes the only divergence of `$`, and the NUL case too (N4). Also add a newline mutation to `lawc.mutations()`.

### S2. W4 is narrower than it claims
- `lawfiles-17.sh` hardcodes the three ZZ schemas and examples. A -13 or -15 schema is never cross-checked unless someone edits the script. Discover them instead: every `law/**/<kind>.vN.schema.json` with `examples/`. Fail when a registered schema has no examples.
- The mutation corpus (`lawc.py` mutations) varies values by type and edge, but never covers:
  - strings at pattern edges (newline, non-ASCII letters);
  - lengths around `maxLength`;
  - depth beyond 64;
  - a discriminator switched to *another valid* branch value;
  - an `id` repeated across branches.
- The "reference" result includes `fixed_rule_errors()`, a Python re-implementation of the database's own three fixed rules. Those three rules are therefore checked against a second copy of themselves, not an independent validator.

The patch's R7 states this honestly. The README's "This proves the database enforces what the schema says" overclaims and should match R7.

### S3. Registration accepts facet columns that are template columns, and does not check facet column types
`rule_table_register` checks only that each facet column exists (1414–1418). The two probes below were rolled back.
- **A template column as a facet.** A kind with a `text` facet named `terms` (path `$.st`) on a tariff table: the insert stored `terms = "Ord 9"`, a JSON string rather than the validated document. In `rule_row_prepare`, `v_out := {'terms': v_terms} || v_facets` (1613), so the facet wins. Naming `tariff_reference`, `state_code` or `tenant_id` lets the document decide those columns.
- **A mistyped facet column.** A `text[]` facet whose column is `text` stored the JSON text `["a", "b"]`, silently.

**Fix:** registration refuses facet columns that are template, key or span columns. It also checks the column type for each facet type:

| Facet type | Column type |
|---|---|
| text | text |
| text[] | text[] |
| integer | integer or bigint |
| number | numeric |
| boolean, present | boolean |

### S4. A table's facet set is frozen forever
`rule_row_prepare` requires a version's declared facets to equal the table's `facet_columns` exactly (1572). `rule_tables` is never edited (1271–1288). So no later version of a kind can add or drop a facet. That is the breaking change v2 §11 versions are for, and -15's seven facets (F5) are likely to grow.

Either record it as a residual, with the consequence (a new facet means a new table), or provide a sanctioned extension path like T6: an appended facet column, plus a one-time fill of the existing rows' new facet.

### S5. The U4 citation pattern does not check that the cited law row is the one for the citing utility
`rule_row_cite` checks only existence, visibility and in-force-ness (1842–1868), and the fixture's `zz_charge_cites` uses only that.

**Reproduction:** as T1 (municipal), insert `zz_charges` citing law A, the investor-owned cap row. It is accepted.

-15's deposits will copy this pattern. Provide `rule_law_row_cite(table, id, tenant, service, system_kind, state, key, on)`, which asserts `id = rule_law_row_as_of(…)` and then takes the lock. Use it in the fixture and add a negative test.

### S6. T6's "document equals the old typed columns" check exists only by implication
The adoption path calls the area's `insert_check` with the whole row, legacy columns included, through `rule_row_prepare` (1641–1643, 1819). So -13 can compare there. Facets that keep a legacy column's name are compared automatically.

But neither the header nor the history-trigger comment says this is where §4A's equality check lives, and the battery's adoption test (A2) never checks it. `zz_legacy_rules.legacy_cap` is never compared.

**Fix:** state it in the header, and add a test where adopting a document whose cap disagrees with `legacy_cap` is refused by the hook.

### S7. The fixed "component ids unique" rule also applies to inputs documents
`stamp_core_inputs` runs `rule_terms_errors` (2273), which refuses any repeated `"id"` string anywhere (737–748). In an inputs document `"id"` is not a component id. For example, two reads of the same meter, `{"reads": [{"meter": {"id": "m1"}}, {"meter": {"id": "m1"}}]}`, would be refused, and a numeric id is refused outright.

**Fix:** apply the rule to law and tariff roles only, or mark component ids in the schema (a `$defs/component_id` convention) and check those.

### S8. `stamp_core_inputs` does not assert READ COMMITTED
It takes the version's lock shared, then reads the schema (2260–2262). It never calls `assert_rule_read_committed`.

Under REPEATABLE READ with an earlier snapshot, a freeze that has already committed is not seen, and a row of a frozen inputs version is accepted. Rule-row inserts guard against this; add the same call here.

### S9. A tariff with the utility's own classes cannot meet a delegated law row
`rule_tariff_check` filters law rows on every key column the two tables share (1705–1709). Under U5, a city's tariff classes are its own codes, so they never equal a statutory class. No delegated row then matches, and the tariff is refused ("no law is known").

Separately, with R3 (no "every value" in an area key), a delegated row must be written once per statutory class. For -13's key (class, cause), that is classes × causes rows.

Neither is wrong for step 2, but -15's rewrite needs to know. Extend R3 to say that a tariff whose key vocabulary is the utility's own must not share that column name with the law table, and that the comparator then picks the law rows itself.

### S10. Missing negative tests (each a guard only it would catch)
- `rule_applicability_ordinals`: an edit, a delete, an unknown code. There are none.
- `rule_parameter_values`: a close by a role that does not see every tenant, and a second close.
- `stamp_core_inputs`: a frozen inputs version; a table missing the columns.
- `rule_term_facets` and `rule_tables`: a delete. F3 and T2c test edits only.
- `rule_tariff_row_as_of`: its argument refusals.
- `rule_row_prepare`: a vocabulary scope column the rule table lacks.
- F7: a record citing a component (`'p1' = ANY(component_ids)`). The pattern is never exercised.
- The race leg from B1, and the registration negatives from S3.

---

## Notes

- **N1. TEMP.** Section 1 revokes TEMP from `tally_core` directly (173), which is a no-op. The real protection is tu.sql's `REVOKE TEMP … FROM PUBLIC` (tu.sql 18694). Add an assertion to the apply: `NOT has_database_privilege('tally_core', current_database(), 'TEMP')`. Battery K1 checks it, but the patch should refuse to apply without it.
- **N2. The C4 fingerprint is sha256 of PostgreSQL's jsonb text.** That text orders keys by length, then bytes: `{"bb":1,"a":2}` → `{"a": 2, "bb": 1}`. It uses `", "` and `": "` separators. The C# core must reproduce it to "confirm" a fingerprint, and lawc's canonical `dumps()` is a different form. Document the serialisation and add a test vector, or hash a defined canonical form (RFC 8785).
- **N3. Exponents.** The database accepts `1e2` (stored as `100`; canonical after normalisation). lawc's fixed rule refuses `Decimal('1E+2')` in a JSON example as non-canonical, so the two disagree on JSON-sourced documents. The README's "stores … exactly what is written" is not quite true either.
- **N4. NUL.** `rule_terms_parse('{"a":"\u0000"}')` refuses with "repeats a key" (22030): the right refusal, the wrong message.
- **N5. Depth.** The validator refuses documents nested deeper than 64 levels (576); the reference validator has no such limit. Mention it in R7.
- **N6. P3 references are unchecked.** A document's `{"source": "published", "name": …}` is not checked against `rule_parameters`. A `text[]` vocabulary facet on `rule_parameters.parameter_name` would do it; the README could say so.
- **N7. L1 and L3 differ from the spec.** L1: lawc does not enforce one file per (kind, state, service, owner type); the README says per state and service. L3 asks for scenarios to be "schema-checked"; they are shape-checked only, though the inputs kind exists to check them against.
- **N8. -13 re-seeding.** Once the -13 rows are adopted, a law-file seed must reproduce each legacy `source_note` byte for byte, or `rule_row_seed` raises.
- **N9. Seed defaults.** `rule_row_seed` inserts `jsonb_populate_record(NULL::t, …)`, so an area column with a DEFAULT gets NULL instead of its default.
- **N10. CI dependencies.** CI installs them without `--require-hashes`.
- **N11. Facet paths.** A facet path may use `.double()`, which is inexact; consider refusing it like `.datetime()`.

---

## 1. The spec, requirement by requirement (Step-2 items)

| Req | Status |
|---|---|
| V1 registry, freeze, never deleted | Held |
| V2 kind per table (CHECK + FK) | Held |
| V3 checks | Held, including unions and canonical numbers. Rationals are expressible as `{num, den}` objects |
| V4 unions | Held |
| V5–V7 format rules | README only. That is acceptable, since they are format rules |
| V8 delegated document | Held: enforced at registration |
| V9 refuses unenforced keywords | Held, except the pattern divergence (S1) |
| V10 cross-check | Partial (S1, S2) |
| F1–F3 | Held |
| F3 vocabulary dynamic SQL | Safe: `%I`, `%L`, regclass text |
| F4 | Held (`insert_check`) |
| F7 | Pattern not demonstrated (S10) |
| T1, T2, T3, T5 | Held |
| T4 | Held for citation against close |
| T4 for the tariff check | **Broken (B1)** |
| T6 | Held mechanically; the equality check is implicit (S6) |
| T7 | Residual R2 |
| U1, U2 | Held. `IS JSON … WITH UNIQUE KEYS` catches nested, in-array and escaped (`"a"` / `"a"`) duplicates |
| U3 | Held, except B1. A later law change gives an audit finding (R6) |
| U4 | Pattern weak (S5) |
| P1 | **Partial (B2)** |
| P3 | Format rule (N6) |
| C1 | Held. Membership is asserted. No view is owner-rights, and the core gets SELECT on nothing tally_app lacks (probed) |
| C2 | Pattern held; R1 records what `evaluated_by` means |
| C3 | **Dispositions missing (B2)** |
| C4 | Held (N2) |
| L1–L4 | Held, with N7 |

**Template choices for -13 and -15:**
- **Spans with NULL = every one:** right, and they fix -15's `coalesce(class,'')` exclusion bug class.
- **Area key NOT NULL and `=`:** fine for -13 (class, cause) and -15 (class, basis), with the S9 caveat.
- **Law always cited, tariff optional:** right (S5 aside).
- **Tariff checked against the law rows that share its key columns:** right for statutory keys; S9 covers the utility's own keys.
- **Adoption:** right (S6).
- **`rule_row_seed`'s "same row":** sound. Applicability is compared as spans, so owner-type order does not matter. Any other difference raises, or meets the exclusion (23P01).

## 2. Integrity probes that held
- Escaped, nested and in-array duplicate keys are refused.
- Writer-set `terms` and facets are compared, then overwritten.
- Spans are always the trigger's.
- A close carrying any other change is refused.
- A law close needs a role that sees every tenant.
- Tariff RLS, the policy, FORCE RLS and the tenant check on audit findings all hold.
- Audit findings stamp their kind and version from the row.
- The fingerprint cannot be chosen by the writer.
- The freeze and insert handshake works in both orders (RC3, RC4).
- `tally_core` has no TEMP, no CREATE, no materialized views and no default ACL.
- Dynamic SQL is quoted throughout.
