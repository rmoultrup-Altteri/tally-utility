**Verdict: ready.** No blocking defect found in the r7-to-r8 diff. The r7 blocker is fixed. There are nonblocking coverage gaps and a stale residual description.

Both frozen hashes match:

| Artifact | Verified MD5 |
|---|---|
| Patch, 3,452 lines | `3da8dfa0a23f68bb25c4a4c9b3dbd389` |
| Battery | `49779ba424c6638df174bf41e4641a81` |

This is a static review. I did not execute PostgreSQL, CI, mutations, or the probes; the reported 272 PASS lines and 192/192 mutation results remain operator-supplied evidence. All probe outcomes below are **predicted from the SQL, not executed**.

References below use **P** for [patch-17-frozen-r8.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/patch-17-frozen-r8.sql), **B** for [battery-17-frozen-r8.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/battery-17-frozen-r8.sql), and **M** for [mutations-17.py](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/mutations-17.py).

**Blocking: none.**

**Assessment of each r8 change**

1. **Conditional note sample — correct.** P:1612 resolves the delegated branch before inspecting its properties, and P:1614 restricts the query to the requested kind **and version**. A delegated branch reached through `$ref` works. A note-enabled version does not contaminate a no-note version. The no-note document remains unconditional; the note-bearing document is added only when admitted. Registration visits every existing version at P:1836, and row preparation checks the selected version at P:2047. This fixes the false refusal without dropping the existing note-bearing refusal. Probe p02 exercises differing versions with referenced branches.

2. **Registration loop and scope extraction — correct.** P:1804 checks column presence before constructing or iterating legacy rows. A missing area key therefore retains the earlier column diagnostic rather than causing an undefined-column error in the loop. Empty adopting tables execute zero iterations. Nonempty tables have no row limit; only diagnostic detail is capped at three rows (P:1824), with a total thereafter.

   The key, scope, and span checks run in order. A row failing twice contributes one rejected row and its first error; it cannot slip through. Errors raised by `rule_applicability_span`, including unknown codes and repeated owners, are caught at P:1819 and included in the eventual `42P16` refusal at P:1864. A valid key does not bypass scope validation.

   The extracted function at P:1947 preserves the prior state and law/tariff system-kind predicates and SQLSTATEs. Its call at P:2092 remains before applicability derivation and the area hook. Probes p01 and p04 cover these paths.

3. **Audit finding guard — correct.** P:3068 rejects an unfilled document before copying kind/version. It follows the existing row-existence and tariff-tenant checks, so their refusals remain intact. It applies equally to law and tariff rows, and valid object documents pass. Findings without a rule still take the unchanged `ELSE` path. Probe p04 covers an unfilled law, a valid tariff, a finding without a rule, and an owner-injected empty tariff document. That last case is fault injection, **not** an ordinary reachable tariff write.

4. **Generated columns — correct within the stated registration scope.** P:1763 rejects any nonempty `attgenerated` value for template, key, or facet columns. It does not accidentally reject unrelated generated columns. Identity columns are separate: they supply a value before the trigger rather than recomputing a stored expression afterward. Leaving them outside this predicate does not reproduce the reported overwrite hole. Probe p03 checks template/key rejection, an unrelated generated column, and an identity-backed version supplied explicitly. Its virtual-column case runs conditionally on a supporting server; PostgreSQL 16 takes the applicability notice.

5. **Previously unisolated clauses — now isolated.** T1zc tests the ordering exemption before registration creates its triggers, so the identity assertion cannot mask the missing function comparison. T1zd isolates the function namespace requirement. A1h and A1i independently disturb the system and jurisdiction spans. See B:595, B:602, B:977, B:985.

6. **Documentation — mostly accurate; R26 needs correction.** R14 and R22 describe the revised checks. The final sentence of R26 does not describe the new exception handling; see N1 below.

**Should-fix S1 — the added mutation set does not cover every new clause independently.**

The named M184–M195 mutations have appropriate distinguishing cases:

| Behavior | Case | Mutation |
|---|---|---|
| Do not invent a forbidden note | T1za | M184 |
| Retain the no-note sample | T1zb | M185 |
| Reject generated facet | T1ze | M186 |
| Refuse unfilled audit reference | First K4i | M187 |
| Require public trigger function | T1zd | M188 |
| Check ordering-exemption function | T1zc | M189 |
| Check legacy key | A1f; A1l adds punctuation | M190 |
| Check legacy state/service-kind | A1j, A1k | M191–M192 |
| Compare each stored span | A1g–A1i | M193–M195 |

I do not predict a survivor among those named mutations. However, these additional mutations are **predicted to survive the frozen battery**:

- Delete `AND sc.terms_version = p_version` at **P:1614**. Existing multi-version fixtures retain the same delegated-note policy. **p02** distinguishes versions that differ.
- Add `LIMIT 1` to the legacy-row query at **P:1808**. The new refusal fixtures are singleton tables; the successful multi-row adoption does not establish that later rows were checked. **p01** puts an invalid row after 99 valid rows.
- Change the generated-column membership expression at **P:1764** to `ANY (p_facet_columns)`. T1ze still rejects its generated facet, while generated template/key columns escape. **p03** distinguishes both omissions.

These are coverage gaps, not defects in the current implementation. Mutation definitions: M:510–535.

**Notes**

- **N1 — stale R26.** P:3447 says non-text keys and repeated owner types refuse with the underlying error instead of the combined message. The new handler at P:1819 catches both row-check failures; the accumulated shape/row errors become `42P16` at P:1864. Probe **p01** includes both examples. Update the residual wording.
- **N2 — duplicate test identifier.** B:1211 and B:1215 both use `K4i`. M187 currently reaches the intended first case, but unique identifiers would make future mutation attribution unambiguous.

**Regression assessment**

I found no r8 change that opens a rounds 1–7 hole. Specifically, the delegated-document checks retain both required samples where applicable; tariff scope validation retains its prior predicates; legacy registration still refuses blank keys and every span mismatch; and the audit addition preserves the existing tenant check. The corresponding probes are p02, p04, p01, and p04 respectively.

Only these four files were created; no other file was modified:

- [p01-adoption-loop.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r8-probes/p01-adoption-loop.sql)
- [p02-note-versions-ref.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r8-probes/p02-note-versions-ref.sql)
- [p03-generated-and-identity.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r8-probes/p03-generated-and-identity.sql)
- [p04-tariff-scope-and-audit.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r8-probes/p04-tariff-scope-and-audit.sql)

Each is self-contained, requires a database name starting with `codex`, reports case results through `NOTICE`, and uses one transaction ending in `ROLLBACK`. All are predicted to report PASS on frozen r8, subject to execution.

## Operator outputs (probes run on a clone of frozen r8, database codex817)

```
== p01-adoption-loop.sql
NOTICE:  PASS empty adopting table registers: success 
NOTICE:  PASS 100 valid legacy rows register: success 
NOTICE:  PASS invalid row after 99 valid rows is checked: 42P16 codex_probe_rules does not fit the rule-table template: legacy row c0de0000-0000-4000-8000-000000000100 cannot be adopted: codex_probe_rules: QQ is not a known state (no state place of that code) 
NOTICE:  PASS missing area key reports column error, not undefined column in loop: 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules has no column customer_class (text) (v5.4.2-17)
NOTICE:  PASS non-text key uses combined template error (R26 is stale): 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules.customer_class is integer, not text; legacy row c0de0000-0000-4000-8000-000000000001 cannot be adopted: the 
NOTICE:  PASS bad owner code is caught and aggregated: 42P16 codex_probe_rules does not fit the rule-table template: legacy row c0de0000-0000-4000-8000-000000000001 cannot be adopted: owner_type codex_unknown: not a known code with an ordinal (v5.4.2-17) (v5.4
NOTICE:  PASS repeated owners now use combined error (R26 is stale): 42P16 codex_probe_rules does not fit the rule-table template: legacy row c0de0000-0000-4000-8000-000000000001 cannot be adopted: a set of owner_type codes is NULL (every one) or non-empty, wi
NOTICE:  PASS valid key, invalid scope: 42P16 codex_probe_rules does not fit the rule-table template: legacy row c0de0000-0000-4000-8000-000000000001 cannot be adopted: codex_probe_rules: system kind master_meter is not a kind of water system (v5.4.2-17) (v5.4
NOTICE:  PASS one row with two defects reports its first refusal: 42P16 codex_probe_rules does not fit the rule-table template: legacy row c0de0000-0000-4000-8000-000000000001 cannot be adopted: the key of codex_probe_rules names exactly {customer_class}, each
NOTICE:  PASS four bad rows counted, including a row with two defects: 42P16 codex_probe_rules does not fit the rule-table template: legacy row c0de0000-0000-4000-8000-000000000001 cannot be adopted: the key of codex_probe_rules names exactly {customer_class},
== p02-note-versions-ref.sql
NOTICE:  PASS v1 ref branch forbids note: no false refusal from v2
NOTICE:  PASS v2 ref branch admits note: incompatible facet refused
NOTICE:  PASS registration checks every version, including v2: 42P16 codex_probe_rules does not fit the rule-table template: codex_versions v2: its facets cannot be derived from the standard delegated document {"note": "x", "governs": "delegated_to_utility", "
== p03-generated-and-identity.sql
NOTICE:  PASS generated template column refused: 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules.source_note is a generated column: it would store what the document does not say (v5.4.2-17)
NOTICE:  PASS generated area key refused: 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules.customer_class is a generated column: it would store what the document does not say (v5.4.2-17)
NOTICE:  PASS unrelated generated column allowed: success 
NOTICE:  PASS identity template column allowed; explicit version retained: success 
NOTICE:  PASS virtual-column applicability: not supported on this server; no virtual DDL executed
== p04-tariff-scope-and-audit.sql
NOTICE:  PASS tariff prepare still refuses unknown state: 23503 codex_tariffs: QQ is not a known state (no state place of that code) (v5.4.2-17)
NOTICE:  PASS tariff prepare still refuses water master meter: 23514 codex_tariffs: system kind master_meter is not a kind of water system (v5.4.2-17)
NOTICE:  PASS tariff prepare still refuses missing system kind: 23514 codex_tariffs: system kind  is not a kind of gas system (v5.4.2-17)
NOTICE:  PASS valid tariff preserved
NOTICE:  DEFECT core cannot cite unfilled legacy law: expected 23514 / not yet adopted, observed 42501 / permission denied for function finding
NOTICE:  DEFECT core can cite a valid tariff: expected <NULL> / , observed 42501 / permission denied for function finding
NOTICE:  DEFECT finding without rule still allowed: expected <NULL> / , observed 42501 / permission denied for function finding
NOTICE:  DEFECT same empty-document guard covers tariff rows under fault injection: expected 23514 / not yet adopted, observed 42501 / permission denied for function finding
```

p01-p03 print no defect (p01 and p03 confirm N1: R26 is stale). The four p04 DEFECT lines are a probe-setup artefact: each is 42501 "permission denied for function finding…", raised before the guard runs, because the probe calls a function tally_core is not granted. The same refusal is covered in the battery by K4i through the grants (tally_core inserts), which passes and is caught by M187.
