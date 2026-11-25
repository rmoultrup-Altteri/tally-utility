# Review brief: v5.4.2-24 r13 — tests only (confirmation)

**Date:** 2026-11-24. **Kind:** confirmation of round 13's test changes. **Reviewer:** Opus alone (as for -30 r6). Do not read other reviewers' files for this round.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r13.sql` | `37630681b0dd63235ca3ab5c11b0b326` |
| `tests/v5.4.2-24/review/battery-24-frozen-r13.sql` | `0ec62ea358e5d69968595f0e2d02fee8` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r13.sh` | `360dea4db148825d696134bfa30e0502` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r13.py` | `d4b925f76a1c370dce147059f01b5bc8` |
| `tests/v5.4.2-24/review/ci-24-frozen-r13.diff` | `ec30f74364228bf3f325a1958583d01b` |
| `tests/v5.4.2-24/review/r12-to-r13.diff` | `9bbb3fc99b1453a266c8bc59a92e3377` |

**The patch is byte-identical to frozen r12** (same md5), which Opus, Fable and Codex all called ready. So are the race script and the ci diff. `r12-to-r13.diff` is the battery and mutation-runner changes only.

## What changed

Read `application/wave2-build-2026-10-15/v5.4.2-24-r13-plan.md`. In short:

1. **S4c's pending term** (your r12 S1; Codex r12 S1; Fable r12 N1): a receipt's payment not voided and dated by the day counts its amount where no posting entry is dated by that day, whatever its status. Fixtures P25 (pending, posting entry written, left pending) and P25b (posting entry dated two days after the payment). The author ran the battery with r12's term restored: S4c failed.
2. **S4d removed** (your r12 N3).
3. **D2 split** into D2, D2b, D2c (Fable r12 N3); M118 and M138 now name D2c, M129 and M175 D2b, M171 stays at D2.
4. **A flake fixed:** the fixture helpers named rows by the last four hex digits of the id, so a random id could take a fixture's payment number (P9, 23505, seen once in a full mutation run). A random id now names its rows by twelve.

## What to answer

1. Is S4c now right for both of your r12 shapes, and for every other shape you know of (a payment voided after its entry; a posting entry undone; a deposit)? Is any term now counted twice or not at all?
2. Do P25 and P25b test what they claim, and does the restored-term run show S4c catching it (reproduce it)?
3. Do the re-pointed mutations name the check that genuinely tests their defect?
4. Does the helper change alter any fixture's number, or any check that reads a number?

## Results so far (reproduce what you can)

- Strict apply twice; `battery-24.sql`: 355 checks; races: 29 (unchanged).
- `mutations-24.py`: 169 of 169 caught, each at its named check, in one full run (2026-11-24).
- `tests/ci.sh`: 61 steps, all pass (2026-11-24, r13, on `tally` carrying -30).

## How to probe

As in the r12 brief: your clone `rv24opus` of `tally`, TEMP revoked, the frozen patch applied strictly. Do not create, drop or alter roles; do not run `mutations-24.py` (fixed name `m24`) or `tests/ci.sh`; modify no repo file but your output. Drop the clone when done.

**Output:** `tests/v5.4.2-24/review/opus-r13.md`: verdict "ready" or "not yet"; items B, S, N, each executed or predicted, with evidence.
