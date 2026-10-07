# Review r3 — v5.4.2-17 (the rule-terms convention, written once)

**Reviewer:** fable. **Date:** 2026-10-07.
**Artefacts checked:** patch `74c730ed9ceb11b7449f3b373a851000` (3054 lines), battery `9d91b4852638755db3d1734887d66fab` — both match the brief; `sql/v5.4.2-17-rule-terms-convention.sql` and `tests/v5.4.2-17/battery-17.sql` carry the same hashes.
**Environment:** `fable17r3` (TEMPLATE tally, TEMP revoked); strict apply twice, 0 errors each pass. Clones `fable17r3_iso`, `_race`, `_law`, `_m*`; all dropped at the end.

## Verdict: **ready** — no blocking item, no should-fix; three notes

What ran and passed, unmodified:
- battery: 216 PASS, 0 FAIL, rolled back (202 → 216);
- `isolation-17.sh` X1–X6; `races/rule-close-17.sh` RC1–RC7 (second session seen waiting in each; RC6/RC7 new);
- `lawfiles-17.sh` W1–W5 (899 documents, 0 disagreements);
- `assert_core_role_invariants()` and `assert_tenant_isolation_invariants()` on the applied clone;
- `mutations-17.py`, scratch copy pointed at the frozen r3 patch and `fable17r3_m*`: M125–M134 — 10/10 caught at their named checks (r1: 8/8, r2: 8/8 in earlier samples); I did not run all 136.

## 0. Round-2 findings, re-run against r3

| r2 | Re-run | Result |
|---|---|---|
| **F1** facet type not paired with the column's | `zz_coerce` (text[] / number / present facets on `text` columns) | **held**: registration refuses with every mismatch named (`facet component_ids is text[] but zz_coerce.component_ids is text; … has_fee is present but … is text …`). A kind registered with one facet whose column is `text` for a `number` facet is refused too (my F1b). `rule_facet_column_errors` (1417–1429) runs at registration for every version of the kind and again in `rule_row_prepare` (1744–1749), so a later version's facet on a wrong column fails at its first row |
| **F2** adoption check in the permanent insert check | adopt with `p_adoption_check = zz_legacy_check`, then insert a new commercial row (cap 75), then `DROP COLUMN legacy_cap`, then another new row | **held**: both new rows stored (`new rows after adoption: 2`); the adoption check runs only in the fill branch (2033–2036). A supplied `terms` that contradicts `terms_source` at adoption is refused (`terms is derived from terms_source`), as finding 13 says. `rule_tables_adoption_check` CHECK ties the flag to the hook (1352) |
| **F3** union hop counted as a level | root-`oneOf` recursive schema | **held**: 64 deep valid, 65 refused in the DB; `lawc.reference_errors` says the same (64 valid, 65 `nested too deeply`). V24 covers Codex's shape |
| N3 `version` via `$ref` refused | `$ref` to `{integer, 1..1.5}` | **held**: resolved and accepted; range semantics 1 ≤ min ≤ max (R4n/R4o) |
| N1 charge under delegated law with no tariff | — | tested as C2g |

No fix opened a hole I could find:
- the fill branch now passes the row as written to `rule_row_prepare`, so a writer-set facet or `terms` is compared, not discarded;
- adopting registration refuses any row with `terms`, `terms_source`, `terms_kind` or `terms_version` set (A1e) — and still requires nullable document columns, so a non-adopting table cannot slip pre-filled rows past it (non-empty refused, A1d);
- the re-seed compares every named column except the applicability set columns and `terms_source` (compared parsed), and treats a missing `effective_to` against a stored end as a difference (2271–2283); a re-seed of the same row returned the same id (probed); a seed naming `created_at` would always differ — correct strictness;
- the freeze compares text (R8c), so `0` → `0.0` under a freeze is an edit;
- `assert_core_role_invariants()` is owner-only (`tally_app`/`tally_core` EXECUTE both false), and I made it fire on `GRANT CREATE ON SCHEMA zz_side TO tally_core` and on `GRANT tally_app TO tally_core`, both rolled back; `tests/ci.sh` runs it last.

## Notes

- N1. A strategy `version` range may have a non-integer bound: `{integer, minimum 1, maximum 1.5}` registers. Harmless (the `integer` type still refuses 1.5 in a document), but the message "1 ≤ minimum ≤ maximum" implies integer bounds; add `trunc()` equality or leave it.
- N2. A re-seed treats `fee_cap: 50.0` as the same row as stored `50` (jsonb equality; the facet is derived anyway). Consistent with the document being compared parsed; different from the close/freeze rule, which is deliberately textual. Fine as is, but say so in the `rule_row_seed` comment.
- N3. `rule_facet_column_errors` is one more catalog read per rule-row write. Negligible for law rows; tariff writes are rare. No action.

## 1. The spec

Unchanged from r2 except: T1 now has the adoption hook as its own column (held); F1–F3 held with paired types; V5 held as a range, which is what v2 §11 asks (strategies version independently of documents); C1's invariants are a reusable assertion in CI. P1 class scope remains residual R10; T7 R2; R9–R18 stated. -13 can follow R14 as written: the equivalence check is adoption-only, so dropping the old columns afterwards costs nothing, and a new row inserts normally (A4; my F2 re-run).

## 2. Tests

Added and verified by name: R4n/R4o, V10b, V13b, V24, T1h, T4k, R8c, C2g, A1c/A1e/A4, K8, K9, O1, O2, RC6, RC7; M125–M136. Remaining gaps are small: a tariff spanning a `law` row and a `delegated` row; `tally_core` UPDATE on a tariff/law row refused by grant; `coverage_to >= coverage_from`. None guards a path an application role can reach.

## 3. Housekeeping

Databases `fable17r3*` dropped. No repo file other than this one written.
