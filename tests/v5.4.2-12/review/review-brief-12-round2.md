# Review brief — v5.4.2-12, the meter test history (round 2, frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-12-meter-test-history.sql` (= `review/patch-12-frozen-r2.sql`) | 1576 | `fd2418e2be1711ef90826c9d6b612aec` |
| `tests/v5.4.2-12/battery-12.sql` (= `review/battery-12-frozen-r2.sql`) | 922 | `89277c1e6a47e075bced6639a79bf926` |

Frozen. Review the frozen copy; if it changes under you, stop and say so. **Do
not edit any file in the repo.** Everything in the round-1 brief
(`review-brief-12.md`) still applies: authority, environment, how to run,
rules of engagement, out-of-scope list. Read it first if you did not review
round 1.

## What round 1 found, and what this revision did

Two reviewers, independently (Codex stalled and was cancelled). The patch
header now carries a "Review round 1" block; the table below maps each
finding to the change and the battery check that pins it.

| # | Finding (who) | Change | Pinned by |
|---|---|---|---|
| 1 | tally_app could move its own `tenants.cutover_date` — end its own gate, or move go-live past a test then filed as "migrated" with an asserted result (both) | cutover_date is platform-set: tally_app may change it only as a platform admin; owner/superuser may (onboarding). Logged in `tenant_configuration_history` (recorder re-issued with the one added key; its known-key CHECK widened) | E0, E0b; mutation M8 |
| 2 | Supersession unconstrained: a derived failure replaced by a bare inconclusive_reason or a weaker record; a re-dated correction lengthens the window (both) | A correction must keep the test_date, may not weaken `record_basis` (date-only < migrated_full < recorded), and a test with readings may be corrected only by one with readings | C4, C5, C5b, C5c, C5d; M7 |
| 3 | Gate lapsed at `cutover + 6 months`, not the inverse of A-2's `anchor − 6 months` at month ends (both) | `supervisor_gate := weak AND (cutover IS NULL OR (anchor − 6 months)::date < cutover)` | F10 (day-by-day sweep, cutovers 03-31 and 08-31); M6 |
| 4 | "recorded" rows could be back-dated before go-live and escape the gate (Opus) | Invariant is now two-sided: every migrated test ≤ cutover ≤ every recorded test; enforced on insert and on cutover change | E6, E7; M9 |
| 5 | Equal-and-opposite beyond threshold filed inconclusive, pointer "conditional" (Opus) | New derived `found_defective`; pointer "failed" and `prior_test_failed` read it; outcome stays inconclusive (no direction) | A6 |
| 6 | Meter lock FOR UPDATE blocked FK-referencing inserts (both) | FOR NO KEY UPDATE (tests and absence declarations) | two-session re-run: 11 ms, was ~3 s |
| 7 | Tenant FOR SHARE deadlocked vs a session that touched a meter then its tenant (Fable) | FOR KEY SHARE on insert (all bases, since recorded now checks cutover too); the cutover change self-upgrades to FOR UPDATE | two-session re-run: no deadlock |
| 8 | Trailing zeros beyond 4 dp gave the stored max a different scale (Opus) | Derivation casts to `numeric(14,4)` before the formula | A16 |
| 9 | Cutover trigger not ENABLE ALWAYS (both) | Fixed | I2 |
| 10 | notes not type-checked; precondition hint silent on `not_tested`; `psql -f` non-transactional undocumented (Fable) | Fixed / documented | A10g |
| — | Not changed, recorded as residuals: meter location still tally_app-writable (R5, Opus); omitted load points undetectable (R15, Fable); date corrections impossible pending Kyle (R13); platform-only rule names tally_app (R14) | | |

Also added after the fold: a tenant not visible to the session now raises
`foreign_key_violation` before the cutover check reads NULL (D1b).

## Verification (re-run it)

- Strict apply ×2 clean; AC-32 passes.
- Battery **102 PASS**, zero failures. Regressions 28 / 58 / 41.
- Mutation: nine guards broken one at a time (M1–M9), each caught by its check.

## What I want from round 2

1. **Confirm or refute each fix above** against its round-1 repro. Did any fix
   close the reported shape but leave a sibling open? (The A-2 review's second
   round found the first fix was the same defect mirrored — hunt for that.)
2. **The new code is the new attack surface.** In particular:
   - The two-sided cutover invariant and its locking: a recorded insert, a
     migrated insert and a cutover change interleaved in every order. Can the
     invariant be violated? Can the new FOR UPDATE self-lock deadlock?
   - `current_user = 'tally_app' AND NOT is_platform_admin()`: any path by
     which a tenant-level session changes cutover_date (a definer function, a
     trigger on another table, an INSERT … ON CONFLICT on tenants)?
   - The supersession rules: can a correction chain (A superseded by B,
     B by C) achieve what one step cannot?
   - The re-issued `record_tenant_configuration_change()` — verbatim but for
     one key? Any behaviour change for the thirteen original keys?
   - `found_defective` on every path: date-only with each outcome, reason-
     inconclusive, derived, superseded.
3. Anything round 1 missed.

Same deliverable as round 1: findings most severe first, each with a runnable
repro and real output, the finding separate from any fix, and whether the fix
was measured; then what you checked and found sound.
