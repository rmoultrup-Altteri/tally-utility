# Review round 2: v5.4.2-18 — backbilling at the rule-terms convention

Same brief as round 1 (`review-brief-18-r1.md`: read it, and your round-1 findings) — this is the revision folding round 1. Dispositions: `review-findings-18-r1.md`.

**Frozen r2** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes):
- patch `tests/v5.4.2-18/review/patch-18-frozen-r2.sql` — md5 `2715fe7723fad45d6a71190eb805ec57` (814 lines)
- battery `tests/v5.4.2-18/review/battery-18-frozen-r2.sql` — md5 `294ea5f8814fc1aa3695d1f93be505fb`
- law file `law/backbilling/` (regenerated), `tests/v5.4.2-18/migration-18.py`, `mutations-18.py` (92 mutations), battery-13 groups C/Z

**What changed since r1:** (1) the sixteen bind `system_kinds = {distribution}` (Opus B1); (2) the eight unprotected rows are `delegated_to_utility` documents, not law — the adoption check demands it and demands the old columns claimed nothing; the fill clears their anchor facet (Opus B2, R10; **Ryan has not yet confirmed**); (3) the migration refuses any legacy row that is not Texas gas (Fable S1); (4) qualifying outcomes in byte order (Opus S3); (5) the adoption check no longer pretends to compare the anchor strategy (N1); residuals R1, R8, R9, R10 rewritten/added; (6) tests: cooperative/propane/master-meter/delegation lookups, owner-subset overlap, a city-type delegation and a master-meter row beside the sixteen, a closed legacy row, the check called in the trigger's row shape, G4 sweep; per-process names.

Review the changes and look for what they broke: the delegation's old-column conditions and the anchor-facet clearing; the Texas-gas refusal; whether anything else in the 16 rows is a delegation in disguise (the three R-39 rows say "never pending counsel"); whether `{distribution}` is right (is `distribution` the only system kind that serves gas to the public?); and the same probes as round 1. Same output rules (several messages under ~3 KB; verdict ready / not yet).
