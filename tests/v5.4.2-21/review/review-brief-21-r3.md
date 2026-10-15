# Review brief: v5.4.2-21 r3, scoped to the r2→r3 diff

**Date:** 2026-10-14. **Kind:** patch review, round 3, scoped to the diff.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's r3 files.

## Frozen files

Check the hashes first. Stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-21/review/patch-21-frozen-r3.sql` | `57f2d1f007b41e4aee2b9ad7568aff4e` |
| `tests/v5.4.2-21/review/battery-21-frozen-r3.sql` | `e3a432c03f23b263d74a43ede58fdce2` |
| `tests/v5.4.2-21/review/labels-21-frozen-r3.sh` | `0056d791653ba17f17f172b86db6ed2e` |
| `tests/v5.4.2-21/review/mutations-21-frozen-r3.py` | `5fb86c42895f9bc6e6c62d59228675db` |

The patch's r2→r3 diff is in `tests/v5.4.2-21/review/diff-21-r2-r3.diff`.

## What changed

The r2 verdicts were: Codex "ready"; Opus "not yet" (B1); Fable "not yet" (B1). `review-findings-21-r2.md` gives each disposition (G1–G7).

- **G1** (Fable B1). The arithmetic is read at `(snapshot.valid_at, now())`. The date is the bill's own; the knowledge is current, as the surcharge sibling uses.
  - The snapshot's `recorded_at` is the caller's to choose, and could hide a later reclassification.
  - This resolves Codex r1 B2 together with Fable r2 B1.
- **G2** (Opus B1). Binding, reviving or switching off a user who is, or was, a platform administrator requires `is_platform_admin()`.
- **Tests.**
  - L7a–c: the caller's `lock_timeout` is restored, on both branches and after a refusal.
  - LR7: the location-type branch's 5 s wait.
  - AR1: Fable's two-instant case.
  - A8: a complete correction issued with every deferred check.
  - U3h–j: the platform-administrator cases.
  - Mutations M46b, M49c, M53b, M60, M60b.
- **Text.** Residuals R8 (reversal links on rows that are not void reversals) and R9 (`line_item_carries_base` at the period end, pre-existing). AC-43 gains the onboarding consequences.

## Results (reproduce them)

- Strict apply, twice.
- `tests/ci.sh`: all pass, 32 steps.
- `battery-21`: 139 checks.
- `labels-21.sh`: LR1–LR7, LR2b and AR1.
- `mutations-21.py`: 67 of 67 caught.

## What to answer

Scope is the r2→r3 diff and its tests:
1. **Is G1 right?** Can a caller still steer the classification, through the date, the knowledge, or the snapshot's presence? Does reading `now()` refuse a legitimate correction (a historical-mode rebill of a since-reclassified item)? If so, is that the right side to fail on?
2. **Is G2 complete?** Consider an INSERT of a bound platform administrator, a role change in the same UPDATE, and a platform administrator of another tenant.
3. **Has r3 broken anything** r2 had right?
4. **Is any new check weaker than its label?**

## How to probe, and output

As in round 2:
- your own clone, named `rv21opus` / `rv21fable`, with TEMP revoked and the frozen r3 patch strict-applied;
- no role changes;
- do not run the mutations.

Write `tests/v5.4.2-21/review/<reviewer>-r3.md`: a verdict, then B…, S…, N…, each marked executed or predicted. Final message under 2 KB.
