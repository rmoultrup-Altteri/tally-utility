# Review brief: v5.4.2-21 r4, scoped to the r3→r4 diff

**Date:** 2026-10-14. **Kind:** patch review, round 4, scoped to the diff.
**Reviewers:** Opus, Fable, Codex, independently.

## Frozen files

Check the hashes first.

| File | md5 |
|---|---|
| `tests/v5.4.2-21/review/patch-21-frozen-r4.sql` | `649db2b7094e585adde761f69a89a126` |
| `tests/v5.4.2-21/review/battery-21-frozen-r4.sql` | `60a45bb255ce9b5ede13ab6d61f5e7ce` |
| `tests/v5.4.2-21/review/labels-21-frozen-r4.sh` | `9c2eb69f2ee7c8da5fd714f2af49993c` |
| `tests/v5.4.2-21/review/mutations-21-frozen-r4.py` | `5a51b7cc5a92ccd9a005d022db815184` |

The patch diff is in `diff-21-r3-r4.diff`. `review-findings-21-r3.md` covers H1–H4.

## What changed

- **H1** (Opus B1, Fable B1, the same item). The supervisor guard fires on `role` too.
  - Taking a user out of tenant_admin requires `session_is_supervisor()`.
  - Taking a user out of platform_admin requires `is_platform_admin()`.
  - Granting a role stays the -13 grant guards'.
  - Tests: U3k–m; mutation M49d. The invariant's trigger string now reads `OF cognito_sub, is_active, role`.
- **H2** (Codex S1). LR6 and LR7 run B in the background, observe it blocked by A, catch the 55P03 inside B, and read B's own `lock_timeout`.
- **H3** (Codex S2). U3j reads back the state after each step.
- **H4.** Residual R10.

## Results

- Strict apply, twice.
- `tests/ci.sh`: all pass, 32 steps.
- `battery-21`: 143 checks.
- `labels-21.sh`: 9 cases.
- `mutations-21.py`: 68 of 68 caught.

## What to answer

1. Is H1 complete? Consider every way to remove an administrator's power through `users`: role, `is_active`, the binding, the id, the tenant, and combinations in one statement or across two.
2. Did r4 break anything?
3. Is any new check weaker than its label?

## How to probe, and output

As in round 3: your own clone, no role changes, no mutation runs. Write `tests/v5.4.2-21/review/<reviewer>-r4.md`: a verdict, then B…, S…, N…, each marked executed or predicted. Final message under 2 KB.
