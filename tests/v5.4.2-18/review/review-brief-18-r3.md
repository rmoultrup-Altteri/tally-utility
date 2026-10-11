# Review round 3: v5.4.2-18 — backbilling at the rule-terms convention

Same brief as rounds 1–2 (`review-brief-18-r1.md`, `review-brief-18-r2.md`). This revision folds round 2 (Opus: ready on the code; Fable: ready; both conditional on Ryan confirming R10). Dispositions below. **Codex has not reviewed any round yet (usage limit): Codex, review the whole patch fresh, with the r1 brief's questions.**

**Frozen r3** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes):
- patch `tests/v5.4.2-18/review/patch-18-frozen-r3.sql` — md5 `cc820b6de0d3671d1337b7157639903b` (866 lines)
- battery `tests/v5.4.2-18/review/battery-18-frozen-r3.sql` — md5 `294ea5f8814fc1aa3695d1f93be505fb`
- `law/backbilling/`, `tests/v5.4.2-18/migration-18.py` (P1–P7), `mutations-18.py` (97 mutations, all caught), battery-13 groups C/Z

**r2 -> r3:** (1) the adoption check requires the row's note and class to agree (note says "7.45 does not reach this class" iff class = unprotected) — Fable r2 S2; (2) a delegation may drop the cause facts (qualifying outcomes, units flag, delivery path) only when the protected row of the same cause and start says the same — Opus r2 S1; (3) R10 rewritten: those facts are Kyle's classification of the cause (R-39/R-33), not defaults; after -18 the core has nowhere to read them for an unprotected case, so the future backbilling tariff kind or core cause semantics must restate them (HANDOFF will say so); a delegated window must be bounded by limitations law by the future tariff comparator (Fable r2 S1, Opus N2); (4) R11 new: the three R-39 rows are law-shaped placeholders pending counsel, plus the question whether uncapped protected rows mean "no limit" or "the tariff's limit" (Opus r2 S2/N1). Tests: P7ah–P7al, mutations M94–M98.

**Still open for Ryan (not for you):** whether the eight unprotected rows are delegations (R10) rather than law.

Same output rules (several messages under ~3 KB; verdict ready / not yet). Codex: write probes as .sql files in `tests/v5.4.2-18/review/codex-r3-probes/`; the author runs them on a clone of the frozen patch.
