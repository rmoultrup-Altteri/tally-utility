# Review round 7 (Opus): v5.4.2-17 r6-to-r7 diff

**Hashes match:** patch-17-frozen-r7.sql `b2684ffd74aaa19998cd58b470ba6883`, battery-17-frozen-r7.sql `e07b5516aa22f0103ab15086c93d5937`.

**Docker ran.** I cloned `opus717` from `tally`, revoked TEMP, and strict-applied the r7 patch (`search_path=''`, `check_function_bodies=on`). The battery ran from a copy with `/tmp/law` rewritten to `/tmp/opus7law`, so the shared `/tmp/law` was never touched: 262 PASS. I then appended probes before the battery's ROLLBACK, each in its own subtransaction. For the mutation checks I made four throwaway databases, `opus717m{ns,span,exfn,btrim}`. All databases and container files I created have been dropped.

## Verdict: **ready**. Nothing blocking.

All six r7 changes do what their findings asked. I found no r1-r6 guard weakened by r7. There are three should-fix items. Two are cases where an r7 check is narrower than what it claims (S1, S2). The third is a test gap: four mutations survive (S3).

---

## 1. Per change

### 1.1 Template triggers known by identity: correct
The CTE is at patch :1517-1555. All of these are refused with the "not the template's" message:
- P2: the template name with the right function, AFTER INSERT, with a transition table.
- P3: the template name as a DEFERRABLE constraint trigger.
- P4: the history trigger widened to INSERT OR UPDATE OR DELETE (tgtype 31).
- P5: the truncate trigger made AFTER.
- P6: a same-named function in another schema. It is refused by both the sort clause and the identity clause, because `p.pronamespace='public'` leaves `fn` NULL.
- P7: a late-named BEFORE ROW trigger running the template's history function. Refused as sorting after.

These pass, correctly:
- P1: the template trigger with a trigger argument. The function never reads TG_ARGV, so this is harmless.
- P8: a late-named BEFORE STATEMENT trigger. It cannot change a row.

The rewrite-rule clause catches an ON DELETE DO ALSO NOTHING rule (P9). An inheritance child that is created and then dropped leaves no residue (P10).

**The registered table as a child, not a parent (P11, P12).** `ALTER TABLE <registered> INHERIT parent`, and `ATTACH PARTITION <registered>` to a partitioned parent, both pass the assertion. Both are harmless, so I am not asking for a check:
- TRUNCATE on the parent fires the child's `rule_row_no_truncate` (refused, 23001).
- DELETE through the parent fires the child's `rule_row_history` (refused, 23001).
- Lookups never read the parent.

A partition *of* a registered table is impossible, because registration requires `relkind='r'` (:1652). The `COLLATE "C"` in the sort comparison is neutral, as the brief says. `pg_collation_for(tgname::text)` is `"C"` in a database whose default collation is `en_US.utf8` (P13). I found no case where it is not neutral.

### 1.2 Unfilled legacy rows: the three readers are correct
On my own adopting table `zz_lu`, with an unfilled commercial row:
- The lookup refuses with "not yet adopted" (Q1).
- `rule_law_row_cite` refuses, through `rule_row_cite`, before it resolves the row (Q2).
- `rule_row_cite` as `tally_app` refuses (Q5).
- The A5c fixture covers the tariff check.
- Adopting registration orders spans correctly: owner_types `{municipal,cooperative}` against the canonical stored span registers (Q6). Both sides compare `int4multirange` values, which are canonical, so order and representation cannot differ.
- A key that is only a no-break space is refused (P24). The `[[:alnum:]]` whitelist holds.

Other readers of an unfilled row:
- **Seed (Q4):** refused, but the message says "already holds this law row … with a different terms, terms_kind, terms_version", not "not yet adopted". Note N1.
- **Audit findings (Q3):** accepted. `tally_core` can file a finding whose rule row is unfilled. It is stamped `terms_kind=NULL` and `terms_version=NULL` (`enforce_rule_audit_finding`, :3000-3007). Note N2.
- **Close (P19):** a superuser can close an unfilled row, and the row can still be filled afterwards. That is fine.

### 1.3 Delegated dry-run with a note: correct for T1z, but it over-refuses (S2)

### 1.4 Strategy required: correct
The clause is at :565. R4y and M167 are specific to it.

### 1.5 Name-clause cases T1w, T1x, T1y: each fails only its own mutation
Confirmed from M175-M177 in `mutations-17.py:495-500`.

### 1.6 Inline discriminator: message and README agree
`tools/law/lawc.py:192-204` also counts only an inline `const`, so the tool and the database apply the same rule.

---

## 2. Should-fix

### S1. Adopting registration still admits legacy rows the fill can never adopt, and a lookup can reach them
The new pre-check (:1764-1787) covers a blank key and mismatched spans. The fill (`rule_row_prepare`, :2012-2029) refuses more than that, independent of the document:
- an unknown state (no state place);
- a system kind that is not a kind of the row's service.

Neither can be corrected through the fill, which changes only document columns. So such a row stays unfilled for good unless someone disables the triggers. That is the same class of defect as r6 Fable S2.

Reproduction (Q7):
1. An electric legacy row with `system_kinds={distribution,master_meter}` and its span computed correctly. The adopting registration is **accepted** (Q7a).
2. The fill is refused: "system kind master_meter is not a kind of electric system" (Q7b).
3. A city-owned electric distribution profile in ZZ looks it up and gets "not yet adopted", now and forever (Q7c). The span `{[0,2)}` contains distribution, so the lookup reaches the row.

P22 shows the same for state `QQ`: registration passes and the fill is refused. No profile reaches that row, so it is stuck but unseen.

**Fix:** put the document-independent half of `rule_row_prepare` into one function: the key check, the state place, system kinds against the service, and the spans. Call it from the fill and, for every legacy row, from registration. Then the two checks cannot drift apart. The current check is narrower than its comment, "Every legacy row must be one the fill can adopt" (:1764).

Real -13/-15 rows are Texas gas rows, and every system kind admits gas, so the practical risk today is low.

### S2. The note dry-run refuses tables whose kind admits no note
The second document (:1599) is run whether or not the kind's delegated branch admits `note`. A delegated branch may omit `note` (:1040 allows `<@ {citation,governs,note}`). For such a kind, a law branch can carry its own `note` of another type.

Reproduction (P15): kind `zz_intnote` has a delegated branch with no `note`, and a law branch with `note: {"type":"integer"}`. Facet `note_n` is an integer at `$.note`, on a nullable column. Registration is **refused**: "path $.note matched "x", not a integer". Yet `rule_terms_errors` rejects that noted document for this kind ("/note: unknown key", P15b). No valid delegated document fails, so this is a refusal of something that should be allowed. `rule_row_prepare` (:1966) runs the same function at every law-row write, so every row of such a kind would also be refused.

**Fix:** dry-run a document only when `rule_terms_errors(schema, doc)` is empty. Equivalently, run the noted document only when the delegated branch's properties include `note`. This is contrived, but the fix is one line.

### S3. Mutations that survive the battery
Each was applied to a fresh clone and the full battery run: 262 PASS, rc 0, for all four.

| Mutation | What survives | Missing case |
|---|---|---|
| `ns` | `p.pronamespace = 'public'::regnamespace` dropped from the `trg` join (:1527) | A template trigger running `<otherschema>.enforce_rule_row_insert()`. P6 shows the clause is what refuses it. |
| `span` | the `system_span` and `jurisdiction_span` legs dropped from the registration span check (:1782-1783) | A1g only puts the owner span off. Add a legacy row whose system span, and one whose jurisdiction span, disagrees. |
| `exfn` | `AND m.fn = t.fn` dropped from the sorts-after exemption (:1537) | None possible. The identity clause catches every case the exemption's function test would, so either remove the test or say in a comment that it is redundant. |
| `btrim` | the blank-key test `%I !~ '[[:alnum:]]'` replaced by `btrim(%I) = ''` (:1774) | A1f uses an ASCII space. Use a no-break-space key (as in P24) so the whitelist is what is tested. |

---

## 3. Notes

- **N1.** The seed's message on an unfilled row (Q4) is misleading. It is refused for the right reason in effect, but the message names a "different terms". Optionally, check `terms IS NULL` on `v_existing` in `rule_row_seed` (:2531) and say "not yet adopted".
- **N2.** An audit finding can name an unfilled law row (Q3), and is stored with NULL kind and version. The core cannot have evaluated that row, because every lookup refuses it. Either refuse it in `enforce_rule_audit_finding`, or record it as a deliberate allowance, since a finding *about* an unadopted row may be legitimate.
- **N3.** With a non-text area-key column, adopting registration fails on a raw `42883 operator does not exist: integer !~ unknown` (P23). The consolidated "does not fit the template" message is lost. It is still refused. Skip the blank-key EXECUTE when the column's type is not `text`.
- **N4.** Duplicate owner_types in a legacy row: `rule_applicability_span` raises 23514 from inside the registration's count query (P20). It is still refused, but outside the consolidated message.
- **N5 (outside the r7 diff, from r1-r6, not opened by r7).** A facet column that is `GENERATED ALWAYS … STORED` registers, and its stored value overrides the template's facet. Reproduction (P14): `fee_cap GENERATED ALWAYS AS (0)` registers, and a flat-fee row is stored with `fee_cap=0` while the document says 50. PostgreSQL computes stored generated columns after BEFORE ROW triggers. This is another route around the template's write, in the family r7 change 1 closes. The patch has no `attgenerated` test anywhere. One fix covers it: refuse `attgenerated <> ''` on facet and template columns in `rule_table_column_errors` / `rule_facet_column_errors`, and in the assertion. The same applies to a generated `owner_span` or similar column.
