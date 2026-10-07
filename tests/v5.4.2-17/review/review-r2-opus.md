# v5.4.2-17 draft r2 — review (Opus)

**Artefacts checked:** patch md5 `896915806252050afc5627ea7ff5def0` (2939 lines) and battery md5 `5da3cb4c31ec909eff92dd2b9bead7d5`. Both match the brief.

**Probe setup:** clones `opus17r2` (ZZ fixture and probe rows committed) and `opus17r2b` (clean), each strict-applied from `tally` with TEMP revoked. On `opus17r2b` the full suite passes:
- battery: 202 PASS;
- isolation: 0 failures;
- races: RC1–RC5;
- law files: W1–W5 (W4: 899 documents, 0 disagreements).

I did not run the mutation suite: it clones into a fixed database name, `m17`.

**Verdict: ready.** Nothing is blocking. All my round-1 blocking items hold under re-run, and so do most should-fixes. Three new or remaining should-fixes are below. Each is small, and none lets a tenant reach another's data or lets the application write what it may not.

---

## 0. Round-1 findings, re-run against r2

| r1 | Re-run result | Holds? |
|---|---|---|
| **B1** tariff check used stale law | My two-session race again: law A was closed and a stricter law B (cap 10) inserted in flight; the tariff was seen waiting on a Lock. It is now **refused**: "looser than the law: fee 40 above the cap 10 of law B" (`rule_tariff_check` 1844–1885). The loop is sound: the last read happens after every lock it needs is held. A close of a row it saw has either committed (and is seen) or waits. A new row overlapping a locked open row cannot be inserted without that row's close, and the close waits. A row in a gap only adds coverage the read already refused. RC5 covers it; M106 is listed | **Yes** |
| **B2** P1 class scope missing | Recorded as residual R10 (2893–2898), on the stopping rule: §183.003 publishes one rate. Acceptable. The -15 rewrite must drop or justify its `customer_class` column on `deposit_interest_rate_law` | Yes (residual) |
| **B2** units not a vocabulary | `rule_units` with a foreign key (2266–2304) | Yes |
| **B2** C3 dispositions missing | `rule_audit_finding_dispositions` (2725–2782): (tenant, finding) foreign key, FORCE RLS, `decided_by` stamped and required, append-only. Another tenant's finding cannot be referenced: the composite foreign key plus the policy's WITH CHECK refuse it | Yes |
| **S1** Python `$` before a newline | Fixed rule 786–796 refuses U+0001–U+001F and U+007F in strings **and keys**, at any depth; I probed a key nested in arrays. lawc refuses my newline example before the cross-check runs. U+0085 and U+2028 match `$` in neither engine | Yes |
| **S2** W4 narrow and hardcoded | W4 now discovers every schema and needs examples. Its mutations cover newline, tab, non-ASCII, 201 characters, 30 digits and a discriminator switch: 899 documents. The README is corrected | Yes |
| **S3** facet columns | A template column as a facet is refused: `terms is a template or key column, never a facet` (1503–1506). **Type pairing is not fixed** (new S1 below) | **Partly** |
| **S4** facets fixed forever | Residual R9 | Yes (residual) |
| **S5** citation not tied to the utility | `rule_law_row_cite` (2082–2101). The fixture names the profile and the key, and cites through it; the city citing the IOU row is refused ("no law … binds a municipal gas utility"). The tariff is cited only if it is the utility's own, the component is checked against the facet (F7), and `UPDATE` is revoked | Yes |
| **S6** adoption equality | An adopting table must name an insert check (1528–1530), which receives the whole row with its old columns (1761–1762, 1973). A3h shows a mismatching document refused | Yes |
| **S7** component ids in inputs | `rule_terms_errors(…, false)` from `stamp_core_inputs` (2501) | Yes |
| **S8** inputs under REPEATABLE READ | `assert_rule_read_committed` (2487); X6 | Yes |
| **S9** city classes against delegated rows | Residual R16 | Yes (residual) |
| **S10** test gaps | Mostly added: T1f/g, X6, RC5, K7, P3i, F2g and others. Ordinal-guard negatives are still absent (grep `ordinal` in the battery: only the span helpers appear) | Mostly |
| **N1** TEMP through PUBLIC | Asserted at apply (2829–2834) | Yes |
| **N4** NUL escape | Now refused as "JSON that PostgreSQL can store: unsupported Unicode escape sequence" | Yes |

---

## Should-fix

### S1. A facet column's type is not paired with its facet type
Registration only whitelists the column type: text, text[], integer, bigint, numeric or boolean (1511). It never checks that the column type fits the facet's own type. The r1 disposition (row 4) lists "`text[]` into `text`" as fixed; it is not.

**Reproduction (opus17r2, rolled back):** a tariff kind with three facets, on columns of other whitelisted types:

| Facet type | Column type | Result |
|---|---|---|
| `text[]` | `text` | Accepted; stored **`["a", "b"]`**, the JSON text |
| `boolean` | `text` | Accepted; stored `true` as text |
| `number` | `integer` | Accepted for `7`; `7.5` raised `invalid input syntax for type integer`, a loud error and not a refusal by any guard |

The facet types are known only per (kind, version), so the check belongs in `rule_row_prepare`: compare each declared facet's type with its column's `format_type`. The pairs are:

| Facet type | Column type |
|---|---|
| text | text |
| text[] | text[] |
| integer | integer or bigint |
| number | numeric |
| boolean, present | boolean |

Add a battery negative (a `text[]` facet over a `text` column).

### S2. `rule_row_seed` silently accepts a re-seed whose other named columns differ
r2 lets a seed name any column of the table (2172–2180, 2199). The re-seed comparison still covers only terms, effective_to, source_note, kind and version (2204–2212).

**Reproduction (rolled back):**
1. Add an area column `memo`.
2. Seed a row with memo "the cap applies per meter".
3. Re-seed with memo "… per premise": it returns the same id, no error.
4. Re-seed naming `fee_cap: 999, has_fee: true`, which are facets the document does not give: it returns the same id, no error. The same values on a first insert are refused (T6d).

The function's own claim is "never … a silent skip" (header 141–142; 2142–2147). lawc emits only envelope and key columns, so tool-made seeds are unaffected. A hand-written -13 seed, while its legacy typed columns still exist, is affected.

**Fix:** on an existing row, compare every column the seed names, apart from the spans, whose sets are already compared. Compare facets against the stored derived values.

### S3. "A strategy fixes its version" couples strategy versions to terms versions
The new rule (464–476) requires `version` with minimum = maximum on every branch of a `strategy` union. The discriminator's values must also be distinct (477–481). So a schema version can admit exactly one version of each strategy.

Writing `greater_of` v2 then needs a new `terms_version`, and v1 is no longer writable for a historical row under the new schema version. Convention v2 says strategy versions follow the frozen-version rule "independently of `terms_version`" (convention line 198). It also says a new `terms_version` is "only for a breaking shape change" (line 197).

**Fix:** require both bounds with minimum ≤ maximum, so the schema states the range of versions it admits and the core refuses any version it has no reader for. Alternatively, state the coupling as a residual against v2 §11.

The rule also binds only a discriminator literally named `strategy`. A union discriminated on another name escapes it; add a line to the README.

---

## Notes
- **N1.** The new state check (1729–1733) is any `places` row of kind `state` with that code. It ignores the place's dates. That is harmless while states never close; say so in the comment.
- **N2.** `rule_tariff_check` gives up after 5 reads with 55P03, a retryable code. A law table busy with closes could starve tariff writes. That is acceptable; R5 sits beside it.
- **N3.** Shared locks are taken in id order within each read. A migration closing two law rows in one transaction, against a tariff holding one of them, can deadlock. PostgreSQL detects that and aborts one side. Worth a sentence near T4 so the migration retries.
- **N4.** Dispositions do not check that `decided_by` belongs to the finding's tenant beyond the policy: a platform-admin session can dispose of any tenant's finding. That is consistent with the rest of the schema.
- **N5.** Ordinal-guard negatives (an edit, a delete, an unknown code) are still untested, and no mutation targets `enforce_rule_applicability_ordinal`.

---

## 1. The spec (Step-2 items)

| Req | Status |
|---|---|
| V1–V4, V8 | Held |
| V5 | Held, with S3 |
| V6, V7 | Format rules (README) |
| V9 | Held |
| V10 | Held: W4 discovers schemas, its corpus is broadened, and the README states the limits honestly (R7) |
| F1–F4 | Held. F2 has a typing gap (S1) |
| F7 | Held; the fixture demonstrates it |
| T1–T5 | Held. T4 now covers the tariff check too (RC5) |
| T6 | Held: the hook is required |
| T7 | Residual R2 |
| U1–U4 | Held. U4's pattern is fixed |
| U5 | Area |
| P1 | Held, except class (residual R10) |
| P3 | Format rule, with a facet recipe in the README |
| C1–C4 | Held. C3 dispositions are built. C4 is per R15 |
| L1 | Note: amended |
| L2 | Held |
| L3 | Held; scenarios per residual R11 |
| L4 | Held |

**Template choices for -13 and -15:**
- **Spans, the NOT NULL `=` area key, "law always cited, tariff optional", and tariffs checked on shared keys:** right. R3 and R16 state the limits.
- **Adoption:** right, and R14 gives -13 its sequence. -13's typed columns pass the new facet-type whitelist: `integer`, `text[]` and `boolean` are all allowed.
- **`rule_row_seed`'s "same row":** sound, apart from S2.

## 2. Integrity probes that held
- Tariff race (above).
- A template column as a facet.
- Control characters in nested keys.
- NUL refused for its real cause.
- A city's citation of the IOU row.
- Dispositions across tenants.
- `tally_core`'s TEMP asserted at apply.
- All earlier probes (duplicate keys, writer-set facets and terms, close-only edits, law close by a role that sees every tenant, finding subject checks, fingerprint) behave as in r1.

Databases `opus17r2`, `opus17r2b`, `opus17r2_iso`, `opus17r2_race` and `opus17r2_law` are dropped.
