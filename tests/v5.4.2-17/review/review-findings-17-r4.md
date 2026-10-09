# v5.4.2-17 review round 4: findings and dispositions

**Frozen:** patch `ad7045b9e680af4ca0f72212013a7cd5` (3,080 lines), battery `a24cdfb2cf48d8ec9e137468d26e84c1`. Codex verified both hashes.

**Verdict:** Codex, **not yet**: two blocking items. Opus and Fable reviewed r3 (both "ready") and were not asked about r4. Codex ran, but its sandbox could not reach Docker, so every database claim in its review was static. Ryan's instruction stands: Codex's review of r4, then ask Ryan to approve the mirror.

**Review:** `review-r4-codex.md`. Codex confirmed its round-2 blockers B1-B3 and the r3/r4 changes hold in the source.

**Reproduced before folding** (frozen r4 on a scratch clone, 2026-10-09; Codex's B1/B2 SQL predictions and S1 were static):

| # | Finding | Who | Reproduced | Disposition |
|---|---|---|---|---|
| B1 | A law kind registers with a delegated branch no document can satisfy (`maxLength: 1` on `governs`): `rule_terms_schema_errors` returned `{}`, the INSERT succeeded, and the standard delegated document failed with "at most 1 characters" | Codex B1 | **Yes** | **Fixed.** The branch must equal the standard one after dropping annotations: exact `governs`, `citation` and `note` property schemas, `required` exactly `[governs, citation]`, no other keyword. R3d, R3e, R3f (refused), R3g (annotations allowed); M141, M142, M143 |
| B2 | The version rule ran only inside a `oneOf` discriminated by `strategy`; a lone `{strategy: const "flat"}` object with no version registered as a tariff kind | Codex B2 | **Yes** | **Fixed.** The rule moved out of the union into the object case: any object schema with a `strategy` property requires a bounded integer `version`. One guard, not two, so no redundant check for a mutation to hide behind. R4q (refused), R4r (same schema with a version registers); M112 retargeted |
| S1 | `rule_row_seed` read a scalar or object in `owner_types` / `system_kinds` as NULL ("every one") and returned the id of an existing all-applicability row | Codex S1 | **Yes**, 6 of 6 malformed values accepted and returned the existing id | **Fixed.** Each applicability field is typed before matching: null or an array of strings (`commission_jurisdiction`: null or a boolean). T4n0 (the valid re-seed still works), T4n1-T4n5; M144-M148 |
| S2 | `lawc` checks a lone surrogate in values but not in object keys | Codex S2 | Yes (Codex executed it) | **Fixed.** Keys get the same check. W5 covers value, key, and a valid supplementary character |
| S3 | The header and residual R14 still said the old-column equality belongs in the insert check | Codex S3 | Read, not run | **Fixed.** Both name the adoption check; R14 says why the insert check is the wrong place |

**Recorded, no change:**
- Codex notes W4 mutates documents and not registration schemas, so it cannot find a registration-format hole like B1 or B2. That is why both are tested at registration in the battery.
- The mutation runner reads the working patch and fixed database names (`m17`, …), so a reviewer's frozen-artefact run needs an adapted copy. Unchanged.
