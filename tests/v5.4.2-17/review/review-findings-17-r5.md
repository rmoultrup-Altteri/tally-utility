# v5.4.2-17 review round 5: findings and dispositions

**Frozen:** patch `d20d453c0aaecadb79ffdc0852d8cb56` (3,120 lines), battery `ea9bb460c10534fce95b9c5883e48904`. All three reviewers verified both hashes.

**Verdicts:** Opus **ready**, Fable **ready**, Codex **ready** (source review). No blocking item from anyone. All three confirmed the r4 fixes (B1, B2, S1-S3) hold and opened no new hole.

**Reviews:** `review-r5-opus.md`, `review-r5-fable.md`, `review-r5-codex.md`. Codex's sandbox cannot reach Docker, so it wrote nine probes (`codex-r5-probes/`); I ran them on a clone of the frozen r5. p01-p05, p07, p08 printed no failure; p06 and p09 reproduced its two should-fixes (output appended to its review).

| # | Finding | Who | Reproduced | Disposition |
|---|---|---|---|---|
| 1 | 8 of 9 clause-removal mutations survive: nothing only the new clauses can fail | Opus S1 | Yes (Opus) | **Fixed.** R3h, R4s, R4t, R4u, R4v isolate the required-citation clause and each version clause. M149, M151-M154 |
| 2 | A law table's facets can make the delegated document unstorable: a strict path gives 2203A, a NOT NULL facet column gives 23502, and both tables register | Opus S2 | Yes (Opus) | **Fixed.** `rule_law_delegated_facet_errors` dry-runs the standard delegated document through the kind's facets at law-table registration (every existing version) and at a later version's first row. T1n, T1o, T1p; M156, M157, M158 |
| 3 | A strategy schema may be a plain string, so any name validates; convention v2 §4-5 says the names are closed | Opus S3 | Static | **Fixed.** A strategy needs a string `const` or an `enum`. The `type` clause I first wrote was redundant (const and enum exist only under a string), so only the const/enum test remains. R4w, R4x; M155 |
| 4 | The delegated-branch exact compare refused a `citation` written as `{"$ref": …}`, with a message saying the opposite of the truth | Fable S1, Opus N1 | Yes (Fable) | **Fixed.** `governs`, `citation` and `note` are resolved before the compare. R3i; M150 |
| 5 | A BEFORE ROW trigger sorting after `rule_row_insert` / `rule_row_history` rewrote `terms`, `fee_cap` and a closed row's `source_note` after validation (owner DDL only) | Fable S2 | Yes (Fable) | **Fixed.** `rule_table_trigger_errors`: registration refuses any BEFORE ROW trigger sorting at or after `rule_row_history`; `assert_rule_table_invariants()` (tail and CI) also requires the template's three triggers ENABLE ALWAYS. T1i-T1m; M159-M162 |
| 6 | A direct insert accepts a blank area key that lookup and seed refuse (an unaddressable row) | Codex S1 | Yes (p06) | **Fixed.** `rule_row_prepare` applies `rule_key_check`, for law and tariff rows. T4a2, U2z; M163 |
| 7 | Published values and bounds accept `Infinity` and `-Infinity` | Codex S2 | Yes (p09) | **Fixed.** The value guard and both CHECKs refuse NaN and both infinities. P3c2, P3c3, P3c5 (and P3c4, a finite value of the same unbounded parameter, still publishes); M164-M166 |

**Recorded as residuals or comments, no code change:**
- `stamp_core_inputs` fingerprints at INSERT only (Fable note): R19.
- A seed and the adoption fill compare jsonb where a freeze and a close compare text; `-0` and `1E2` are normalised by jsonb before the canonical check (Fable notes): R20.
- A seed does not type its dates (Opus N4): R21.
- R14 step 1 now says the migration computes the spans (Fable note).
- The version rule is keyed on the property name `strategy` (Opus N2): that is the convention's own name, and `law/README.md` now says the name is what makes it a strategy. A version range no document can satisfy (`minimum 1, maximum 1, exclusiveMaximum 1`) still registers (Opus N3): an unsatisfiable tariff shape is its author's problem, unlike the delegated branch. NFC and NFD spellings of a key are distinct keys (Opus N5), as in standard JSON; unchanged.
- A seed that repeats a JSON number as a date fails closed on re-seed (Opus N4): R21 states it exactly.
