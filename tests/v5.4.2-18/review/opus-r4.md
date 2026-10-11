# v5.4.2-18 review round 4 (delta) — Opus

Hash: patch 08e03723… (877 lines, = sql/v5.4.2-18-…); battery unchanged (294ea5f8…). The diff from r3 is the whole change.

Runs: strict apply on a clean clone of `tally` — OK; battery-18 107 PASS, 0 FAIL; migration-18.py with PATCH18 = frozen r4 — 54 PASS, all pass (P3a–c with the historical delegation fixture, P7am, P7an).

## Verdict: READY (R10 remains Ryan's)

r3 S1 confirmed fixed:
- My r3 reproduction (unprotected crossed_meters, 1990–1995, units_invariant true, reissue, no protected twin) now aborts the migration ("nothing to be compared with").
- A twin that overlaps only part of the range (protected 1998–2000 against unprotected 1990–2000), with different facts (reissue, units), aborts with "differ from the protected row".
- Nothing broke: the P3 fixtures adopt; the closing NOTICE counts rows (16 on the real data).

### Note (not blocking)
The twin test is "some protected row overlaps", not "protected rows cover the delegation's dates". A delegation whose range is only partly twinned, with equal facts on the twinned part, passes, and its untwinned days are compared with nothing. Because the facts are a classification of the cause, an equal overlapping twin is adequate evidence. If the wording "in force over its dates" is meant literally, either test coverage with a datemultirange or soften the comment.
