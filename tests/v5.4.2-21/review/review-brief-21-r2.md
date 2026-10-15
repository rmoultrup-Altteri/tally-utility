# Review brief: v5.4.2-21 r2

**Date:** 2026-10-14. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's r2 files.

## Frozen files

Check the hashes first. Stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-21/review/patch-21-frozen-r2.sql` | `11aad26ff3f58cb4ac7245d4ff421a6a` |
| `tests/v5.4.2-21/review/battery-21-frozen-r2.sql` | `08c7fd59501322ffe18ac91c2d94c415` |
| `tests/v5.4.2-21/review/labels-21-frozen-r2.sh` | `2a3c8dadf6efe5631bf46dbd56df0c52` |
| `tests/v5.4.2-21/review/mutations-21-frozen-r2.py` | `9e6791807686e8380a8d87aa1d8c61cc` |

`tests/v5.4.2-21/review/diff-21-r1-r2.diff` is the patch's r1→r2 diff.

## What changed

All three r1 verdicts were "not yet". `tests/v5.4.2-21/review/review-findings-21-r1.md` lists every finding (F1–F14) and what r2 does about it. In short:

- **F1.** An unclassifiable surcharge (no version visible at the coordinate) is now a gap.
- **F2.** The arithmetic is read at the bill's snapshot coordinate. With no snapshot, the snapshot check refuses.
- **F3.** Label keys (key, entity, tenant) are write-once for every role.
- **F4.** For `tally_app`, binding a Cognito identity and changing `is_active` require `session_is_supervisor()`. Ryan has been told of the onboarding consequence.
- **F5–F7.** On the void and the ledger:
  - the void's charge is the bill's customer's;
  - `reference_type = 'invoice_void'` if and only if `void_reversal`;
  - one void reversal per entry.
- **F8.** The label lock waits at most 5 s; the header is rewritten.
- **F9.** `retired_by` is stamped from `app.user_id`.
- **F10.** The retention invariant checks the labels' three guards. The new `assert_wave1_guard_invariants()` checks the other new guards.
- **F11.** A gas rider no longer needs the commodity rate. This is a drafting call, reported to Ryan.
- **F12–F14.** Tests.

## Results (reproduce them)

- Strict apply, twice.
- `tests/ci.sh`: all pass, 32 steps, including the new wave-1 invariant step.
- `battery-21`: 131 checks.
- `labels-21.sh`: LR1–LR6 and LR2b.
- `mutations-21.py`: 62 of 62 caught at their named checks.
- Older tests changed since r1:
  - battery-15 gains C8b, run as the owner; the -15 guard refuses first;
  - battery-20 I1's line carries its rate.

## What to answer

1. **Is each finding you raised fixed, and fixed correctly?** Re-run your r1 repros against r2.
2. **Is there a path around any r2 change?** In particular:
   - the supervisor guard (other roles, an INSERT path, a platform admin of another tenant, the owner);
   - the key freeze;
   - the snapshot coordinate (can a caller choose it?);
   - the lock timeout's save and restore (does it leak into the caller's transaction on success or on failure?).
3. **Has r2 broken anything that r1 had right?**
4. **The two drafting calls (F4's onboarding consequence, F11).** Is either wrong on the merits?
5. **Tests.** Is any new check weaker than its label?

## How to probe

Same as round 1:
- your own clone (`rv21opus` / `rv21fable`) from `tally`, with TEMP revoked and the frozen r2 patch strict-applied;
- no role changes;
- do not run `mutations-21.py`;
- touch no repo file except your output;
- drop your clone when done.

## Output

Write `tests/v5.4.2-21/review/<reviewer>-r2.md` with:
- a verdict ("ready" or "not yet");
- blocking items (B1…);
- should-fix items (S1…);
- notes (N1…).

Mark each claim executed or predicted. Your final message is under 2 KB.
