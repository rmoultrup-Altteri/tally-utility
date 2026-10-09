# v5.4.2-17 review round 7: findings and dispositions

**Frozen:** patch `b2684ffd74aaa19998cd58b470ba6883` (3,377 lines), battery `e07b5516aa22f0103ab15086c93d5937` (262 PASS lines). All three reviewers verified both hashes.

**Verdicts:** Opus **ready**, Fable **ready**, Codex **not yet** (one blocker, B1, which Opus also found as a should-fix). All three confirmed the six r7 changes do what their findings asked and that no r1-r6 guard was weakened.

**Reviews:** `review-r7-opus.md`, `review-r7-fable.md`, `review-r7-codex.md`. Codex's sandbox cannot reach Docker; I ran its seven probes (`codex-r7-probes/`) on a clone of the frozen r7 (outputs appended to its review): p04 (S1) and p07 (B1) reproduced; p05 is the sampling limitation already recorded as R22.

**r8 frozen:** patch `3da8dfa0a23f68bb25c4a4c9b3dbd389` (3,452 lines), battery `49779ba424c6638df174bf41e4641a81` (272 PASS lines). `tests/ci.sh` all pass; `mutations-17.py` 192/192 caught (M184-M195 new, M178 re-anchored, M179-M180 retired).

**Method for r8:** each fix has a case written first and run alone against the r7 patch (`tests/v5.4.2-17/fail-first.py`). Then the fold, `tests/ci.sh`, and a mutation for each new clause.

| # | Finding | Who | Reproduced | Disposition |
|---|---|---|---|---|
| 1 | **The note dry-run refuses a valid table.** It tries a delegated document with a note even where the kind's delegated branch forbids one (`additionalProperties: false`), so a facet that works for every valid document is refused at registration | Codex B1, Opus S2 | Opus, Codex (p07). T1za fails on r7 | **Fixed.** The note sample is tried only where a delegated branch of the kind's schema has a `note` property. T1za; M184. The strict `$.note` case (T1zb) and M185 keep the no-note document honest |
| 2 | Registration is narrower than the fill: the fill also refuses an unknown state and a system kind that is not of the row's service; registration checked neither | Opus S1 | Opus (an electric row with `master_meter`). A1j, A1k fail on r7 | **Fixed by sharing the checks, not copying them.** `rule_row_scope_check` (state, system kinds) is extracted from `rule_row_prepare`; registration runs it, `rule_key_check` and the span compare on every legacy row. A1j, A1k; M190-M192 |
| 3 | A1g put only the owner span off: dropping the system-span or jurisdiction-span leg survives | Fable S1, Codex S2, Opus S3 | Fable, Opus | **Fixed.** A1h (system), A1i (jurisdiction); M193-M195 (one per leg) |
| 4 | Dropping `p.pronamespace = 'public'` survives: `zz_other.enforce_rule_row_insert()` under the template name passes the assertion | Fable S2, Opus S3 | Fable | **Fixed.** T1zd; M188 |
| 5 | Dropping the function test from the sorts-after exemption survives (the identity clause also reports) | Codex S2, Opus S3 | Codex (static) | **Fixed with a case where the other clause is inactive.** T1zc registers a table that already carries a `rule_row_insert` impostor: without the function test, registration passes the ordering check and `CREATE TRIGGER` fails with 42710 instead of 42P16. M189 |
| 6 | Dropping the no-note document survives, because T1p's `strict $.fee.cap` raises on both | Fable S3 | Fable | **Fixed.** T1zb (a strict `$.note` facet); M185 |
| 7 | The audit-findings guard accepts a rule row with no document and stamps NULL kind and version | Fable S4, Codex S1, Opus note | Codex (p04) | **Fixed.** Refused with the "not yet adopted" wording. K4i; M187 |
| 8 | The blank-key test replaced by `btrim() = ''` survives (A1f used an ASCII space) | Opus S3 | Opus | **Fixed by removing the copy.** Registration now calls `rule_key_check` itself, so there is no second test to drift; A1l (an em-dash key) pins it. M190 |
| 9 | A `GENERATED ALWAYS … STORED` template, key or facet column registers and overwrites the facet (since r1) | Opus | Opus (`fee_cap` stored 0, document said 50) | **Fixed.** Registration refuses it. T1ze; M186 |

**Recorded as R26, no code change:** a close of an unfilled legacy row is allowed (by design); a seed of an unfilled row is refused as "different terms"; a non-text key or repeated owner types refuse registration with the underlying error. R22 now says the note is tried only where admitted.

**Dropped:** M179 and M180 (the r7 inline blank-key and span tests they mutated no longer exist; M190-M195 replace them).
