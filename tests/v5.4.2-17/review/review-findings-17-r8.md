# v5.4.2-17 review round 8: findings and dispositions

**Frozen:** patch `3da8dfa0a23f68bb25c4a4c9b3dbd389` (3,452 lines), battery `49779ba424c6638df174bf41e4641a81` (272 PASS lines). All three reviewers verified both hashes.

**Verdicts:** Opus **ready**, Fable **ready**, Codex **ready**. No blocking item. All three confirmed each r8 change does what its finding asked (the note rule per version and through `$ref`; `rule_row_scope_check` unchanged in behaviour for tariff rows; the per-row registration loop; the audit guard; generated columns) and that no r1-r7 guard was weakened.

**Reviews:** `review-r8-opus.md`, `review-r8-fable.md`, `review-r8-codex.md`. Codex's sandbox cannot reach Docker; I ran its four probes (`codex-r8-probes/`) on a clone of the frozen r8 (outputs appended to its review). p01-p03 print no defect. The four p04 DEFECT lines are a probe-setup artefact (42501 on a function `tally_core` is not granted, before the guard runs); K4i/K4j covers the audit refusal through the real grants.

**r9 frozen:** patch `ed1b8298d22de9f5015a9007422eab19` (3,459 lines), battery `ac59a9437bd342138a952eb2a6477f56` (276 PASS lines). Against r8 the patch differs in comments only (`diff` of the non-comment lines is empty). `tests/ci.sh` all pass; `mutations-17.py` 198/198 caught (M196-M201 new; M187 retargeted to K4j). No further review round: the three reviewers already read this code.

**Disposition (r9 = tests, mutations and wording only; the patch's behaviour is unchanged):**

| # | Finding | Who | Disposition |
|---|---|---|---|
| 1 | Dropping the `governs` filter in the note rule survives: a kind whose law branch has a `note` would be refused again | Opus S2, Fable S1 | **Case T1zh** (a kind with a note on the law branch and none on the delegated branch registers). M198 |
| 2 | Narrowing the generated-column clause to facet columns survives: a generated key column and a generated `terms` register | Opus S1, Fable S2, Codex S1 | **Cases T1zf (key), T1zg (template).** M196, M197 |
| 3 | Dropping `terms_version = p_version` survives | Codex S1 | **Case T1zi** (v1 admits no note, v2 does; v1's facet registers). M199 |
| 4 | `LIMIT 1` on the legacy-row loop survives (every refusal fixture is one row) | Codex S1 | **Case A1m** (a good row, then a bad one). M200 |
| 5 | The tariff leg of the scope check has no case | Fable N3 | **Case U3d** (a water tariff of a gas-only kind). M201 |
| 6 | R26's last sentence describes r7 | Opus S3, Fable N1, Codex N1 | **Reworded.** |
| 7 | Two cases are named K4i | Codex N2 | **Renamed** to K4j (M187 retargeted). |

**Notes, no change:** identity columns are not "generated", so `terms_version` could be an identity column; nothing unchecked is stored, because each row is checked against the version it records (Opus). Registration reads the legacy rows before taking the table lock; only the owner can write a law table (Opus). A close of an unfilled legacy row is allowed by design (R26).
