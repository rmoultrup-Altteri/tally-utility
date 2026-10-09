**Verdict: not yet — one blocking regression in the new delegated-facet dry-run.** The other r7 changes implement their stated fixes. I found no new acceptance bypass.

Both frozen hashes match:

- Patch: `b2684ffd74aaa19998cd58b470ba6883`; 3,377 lines.
- Battery: `e07b5516aa22f0103ab15086c93d5937`.

This is a static review of the r6-to-r7 changes and their affected paths. I did **not** execute PostgreSQL, CI, mutations, or the reported 262 PASS checks. Every reproduction below is **predicted from the SQL, not executed**.

References below use **P** for `tests/v5.4.2-17/review/patch-17-frozen-r7.sql` and **B** for the corresponding frozen battery.

**Blocking — B1: the new dry-run can reject facets that work for every schema-valid document.**

The registry expressly permits the delegated branch to omit the `note` property: P:1046 accepts `NOT ... ? 'note'`. With `additionalProperties:false`, that schema **forbids** a delegated document containing a note.

Nevertheless, P:1598–1604 now unconditionally derives facets from both sample documents, including `"note":"x"`.

[p07-forbidden-note-false-refusal.sql](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r7-probes/p07-forbidden-note-false-refusal.sql:44) constructs:

- A registered schema whose law branch requires numeric `cap` and whose delegated branch forbids `note`.
- A nullable numeric facet using `$.keyvalue() ? (@.key == "cap" || @.key == "note").value`.
- Every valid law document produces its numeric cap; every valid delegated document produces NULL.
- The added sample alone produces the string `"x"`, causing registration to raise `42P16`.

**Predicted result:** the final probe prints DEFECT; the same registration succeeds under r6’s dry-run. This is an introduced false refusal, not the existing limitation that sampling cannot prove every document storable.

**Fix:** run the note-bearing sample only when that kind/version’s delegated schema admits it. Keep T1z/M178 and add this positive registration case; T1z currently exercises only a schema that permits notes (B:565–574). This also restores agreement with the registry behavior established before r7.

**Should-fix — S1: audit rule references remain an unfilled-row reader.**

The three changed readers correctly reject NULL `terms`, but `enforce_rule_audit_finding()` still selects the referenced row directly and stamps NULL `terms_kind`/`terms_version` without refusing it (P:2990–3010). The nullable schema foreign key and rule-reference check permit that result (P:2927–2929).

[p04-unfilled-readers.sql:83](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r7-probes/p04-unfilled-readers.sql:83) predicts that `tally_core` can insert a `record_disagrees_with_rule` finding referencing an unfilled legacy law row.

Either reject unfilled rule references here or explicitly document their intended audit meaning. This is an incomplete extension of the r7 hardening, **not a newly opened bypass**, so I do not make it an additional blocker.

The other requested reader checks are sound:

- **Seed:** a valid incoming document differs from the legacy row’s NULL document and raises `23505`; it neither silently succeeds nor performs adoption (P:2529–2555).
- **Law citation wrapper:** calls the newly protected `rule_row_cite` first (P:2402).
- **Tariff lookup:** rejects a law table; tariff tables cannot register as adopting, and require non-NULL documents (P:1675, P:1692–1695, P:2431).
- **Close floor:** a legacy row may still close, but the lock and citing-record floor remain enforced (P:2218–2245). Closing does not treat its unknown terms as permission.
- **Audit subject:** ordinarily requires a tenant-bearing table; the separate `rule_table` reference is the path identified above.

**Should-fix — S2: several new predicates lack independent mutation coverage.**

The supplied M167–M183 mutations have corresponding cases and appear caught at their named checks. However, “every new clause” is stronger than those mutations establish.

These additional mutations are predicted to survive the existing battery:

1. Delete only the `system_span IS DISTINCT FROM ...` disjunct at P:1782.
2. Delete only the `jurisdiction_span IS DISTINCT FROM ...` disjunct at P:1783.

A1g changes only `owner_types` (B:921); M180 disables the entire resulting refusal. Neither isolates the other dimensions. [p03-adoption-spans.sql:53](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r7-probes/p03-adoption-spans.sql:53) supplies separate system-only and jurisdiction-only mismatches.

3. Delete only `AND m.fn = t.fn` from the sorting exemption at P:1537.

T1q still receives the required template-identity error from the separate registered-table clause at P:1549. Its expected phrase therefore does not establish the exemption predicate independently. [p06-schema-and-exemption.sql:65](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r7-probes/p06-schema-and-exemption.sql:65) checks the reserved-name impostor **before registration**, where that other clause is inactive.

These are proposed additional mutants, not claims that one of the supplied numbered mutations survived execution.

**Assessment of the six r7 changes**

| Change | Assessment |
|---|---|
| **1. Trigger identity, children and rules** | Correct for the stated invariant. Public namespace and zero-argument function matching, exact `tgtype`, WHEN/column-list checks and ENABLE ALWAYS are enforced at P:1517–1555. Wrong events, AFTER transition-table replacements and deferred constraint replacements cannot satisfy the template shape. |
| **2. Legacy rows and adoption preflight** | The three changed readers refuse unfilled terms at P:2148, P:2309 and P:2367. Blank-key validation matches the existing key convention. Typed span comparisons correctly ignore set ordering and equivalent range spelling. Audit references remain S1. |
| **3. Both delegated samples** | Catches the reported numeric-note facet, but introduces B1 by testing a potentially forbidden document. |
| **4. Required strategy** | Correct: P:565 requires strategy whenever that object declares it. An optional enclosing object remains optional; when present, its strategy is required. `$defs` traversal also reaches the check. |
| **5. Trigger-name cases** | T1w–T1y distinguish late byte-order names, uppercase early names and AFTER triggers. I found no case in the current expression where merely dropping `COLLATE "C"` changes behavior. |
| **6. Inline discriminator wording** | Correct wording-only change at P:504 and `law/README.md:82,98`. Citation/note references remain permitted; discriminator references remain refused. |

For trigger edges, PostgreSQL permits transition relations only on AFTER triggers, and constraint triggers must be AFTER ROW. Thus neither requires an additional catalog-field check to protect these BEFORE templates: the exact `tgtype` comparison already excludes them. [PostgreSQL 16 CREATE TRIGGER](https://www.postgresql.org/docs/16/sql-createtrigger.html)

For relation edges:

- `pg_inherits` detects partition children as well as ordinary inheritance children (P:1552).
- Registration separately rejects partitioned parents through `relkind='r'` (P:1653).
- Dropping an inheritance child removes the reason for refusal.
- A view **over** a registered table is allowed: its `_RETURN` rule belongs to the view, not the base table.
- INSERT, UPDATE, DELETE and SELECT rules are covered by the unfiltered `pg_rewrite.ev_class` check. SELECT rules belong to the view relation; TRUNCATE is not a rule event. [PostgreSQL 16 CREATE RULE](https://www.postgresql.org/docs/16/sql-createrule.html)
- Extra AFTER/statement triggers remain allowed. Supplying unused trigger arguments also remains harmless with the current template functions, which do not read `TG_ARGV`.

**Notes**

- **The dry-run remains sampling, even after B1 is fixed.** A nullable integer facet at `$.note ? (@ == "other")` passes both samples, then rejects the schema-valid `"note":"other"`. [p05-note-dependent-facet.sql:44](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r7-probes/p05-note-dependent-facet.sql:44) predicts this. R22 should explicitly include different note values; exhaustive JSONPath/schema compatibility was already outside the dry-run’s guarantee.
- **The explicit C collation is presently redundant.** The `tgname::text` value retains C collation through this CTE. M175’s explicit `en_US.utf8` substitution tests a real behavioral change; deleting the redundant annotation does not. p01 checks the expression’s collation.
- **R14 remains a migration preflight, not proof of universal adoptability.** Its new key/span checks are useful, but the area adoption hook and ordinary preparation checks still run during filling (P:2250–2277). The migration must complete that work.
- R23–R25 accurately describe the facet-nullability, registered-table assertion and inherited-read boundaries. None supplies a runtime DDL fence beyond the existing migration/CI assertion model.

**Probe delivery**

Only seven new files were written, all under [codex-r7-probes](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-17/review/codex-r7-probes):

| Probe | Coverage |
|---|---|
| `p01-trigger-shapes.sql` | Wrong events, transition tables, deferred constraints, allowed extra triggers, collation |
| `p02-relations-and-rules.sql` | Inheritance create/drop, partitions, views, rewrite events |
| `p03-adoption-spans.sql` | Independent span mismatches, blank key, reordered sets and canonical ranges |
| `p04-unfilled-readers.sql` | Lookup/citation wrappers, seed, tariff-role check, close floor, audit reference |
| `p05-note-dependent-facet.sql` | Different valid note value escaping the samples |
| `p06-schema-and-exemption.sql` | Strategy requirements, inline/reference boundaries, sorting exemption |
| `p07-forbidden-note-false-refusal.sql` | **B1: new rejection of a schema-compatible table** |

Each is self-contained, guards the `codex%` database name, runs in one transaction ending in ROLLBACK, and reports through PASS/DEFECT notices. Guards, transaction structure and dollar delimiters were checked statically; database execution remains pending.

## Operator outputs (probes run on a clone of frozen r7, database codex717)

```
== p01-trigger-shapes.sql
NOTICE:  PASS insert function on UPDATE is refused: 42P16 codex_probe_rules: the trigger rule_row_insert is not the template's: it must run public.enforce_rule_row_insert() as BEFORE INSERT FOR EACH ROW, with no WHEN clause and no
NOTICE:  PASS no-truncate function on AFTER TRUNCATE is refused: 42P16 codex_probe_rules: the trigger rule_row_no_truncate is not the template's: it must run public.enforce_rule_registry_no_truncate() as BEFORE TRUNCATE FOR EACH S
NOTICE:  PASS AFTER transition-table replacement is refused: 42P16 codex_probe_rules: the trigger rule_row_insert is not the template's: it must run public.enforce_rule_row_insert() as BEFORE INSERT FOR EACH ROW, with no WHEN clau
NOTICE:  PASS deferred constraint replacement is refused: 42P16 codex_probe_rules: the trigger rule_row_history is not the template's: it must run public.enforce_rule_row_history() as BEFORE UPDATE OR DELETE FOR EACH ROW, with no 
NOTICE:  PASS extra AFTER transition and constraint triggers are allowed: success 
NOTICE:  PASS trigger arguments are harmless for current functions, which do not read TG_ARGV: success 
NOTICE:  PASS cast and CTE preserve C collation
== p02-relations-and-rules.sql
NOTICE:  PASS inheritance child refused: 42P16 codex_probe_rules: codex_probe_rules has an inheritance child (codex_child): a row inserted into the child skips this table's triggers, and the lookups read it (v5.4.2-17)
NOTICE:  PASS dropped child leaves no stale refusal: success 
NOTICE:  PASS ordinary view over registered table is allowed: success 
NOTICE:  PASS rewrite rule on INSERT: 42P16 codex_probe_rules: codex_probe_rules has a rewrite rule (codex_rule): it can change or swallow a write before the triggers see it (v5.4.2-17)
NOTICE:  PASS rewrite rule on UPDATE: 42P16 codex_probe_rules: codex_probe_rules has a rewrite rule (codex_rule): it can change or swallow a write before the triggers see it (v5.4.2-17)
NOTICE:  PASS rewrite rule on DELETE: 42P16 codex_probe_rules: codex_probe_rules has a rewrite rule (codex_rule): it can change or swallow a write before the triggers see it (v5.4.2-17)
NOTICE:  PASS SELECT _RETURN rule is detected on its owning view
NOTICE:  PASS partition child detected through pg_inherits
NOTICE:  PASS partitioned parent refused by registration relkind check: 22023 codex_parent is not an ordinary table in public (v5.4.2-17)
NOTICE:  PASS late trigger on a partition is inspected
== p03-adoption-spans.sql
NOTICE:  PASS only system_span differs: 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules holds 1 legacy row(s) whose stored spans do not match their owner types, system kinds and jurisdiction: comput
NOTICE:  PASS only jurisdiction_span differs: 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules holds 1 legacy row(s) whose stored spans do not match their owner types, system kinds and jurisdiction: 
NOTICE:  PASS only owner_span differs: 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules holds 1 legacy row(s) whose stored spans do not match their owner types, system kinds and jurisdiction: compute
NOTICE:  PASS punctuation-only legacy key refused: 42P16 codex_probe_rules does not fit the rule-table template: codex_probe_rules holds 1 legacy row(s) with a blank key in customer_class: lookup could not address them and the fil
NOTICE:  PASS reordered sets and alternate range representation register and adopt
== p04-unfilled-readers.sql
NOTICE:  PASS unfilled direct citation refused: 23514 codex_probe_rules row c0de0000-0000-4000-8000-000000000099 is not yet adopted into the convention: its document is empty, so what it says is not known (v5.4.2-17)
NOTICE:  PASS unfilled law lookup refused: 23514 codex_probe_rules: the law row for {"customer_class": "legacy"} on 2020-01-01 is not yet adopted into the convention — its document is empty, so what it says is not known (v5.4.2-17
NOTICE:  PASS law citation wrapper also refuses: 23514 codex_probe_rules row c0de0000-0000-4000-8000-000000000099 is not yet adopted into the convention: its document is empty, so what it says is not known (v5.4.2-17)
NOTICE:  PASS tariff lookup refuses a law table before reading it: 22023 codex_probe_rules is not a tariff table (v5.4.2-17)
NOTICE:  PASS seeding does not silently accept or fill an unfilled row: 23505 codex_probe_rules already holds this law row (c0de0000-0000-4000-8000-000000000099 from 2000-01-01) with a different terms, terms_kind, terms_version: a
NOTICE:  PASS legacy close still enforces old citation floor: 23514 codex_probe_rules row c0de0000-0000-4000-8000-000000000099 cannot close on 2020-01-01: a citing record needs it in force on 2020-01-01 (v5.4.2-17)
NOTICE:  PASS legacy close above floor remains allowed: success 
NOTICE:  DEFECT audit rule reference should refuse unfilled law: expected 23514 / not yet adopted, observed <NULL> / <NULL>
== p05-note-dependent-facet.sql
NOTICE:  PASS two-document dry-run accepts this conditional path
NOTICE:  PASS note=other is valid under the registered schema
NOTICE:  DEFECT every valid note value is storable (sampling limitation): expected <NULL> / , observed 22000 / facet note_n of codex_probe_law v1: path $.note ? (@ == "other") matched "other", not a integer (v5.4.2-17)
== p06-schema-and-exemption.sql
NOTICE:  PASS optional strategy within present object refused through $defs: 23514 term schema codex_optional_strategy v1 is outside the subset the validator enforces: /$defs/fee: "strategy" must be required — an object that may l
NOTICE:  PASS optional containing object with required strategy is allowed: success 
NOTICE:  PASS governs reference gets inline diagnostic: 23514 term schema codex_ref_governs v1 is outside the subset the validator enforces: : a oneOf needs exactly one property that every branch requires with a string const writt
NOTICE:  PASS citation and note may still be references: success 
NOTICE:  PASS reserved-name impostor gets ordering diagnostic before registration
== p07-forbidden-note-false-refusal.sql
NOTICE:  PASS delegated document with note is outside this registered schema
NOTICE:  PASS valid delegated document derives nullable cap
NOTICE:  PASS valid law document derives numeric cap
NOTICE:  DEFECT schema-compatible facets must register when note is forbidden: expected <NULL> / , observed 42P16 / codex_probe_rules does not fit the rule-table template: codex_no_note v1: its facets cannot be derived from the st
```

p04 DEFECT = S1 (audit reference to an unfilled row) reproduced. p07 DEFECT = B1 (note-forbidden schema refused) reproduced. p05 DEFECT is the sampling limitation Codex itself labels, recorded as R22. p01-p03, p06 print no defect.
