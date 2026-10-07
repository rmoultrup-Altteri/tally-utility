# v5.4.2-17 review round 2: findings and dispositions

**Frozen:** patch `896915806252050afc5627ea7ff5def0` (2,939 lines), battery `5da3cb4c31ec909eff92dd2b9bead7d5`.

**Verdicts:**
- **Opus:** ready. Three should-fixes.
- **Fable:** ready. Three should-fixes.
- **Codex:** not yet. Three blocking items; static review.

**Reviews:** `review-r2-opus.md`, `review-r2-fable.md`, `review-r2-codex.md`.

**Round-1 fixes re-verified by the reviewers:**
- the tariff race: Opus and Fable re-ran it in two sessions, and it is refused;
- the inputs isolation check (READ COMMITTED);
- the citation helper;
- seed keys and defaults;
- registration of a non-empty table;
- the state check;
- the control characters;
- dispositions and units.

One round-1 disposition was **wrong**: "`text[]` into `text`" was recorded as fixed, but registration checked only a list of allowed column types. It is corrected below.

Triage is by the standing rules, as in round 1. Nothing needed Ryan.

## Findings

| # | Finding | Who | Disposition | Rule |
|---|---|---|---|---|
| 1 | A facet column of another *allowed* type than its facet's: `text[]` in `text` stores JSON text; `boolean` and `number` in `text` | all three | **Fixed.** `rule_facet_column_errors()` pairs each declared facet's type with its column's: text with text; text[] with text[]; integer with integer or bigint; number with numeric; boolean and present with boolean. Checked at registration for every registered version of the kind, and at every row write (which catches a later version). T1h; M125 | Integrity bug |
| 2 | The database counts a union branch as a document level; the reference check does not (a 31-level union document: reference valid, database invalid) | Fable, Codex | **Fixed.** Selecting a branch keeps the depth; a branch is an object schema, so recursion still descends. V24 (Codex's schema: 31 and 62 levels valid, 63 refused at depth 65); M126 | Integrity bug; checks narrower than their claim |
| 3 | Adoption-mode registration admits rows whose documents are already filled, never validated nor compared | Codex | **Fixed.** An adopting table's documents must all be empty at registration. A1e; M127 | Integrity bug |
| 4 | The adoption equivalence check lived in the permanent insert check, so after adoption every valid new row was refused (`cap 75 is not the legacy cap <NULL>`) | Fable | **Fixed.** Registration takes `p_adoption_check` (it replaces the boolean): run only when an empty document is filled, after the insert check. `rule_tables.adoption_check` holds it. A1c (signature), A3h, A4 (a new row after adoption); M128, M129 | Integrity bug; the -13 migration would hit it |
| 5 | A re-seed with a different value in another named column (an area column, a facet) returned the existing id silently | Opus | **Fixed.** Every column the seed names is compared, except applicability (matched as sets) and the document (compared parsed). T4k; M130 | Integrity bug |
| 6 | Strategy versions were fixed to one value, so a strategy's v2 forced a new terms version, against v2 §11 ("independently of terms_version"). A `$ref` for `version` was refused | Opus, Fable | **Fixed.** `version` is an integer with 1 ≤ minimum ≤ maximum, resolved through `$ref`. R4n (empty range), R4o (unbounded); M112, M132 | v2 §11 |
| 7 | A freeze compared jsonb, so `0` → `0.0` passed and the hash no longer matched the stored text | Codex | **Fixed.** Compared as text. R8c; M131 | Integrity bug |
| 8 | Python accepts NUL and lone surrogates, which PostgreSQL cannot store | Codex | **Fixed.** lawc's fixed rule refuses them | Checks narrower than their claim |
| 9 | The core-role checks ran only in this patch's tail; CREATE was checked on `public` only | Codex | **Fixed.** `assert_core_role_invariants()` (owner-only) checks attributes, membership, matviews (column grants), default ACLs, TEMP, and CREATE on the database and on any schema. Run in the tail and last in `tests/ci.sh`. K8, K9; M133 | Guards must act |
| 10 | Guards lacking a case only they refuse: V10, V13, depth, inputs freeze races, ordinal guard | Codex, Opus | **Added.** V10b and V13b (isolated); V24; races **RC6/RC7** (an inputs freeze against a core record, both orders; M134); O1, O2 (M135, M136) | — |
| 11 | APPLY mutations counted any failed apply | Codex | **Fixed.** An APPLY mutation names the phrase the intended guard raises | Checks narrower than their claim |
| 12 | Under delegated law with no tariff, the fixture records no charge | Fable | **Tested.** C2g: there is no policy to charge under, so the core refuses (U4) | — |
| 13 | Adoption discarded a supplied `terms` instead of comparing it | Codex | **Fixed.** Adoption passes the row as written, so a contradictory `terms` is refused as on an insert | — |
| 14 | The tariff check gives up after 5 reads; a two-row close can deadlock with it; the state check ignores the place's dates | Opus (notes) | **Residual R18.** Either outcome is a retry, never a stale acceptance; states do not come and go inside the law's dates | Stated |
| 15 | Mutations are not in CI; W3 does not re-serialise stored rows to YAML | Codex (notes) | **Note.** The mutation suite runs on every revision before review (a 30-minute run; it clones `tally`). W3 compares the stored documents with the files, and the files are the source | — |
