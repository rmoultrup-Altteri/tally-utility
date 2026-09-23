# Review brief — v5.4.2-12, the meter test history (round 3, frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-12-meter-test-history.sql` (= `review/patch-12-frozen-r3.sql`) | 1699 | `ce8fcbe3f4d10f2a654bad0bcfcc7093` |
| `tests/v5.4.2-12/battery-12.sql` (= `review/battery-12-frozen-r3.sql`) | 988 | `ddbdee642981426c4e732a3649cd6047` |
| `tests/v5.4.2-12/isolation-check-12.sql` (new) | 36 | `cd99eaf3122a941c81e0159464268d49` |

Frozen. **Do not edit any file in the repo.** Rounds 1 and 2 briefs
(`review-brief-12.md`, `review-brief-12-round2.md`) still govern environment,
rules of engagement and scope.

## Round 2 — what was found, what changed

Both round-2 reviewers confirmed all ten round-1 fixes. Siblings folded:

| # | Finding (who) | Change | Pinned by |
|---|---|---|---|
| 1 | tenant session self-promotes to platform_admin (users.role unguarded), then moves cutover (both) | New §1b `enforce_platform_admin_grant()`: for tally_app, a row may BECOME platform_admin only if the session already is one. ENABLE ALWAYS | K1, K2, K3; M10 |
| 2 | migrated_full with no readings (inconclusive_reason) switched the R-36 gate off by label (Opus) | CHECK: migrated_full requires load_results | K4; M11 |
| 3 | parallel same-date date-only row displaced a derived failure by insertion order (Fable) | Pointer and governing test tie-break on record_basis strength before recorded_seq | K5; M12 |
| 4 | cutover change under RR/SERIALIZABLE crossed the boundary (Opus) | Cutover change refused unless `transaction_isolation = 'read committed'` | isolation-check-12.sql ISO1–3; M14 |
| 5 | date-only failure superseded by a bare inconclusive_reason (Opus) | A correction of a row with found_defective = true must carry readings | K6; M13 |
| 6 | cutover self-lock deadlock; recorder not ENABLE ALWAYS; stale lock comment (both, LOW) | Lock-order rule documented in §3; `trg_record_tenant_configuration_change` ENABLE ALWAYS; comment fixed | I2 |
| — | Residuals added: R14 (both platform guards name tally_app), R16 (1b is not a role model — coda A2 stays open), R17 (no backfill history row for pre-existing tenants), R18 (date-only assertion may replace assertion, except a failure) | | |

Verification: strict apply ×2 clean; battery **108 PASS**; isolation script 3
PASS; regressions 28 / 58 / 41; fourteen planted mutations (M1–M14) each
caught by its named check.

## What I want from round 3

1. Confirm or refute each round-2 fix against its round-2 repro (your r2
   scratch directories are still there).
2. The new surfaces: §1b (every path by which a users row can become
   platform_admin — INSERT … ON CONFLICT, UPDATE of other columns, a trigger
   elsewhere); the tie-break (can a same-date row still win in any reader —
   the gap view, entered_out_of_order, the cutover bounds check?); the
   isolation refusal (does it block anything legitimate, e.g. onboarding
   tooling that runs in one SERIALIZABLE transaction?); the widened
   defective-readings rule.
3. If you find nothing above LOW, say so plainly: "sound enough to mirror".

Deliverable as before: findings with severity, runnable repro and real output,
finding separate from fix, fix measured or not; a confirm/refute line per
round-2 fix; what you checked and found sound.
