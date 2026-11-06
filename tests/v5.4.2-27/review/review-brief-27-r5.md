# Review brief: v5.4.2-27 r5 — a narrow confirmation round

**Date:** 2026-11-06. **Kind:** patch review, round 5, narrow.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's r5 files. Your own earlier files, and the merged plans, you may read.

All three of you said "ready" on r4. Ryan asked for this short round before the mirror, so that the comments mirrored into `tu.sql` are accurate. **Review only what changed from r4** (`r4-to-r5.diff` and the test changes listed below), and say whether r5 is still ready. Do not re-review r4 as a whole.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-27/review/patch-27-frozen-r5.sql` | `50e7b43da4def4e69883120b5b558333` |
| `tests/v5.4.2-27/review/battery-27-frozen-r5.sql` | `52e862a80bb6b894162b3df0d42d68c4` |
| `tests/v5.4.2-27/review/shortfall-27-frozen-r5.sh` | `bc7fbafff50e007e80482c51fdebe66f` |
| `tests/v5.4.2-27/review/mutations-27-frozen-r5.py` | `81d0f48a0d8a38c73f00118a609e2f5a` |
| `tests/v5.4.2-27/review/r4-to-r5.diff` | `b91fa67f34bd151dd7b5be72a58ca157` (the patch, r4 to r5) |

The live copies are identical today.

## What changed (plan: `application/wave2-build-2026-10-15/v5.4.2-27-r5-plan.md`)

1. **`cash_drawn_at`'s comment** (Codex r4 S1). It now says that rows written in a take-back's own transaction count at its instant, for both shortfall terms. New battery check J2 (Codex's probe 15) and mutation M64.
2. **An undo and its credit's escheat in one statement** (Opus r4 S1). In `enforce_shortfall_application`'s re-read: if this transaction made the credit's move (`status_recorded_at = now()`), it refuses with 23514, "write the undo in a statement of its own". Otherwise it still raises 40001. Battery E21 (refused in one writable CTE) and E21b (admitted as separate statements); mutation M66.
3. **SR11** checks the SQLSTATE 40001 in the verbose error as well as the message (Codex r4 S2).
4. **E21c**: a `gave_to_escheated` sent by the app is replaced (Fable r4 N1).
5. **Notes:** the race script's header names its id collision with -23's battery (Fable r4 N3). The patch header gains the r5 line and the counts.

## To check

- Is the 23514/40001 split right? Can `status_recorded_at = now()` be true for an escheat made by **another** transaction (one that began at the same instant), or false for one this transaction made (a superuser's chosen status time)? What does each case then do, and is that acceptable?
- Is the corrected comment accurate now for both terms?
- Do J2, E21, E21b, E21c and the new SR11 fragment test what their labels say?

## Results so far (reproduce what you can)

- **Strict apply, twice:** clean; the second run is skipped by its marker.
- **`battery-27.sql`:** 146 checks. On frozen r4 only E21 fails (40001); J2, E21b and E21c pass there too.
- **`races/shortfall-27.sh`:** 21 results.
- **`mutations-27.py`:** 74 of 74 caught, each at its named check as the first failure.
- **-23's own tests with -27 r5:** battery-23 409/409 (with -30 after -27), races cash-23.sh 51/51.
- **`tests/ci.sh`:** 58 steps, all pass, with -25, -26, -27 and -30 pending.

## How to probe, restrictions, output

As r4 (`review-brief-27-r4.md`, "How to probe"):
- Opus and Fable clone into `rv27opus` / `rv27fable` and apply the frozen r5 patch strictly.
- Codex reviews the source only, and writes probe files into `tests/v5.4.2-27/review/codex-r5-probes/` for the author to run.
- No role DDL, no `mutations-27.py`, no `ci.sh`. Modify no file except your output. Drop your clone when done.

**Output:** `tests/v5.4.2-27/review/<you>-r5.md` (opus, fable, codex), with a verdict, "ready" or "not yet", and B/S/N items marked executed or predicted. Keep it short: this round is narrow.
