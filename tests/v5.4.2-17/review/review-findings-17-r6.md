# v5.4.2-17 review round 6: findings and dispositions

**Frozen:** patch `e56f35010b3697680cff673cf44cbd8e` (3,256 lines), battery `f65867baaf103dd589c581520cd5228f`. All three reviewers verified both hashes.

**Verdicts:** Opus **ready**, Fable **ready**, Codex **ready**. No blocking item from anyone. All three confirmed the r5 folds hold (battery 247, mutations M149-M166 18/18 at their named checks) and that -13 and -15 can use r6 as built (their rule-table triggers are `a_…`).

**Reviews:** `review-r6-opus.md`, `review-r6-fable.md`, `review-r6-codex.md`. Codex's sandbox cannot reach Docker, so it wrote twelve probes (`codex-r6-probes/`); I ran them on a clone of the frozen r6. p12 reproduced its trigger-identity should-fix.

**r7 frozen:** patch `b2684ffd74aaa19998cd58b470ba6883` (3,377 lines), battery `e07b5516aa22f0103ab15086c93d5937` (262 PASS lines). `tests/ci.sh` all pass; `mutations-17.py` 182/182 caught (M167-M183 new; M63, M156, M159, M162 re-anchored).

**Method for r7:** each fix has a battery case written first and run alone against the r6 patch (`tests/v5.4.2-17/r7-fail-first.py`, one `-- r7:begin` block at a time, the battery's own setup, then ROLLBACK). Every case that is a new refusal printed "not refused" or "refused by another guard" on r6. Then the fold, then `tests/ci.sh`, then a mutation per clause.

| # | Finding | Who | Reproduced | Disposition |
|---|---|---|---|---|
| 1 | The trigger assertion knows the template's triggers by name. A template name pointing at another function, fewer events, a WHEN clause or a column list passes it; an inheritance child and a rewrite rule are outside it | Codex S2, Opus S1, Fable S1 | Codex, Fable, Opus (G1-G3, G8). On r6 here: T1q-T1v print "not refused" | **Fixed.** `rule_table_trigger_errors` requires, per template trigger, the function (`public.enforce_rule_row_insert` / `_history` / `enforce_rule_registry_no_truncate`), `tgtype` 7 / 27 / 34, no WHEN, no column list; the sorts-after exemption is by name and function; a table with an inheritance child or any rewrite rule is refused. T1q-T1v; M169-M174 |
| 2 | A legacy row with `terms IS NULL` on an adopting table is law to every reader: lookup returns it, cite accepts it, a tariff is measured against it. r6's blank-key check can also leave it unfillable | Fable S2, Codex N2, Opus N3 | A5a-A5c print "not refused" on r6 | **Fixed in two halves.** `rule_law_row_as_of`, `rule_row_cite` and the tariff check refuse it ("not yet adopted", 23514). Adopting registration refuses a legacy row with a blank key or with spans that differ from its sets. A5a-A5c, A1f, A1g; M179-M183 |
| 3 | The delegated dry-run covers `{governs, citation}` only: a facet reading `$.note` registers, then a delegated document with a note is refused | Opus S2 | F1 (Opus). T1z prints "not refused" on r6 | **Fixed.** The dry-run runs both documents. T1z; M178 |
| 4 | `strategy` may be optional (`required: ["version"]` registers and `{"fee": {"version": 1}}` validates) | Fable S3 | F5 (Fable). R4y prints "not refused" on r6 | **Fixed.** The version clause's object also requires `strategy`. R4y; M167 |
| 5 | Two trigger-name clauses untested (dropping `COLLATE "C"`, dropping the BEFORE bit) | Opus S3 | O01, O02 survived | **Fixed for what is true.** T1w (`rulerowa`, refused), T1x (`Zz_early`, allowed), T1y (an AFTER ROW `zz_after`, allowed). M175-M177. **Measured:** dropping `COLLATE "C"` alone changes nothing, because `pg_trigger.tgname` is already C-collated and the cast to text keeps it. Opus's O01 survived for that reason, not for lack of a case. The clause stays, with a comment saying so, and M175 compares in `en_US.utf8` instead, which T1w catches |
| 6 | `governs` cannot be a `$ref`; the README says a property may | Codex S1, Fable N2, Opus N5 | D3, E8 (refused by the discriminator rule) | **Fixed as wording, not interpreter.** The discriminator is inline: the refusal says so, and the README's union row and delegated-branch paragraph say so. R3j; M168 |

**Recorded as residuals (R22-R25), no code change:**
- A CHECK on a facet column, an unbound `$variable` in a facet path and a facet that fits the delegated document but not a law branch pass the dry-run and fail loudly at the first row they cannot store (Opus N1, N2, N4; Fable N3; Codex N1): R22.
- A facet is named after its column, so -13's and -15's typed NOT NULL columns go nullable or keep names no facet uses (Fable N5): R23.
- `assert_rule_table_invariants()` is vacuous until -13 is mirrored (Fable N6): R24.
- The reads are `FROM <table>`, not `FROM ONLY`; the invariant refuses a table with a child instead (Opus S1): R25.
- The delegated-branch refusal says "must admit" where the rule is "exactly" (Fable N1): unchanged; the README says "exactly".
- R14 step 2 now says registration refuses a legacy row the fill could not adopt.
