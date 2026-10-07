# v5.4.2-17 review round 1: findings and dispositions

**Frozen:** patch `bf006d2a6722035d928e34177fdf60a0` (2,558 lines), battery `43c4132fb4ed8d2cdebfd77c30429c15`.
**Verdicts:** Opus "not yet" (2 blocking); Fable "not yet" (1 blocking); Codex "not yet" (8 blocking; static review).
**Reviews:** `review-r1-opus.md`, `review-r1-fable.md`, `review-r1-codex.md`.

Findings are triaged by the standing rules (memory `source-inventory-first-triage-by-rule`):
- **Fix** — an integrity bug, or a requirement with a source;
- **Residual** — a shape with no source, or a design deferred with its reason;
- **Note** — documentation only.

Each row names the rule that decided it. None needed Ryan: no two rules conflicted.

## Blocking (by any reviewer)

| # | Finding | Who | Disposition | Rule |
|---|---|---|---|---|
| 1 | `rule_tariff_check` reads the law rows, then locks them, then never re-reads. A tariff written against a close (and successor) in flight is compared with stale law. Reproduced by Opus and Fable | all three | **Fixed.** Lock, then read: every row's lock is taken shared and the rows re-read until a read finds no row it had not locked first; coverage and the comparison use only that read; give up after 5 reads (55P03). Race **RC5** (close plus stricter successor in flight; the tariff waits, re-reads and is refused against the successor); mutation M106 | Integrity bug; count-guards-need-lock-handshake |
| 2 | Adoption never compares the document with the old typed columns, so a schema-valid but different document could be adopted | Codex (Opus S6, Fable S11) | **Fixed.** An adopting table must name an insert check (registration refuses otherwise), which receives the whole row — old columns included — during adoption. Battery A1c, A3h (delegation for a 500 cap refused), A3i; mutation M108 | Integrity bug; the inventory §4 A default |
| 3 | `stamp_core_inputs` does not require READ COMMITTED: a frozen inputs version passes through an old snapshot. Reproduced by Fable | all three | **Fixed.** `assert_rule_read_committed`; isolation **X6**; mutation M107 | Integrity bug |
| 4 | Registration lets a facet column be a template column (`terms` was overwritten, reproduced) or of a type that coerces (`numeric(4,0)` rounds; `text[]` into `text`) | Codex, Opus | **Fixed.** Facet columns are never template or key columns, and are text, text[], integer, bigint, numeric (no precision) or boolean. T1f, T1g; M109, M110 | Integrity bug |
| 5 | Python's `$` matches before a trailing newline; the database's does not (reproduced: 6 disagreements). Python's `normalize()` rounds beyond 28 digits. Registered schemas can admit documents deeper than the interpreter's 64 | all three | **Fixed.** A fixed rule refuses control characters (U+0001–U+001F, U+007F) in every string and key, in both validators, so a newline never reaches a pattern. lawc serialises exactly (`format(d, "f")`, no context rounding) and applies the same 64-level depth rule. The W4 corpus now includes newline, tab, non-ASCII, 201-character, 30-digit and discriminator-switch mutations: **899 documents, 0 disagreements**. V23; M113 | Integrity bug; checks narrower than their claim |
| 6 | P1: published values have no customer-class scope (-15's table had one), and the unit is free text | all three | **Partly fixed.** Built `rule_units`, a vocabulary with a foreign key; P3i; M121. **Residual R10** for class scope: no source publishes a class-specific value (§183.003 publishes one rate a year); the -15 column was a design choice, not a source | Stopping rule |
| 7 | The citing-record pattern: a city cited the investor-owned law row (reproduced by Opus and Fable); a core record could name another tenant's charge; no component citation (F7); a citing record could be UPDATEd past the guard | Codex (Opus S5, Fable S3) | **Fixed.** `rule_law_row_cite()`: the cited row must be THE law row in force for the citing utility's profile, key and date, then is locked. The ZZ fixture now shows the whole pattern: a charge names its profile and area key; cites the law; cites the tariff only if it is the utility's in force; names the governing component, checked against the facet; references another tenant's row only through a (tenant, id) foreign key; and is never updated. C2c, C2d, C2e, C2f; M116 | Integrity bug |
| 8a | C3: audit-finding dispositions were neither built nor a residual | all three | **Fixed.** `rule_audit_finding_dispositions` (append-only, tenant RLS, written by tally_app, user and time stamped) and `rule_audit_disposition_kinds`. K7a–e; M118, M119 | The inventory classed it Step 2 |
| 8b | The expected-decision CHECK passes NULL with a date due | Codex | **Fixed.** Both or neither, in the CHECK and the trigger. K4i; M117 | Integrity bug |
| 8c | Golden scenarios are shape-checked, not schema-checked | Codex (Opus N7) | **Residual R11.** The scenarios' types are the core's decision points, which do not exist yet; v2 §5 says the schemas come from the core's types | Design-permanent: no stop-gap schemas |

## Should-fix and notes

| Finding | Who | Disposition |
|---|---|---|
| V5: a strategy's `version` is not enforced at registration | Fable S8 | **Fixed.** A branch selected by `strategy` must require `version`, an integer with minimum = maximum. R4n; M112 |
| A non-adopting registration accepts a table that already holds rows | Fable S5 | **Fixed.** Refused unless the table adopts them. A1d; M111 |
| `rule_row_seed` drops unknown keys; it nulls columns that have defaults | Fable S4, Opus N9 | **Fixed.** Unknown columns are refused (42703); the seed inserts only the columns it names. T4i, T4j; M115 |
| "A state not known" was claimed, and only the code's shape was checked | Codex S5, Fable S10 | **Fixed.** A state must be a state place (-16). T5e; M114 |
| A component-id rule applied to inputs documents | Opus S7 | **Fixed.** `rule_terms_errors(…, p_component_ids)`; inputs are exempt; `lawc crosscheck --inputs` |
| tally_core: column grants on matviews, a pre-existing role's attributes, effective TEMP | Codex S1, Opus N1 | **Fixed.** `has_any_column_privilege`; NOLOGIN and no SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION; TEMP and CREATE asserted at apply (M124) |
| `rule_terms_parse('{"a":"\u0000"}')` refuses as "repeats a key" | Opus N4 | **Fixed.** The cast comes first and names the cause. V21e; M123 |
| A close may rewrite a number's scale (`50` → `50.000`) | Fable N2 | **Fixed.** The whole-row comparison is on text. T8c; M122 |
| Facet paths may use `.double()` | Opus N11 | **Fixed.** Refused. F2g; M120 |
| The YAML loader admits the non-specific tag `!` | Codex S3 | **Fixed.** Any explicit tag is refused. W5 |
| JSON examples may write exponents, which the database rewrites | Opus N3, Fable N1 | **Fixed.** lawc refuses exponents in JSON input |
| W4 is hardcoded to the ZZ schemas; nothing shows it catches drift; the README overclaims | Opus S2, Fable S9, Codex | **Fixed.** W4 discovers every `law/**/<kind>.vN.schema.json`, fails a schema without examples, and requires the file to equal the registered schema. Mutation M105 (minLength) is caught only by W4. The README states what the cross-check proves and what it does not |
| A table's facets are fixed forever | Opus S4 | **Residual R9** (a sanctioned extension when an area first needs one) |
| A city's own classes cannot meet a delegated row; coverage across unshared keys | Opus S9, Codex | **Residual R16** (the area decides beyond shared keys; the column naming rule stated) |
| A tariff table may name no law table | Codex S2 | **Residual R12** (stated as an exemption for rules no law speaks to) |
| A finding's subject is checked when written, with no lasting reference | Codex S4 | **Residual R13** |
| The -13 adoption needs a sequence (spans first, drop its own history trigger, the insert check) | Fable S11, Codex | **Residual R14** (the migration's, reviewed with it) |
| The fingerprint is over PostgreSQL's jsonb text | Opus N2 | **Residual R15** (documented; a test vector comes with the core's first inputs kind) |
| A close under a tariff is allowed | Fable B1 note | **Residual R17** |
| L1's file partition (per owner type) differs from the README (per state and service) | Codex S6, Opus N7, Fable N6 | **Note.** Owner types are a set on a row (spans), so one file per (table, state, service) holds rows for several owner types; the inventory's L1 is amended to match |
| P3 references to published values are unchecked | Opus N6 | **Note.** An area declares a `text[]` facet over its `{"source": "published", "name": …}` paths with `rule_parameters` as its vocabulary; the README says so |
| A row inserted with `effective_to` cannot be closed earlier | Fable N7 | **Note.** Intended: its end is the law's, recorded at insert; a different end is a correction (R2) |
| CI installs without `--require-hashes`; the Actions run on Node 20 | Opus N10 | **Note.** Pinned versions now; hash pinning and action-version upgrades with the next CI change |
| Test gaps listed by the reviewers | all three | **Added:** T1f/g, T4i/j, T5e, T8c, A1c/d, A3h/i, C2c–f, V21e, V23, F2g, P3i, K4i, K7a–e, R4n, L1's municipal-bound-by-law case, X6, RC5. Mutations M105–M124 |
